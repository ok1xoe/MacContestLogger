import Foundation
import Testing
@testable import MCLCore

/// `EntryCommandPlan` against `runCommand` (`EP:368-457`), the command branch of `logQso` (`EP:473-481`) and the
/// `AppState` methods it calls (`AS`). Composable-local functions are not reachable for a JVM gate, so the
/// tables follow the source; JVM primitives are pinned from a maintainer-only probe.
@Suite struct EntryCommandPlanTests {

    private typealias E = EntryCommandEffect

    private static func context(freq: Int64 = 14_025_000, locked: Bool = false, rst: String = "59",
                                script: [String: [String]] = [:]) -> EntryCommandContext {
        EntryCommandContext(
            currentFreqHz: freq, modeLocked: locked, primaryMode: .cw, rstSent: rst, repeatSeconds: 2.5,
            stationOperator: "", stationCall: "ok1xoe", appVersion: "1.2.3", runtime: "Swift 6.1 · macOS 15.5",
            scriptsDir: "/s", loadScript: { script[$0] }, tour: nil, now: Date(timeIntervalSince1970: 0),
            usesRoverQth: true, isKnownLocation: { $0 == "NY" ? true : ($0 == "XX" ? false : nil) })
    }

    /// The body without the leading `clearCall` and the trailing `focusCall`.
    private static func body(_ command: CallFieldCommand, _ ctx: EntryCommandContext = context()) -> [E] {
        let effects = EntryCommandPlan.plan(command, context: ctx)
        #expect(effects.first == .clearCall)
        #expect(effects.last == .focusCall)
        return Array(effects.dropFirst().dropLast())
    }

    private static func status(_ key: String, _ args: Translator.Arg...) -> E {
        .status(EntryStatus([ContestMessage(key, parts: args.map { .value($0) })]))
    }

    // MARK: - parse for Enter (L11)

    /// Probe `parse`: the parser throws `Overflow`; Kotlin's window handler then quits — Swift shows it as invalid.
    @Test func overflowIsShownAsInvalid() {
        let cases: [(String, String)] = [
            ("99999999999999999", "99999999999999999"), ("9223372036854775807", "9223372036854775807"),
            ("-9223372036854775807", "-9223372036854775807"), ("/99999999999999999", "99999999999999999"),
            ("+99999999999999999", "+99999999999999999"), (" 18446744073709551616 ", "18446744073709551616"),
        ]
        for (input, number) in cases {
            for freq: Int64 in [0, 14_025_000] {
                #expect(EntryCommandPlan.parseForEnter(input, currentFreqHz: freq)
                        == .invalid(message: number + " kHz neleží v žádném pásmu"), "\(input) @\(freq)")
                #expect(EntryCommandPlan.isCommand(input, currentFreqHz: freq))
            }
        }
        #expect(EntryCommandPlan.parseForEnter("99999999999999999", currentFreqHz: 14_025_000, ctrlEnter: true)
                == .invalid(message: "99999999999999999 kHz neleží v žádném pásmu"))
    }

    /// Probe `parse` rows without an exception pass through unchanged.
    @Test func parseResultsAsMeasured() {
        #expect(EntryCommandPlan.parseForEnter("9223372036854775", currentFreqHz: 14_025_000)
                == .qsy(freqHz: -9_223_372_036_840_776_616))
        #expect(EntryCommandPlan.parseForEnter("9223372036854775", currentFreqHz: 0)
                == .invalid(message: "9223372036854775 kHz neleží v žádném pásmu"))
        #expect(EntryCommandPlan.parseForEnter("025", currentFreqHz: 14_025_000) == .qsy(freqHz: 14_025_000))
        #expect(EntryCommandPlan.parseForEnter("14025.1", currentFreqHz: 0) == .qsy(freqHz: 14_025_100))
        #expect(EntryCommandPlan.parseForEnter("OK1XOE", currentFreqHz: 0) == nil)
        #expect(!EntryCommandPlan.isCommand("OK1XOE", currentFreqHz: 0))
    }

    // MARK: - effects per command (`EP:369-455`)

    @Test func qsyFormatsTheFieldAndTheStatus() {
        #expect(Self.body(.qsy(freqHz: 14_025_005)) == [
            .setFrequency(text: "14025.01"), .rigQsy(hz: 14_025_005), .status(.verbatim("QSY na 14025.01 kHz")),
        ])
    }

    /// L11 and: the wrapped negative frequency fills the field and the status (probe `qsy`) and
    /// goes to the shared tuning (`state.qsy` is local for any value); the rig model never sends it to CAT.
    @Test func negativeQsyGoesToTheSharedTuningOnly() {
        #expect(Self.body(.qsy(freqHz: -9_223_372_036_840_776_616)) == [
            .setFrequency(text: "-9223372036840776.00"), .rigQsy(hz: -9_223_372_036_840_776_616),
            .status(.verbatim("QSY na -9223372036840776.00 kHz")),
        ])
        #expect(Self.body(.qsy(freqHz: 0)) == [
            .setFrequency(text: "0.00"), .rigQsy(hz: 0), .status(.verbatim("QSY na 0.00 kHz")),
        ])
    }

    @Test func changeMode() {
        #expect(Self.body(.changeMode(mode: .rtty)) == [
            .setMode(.rtty), .rigMode(.rtty, freqHz: 14_025_000), Self.status("Mód %s", "RTTY"),
        ])
        #expect(Self.body(.changeMode(mode: .rtty), Self.context(locked: true))
                == [Self.status("Mód určuje závod (%s)", "CW")])
    }

    @Test func login() {
        #expect(Self.body(.login(operator: "")) == [.openDialog(.operatorLogin)])
        #expect(Self.body(.login(operator: "  ")) == [.openDialog(.operatorLogin)])
        #expect(Self.body(.login(operator: " ok1abc ")) == [.setOperator("OK1ABC"), Self.status("Operátor: %s", "OK1ABC")])
        #expect(Self.body(.login(operator: "straße")) == [.setOperator("STRASSE"), Self.status("Operátor: %s", "STRASSE")])
    }

    @Test func simpleCommands() {
        let table: [(CallFieldCommand, [E])] = [
            (.wipeLog, [.openDialog(.wipeLogConfirm)]),
            (.exportAdif, [.menuAction("settings.export")]),
            (.importLog, [.menuAction("settings.import")]),
            (.exportCabrillo, [.menuAction("settings.exportCabrillo")]),
            (.openSetup, [.menuAction("settings.open")]),
            (.rescore, [.rescore(manual: true)]),
            (.autoRunSp(enabled: true), [.setAutoRunSp(true), Self.status("Automatické přepínání Run/S&P zapnuto")]),
            (.autoRunSp(enabled: false),
             [.setAutoRunSp(false), Self.status("Automatické přepínání Run/S&P vypnuto (Alt+F11 zapne)")]),
            (.esmOn, [.setEsm(true), Self.status("ESM zapnuto — Enter vysílá zprávy")]),
            (.esmOff, [.setEsm(false), Self.status("ESM vypnuto")]),
            (.openSettingsTab(tabKey: "winkey"), [.openSettingsTab("winkey")]),
            (.cutNumbers(style: .tn), [.cutNumbers(.tn), Self.status("Cut čísla: %s", "T a N (097 → TN7)")]),
            (.cutNumbers(style: nil), [.cutNumbers(nil), Self.status("Cut čísla vypnuta")]),
            (.invalid(message: "RIT: zadej posun"), [.status(.verbatim("RIT: zadej posun"))]),
        ]
        for (command, expected) in table {
            #expect(Self.body(command) == expected, "\(command)")
        }
    }

    /// Decision 14: the Swift runtime instead of `Java <version>`.
    @Test func version() {
        #expect(Self.body(.version) == [.status(.verbatim("MacContestLogger ")
                .appending(.verbatim("1.2.3")).appending(.verbatim(" · Swift 6.1 · macOS 15.5")))])
        var ctx = Self.context()
        ctx.appVersion = nil
        let effects = Self.body(.version, ctx)
        guard case .status(let status) = effects.first else {
            Issue.record("no status")
            return
        }
        #expect(status.czech == "MacContestLogger vývojová verze · Swift 6.1 · macOS 15.5")
        #expect(EntryTexts.runtimeDescription().hasPrefix("Swift 6."))
        #expect(EntryTexts.runtimeDescription().contains(" · macOS "))
    }

    @Test func toggles() {
        let table: [(CallFieldCommand.Setting, Bool, E)] = [
            (.cqRepeat, true, Self.status("Opakování CQ po %s (Esc nebo psaní volačky zastaví, Ctrl+R změní)", "2.5 s")),
            (.cqRepeat, false, Self.status("Opakování CQ vypnuto")),
            (.workDupes, true, Self.status("Dupe v Run se dělá jako nové QSO (WORKDUPE)")),
            (.workDupes, false, .status(.verbatim("Dupe v Run: QSO B4 (NOWORKDUPE)"))),
            (.autoReload, true, Self.status("Při startu se otevře poslední závod (AUTORELOAD)")),
            (.autoReload, false, Self.status("Při startu úvodní dialog (NOAUTORELOAD)")),
            (.postContest, true, Self.status(
                "Dodatečné zadání: čas QSO zadávej do pole Čas (HHmm, přes půlnoc se datum posune samo), nic se nevysílá")),
            (.postContest, false, Self.status("Dodatečné zadání ukončeno — QSO zase dostávají aktuální čas")),
        ]
        for (setting, on, status) in table {
            #expect(Self.body(.toggle(setting: setting, on: on)) == [.toggle(setting, on), status])
        }
    }

    /// `EP:400-416`: program actions; DEBUGCAT and RESET go to the rig model, BEACONS asks the app for the file
    /// (the network ones are handled by the app).
    @Test func appActions() {
        let table: [(CallFieldCommand.Action, [E])] = [
            (.exit, [.exitRequest(confirm: true)]),
            (.exitNow, [.exitRequest(confirm: false)]),
            (.wipeLogNow, [.wipeLogNow]),
            (.closeContest, [.menuAction("contest.none")]),
            (.newContest, [.openDialog(.newContest)]),
            (.openContest, [.openDialog(.contestBrowser)]),
            (.copyLog, [.copyLog]),
            (.reload, [.reloadAll]),
            (.reopen, [.reopenLog]),
            (.logout, [.setOperator("OK1XOE"), Self.status("Operátor: %s", "OK1XOE")]),
            (.broadcastLog, [.broadcastLog]),
            (.debugCat, [.rig(.debugCat)]),
            (.resetInterfaces, [.rig(.resetInterfaces)]),
            (.loadBeacons, [.menuAction("beacons.load")]),
        ]
        #expect(table.count == CallFieldCommand.Action.allCases.count)
        for (action, expected) in table {
            #expect(Self.body(.appAction(action: action)) == expected, "\(action)")
        }
        var ctx = Self.context()
        ctx.stationOperator = "ok2op"
        #expect(Self.body(.appAction(action: .logout), ctx) == [.setOperator("OK2OP"), Self.status("Operátor: %s", "OK2OP")])
        ctx.stationOperator = ""
        ctx.stationCall = " "
        #expect(Self.body(.appAction(action: .logout), ctx) == [])
    }

    /// NETON and NETOFF go to the app (the network log); their status comes from the model.
    @Test func networkCommandsGoToTheApp() {
        #expect(Self.body(.networkOn) == [.networkOn])
        #expect(Self.body(.networkOff) == [.networkOff])
    }

    /// `EP:432`: SPOTME spots the station at the field's frequency; a QSY earlier in a script moves it.
    @Test func spotMeUsesTheFieldFrequency() {
        let ctx = Self.context(freq: 14_025_000)
        #expect(Self.body(.spotMe(comment: "CQ TEST"), ctx) == [.spotMe(freqHz: 14_025_000, comment: "CQ TEST")])
        #expect(Self.body(.spotMe(comment: ""), ctx) == [.spotMe(freqHz: 14_025_000, comment: "")])
    }

    /// `EP:436-440`: the rig commands go to the rig model.
    @Test func rigCommandsGoToTheRigModel() {
        let table: [(CallFieldCommand, EntryRigCommand)] = [
            (.otherVfo(freqHz: 14_030_000), .otherVfo(freqHz: 14_030_000)), (.split(txFreqHz: 0), .split(txFreqHz: 0)),
            (.split(txFreqHz: 14_027_000), .split(txFreqHz: 14_027_000)), (.splitOff, .splitOff),
            (.rit(offsetHz: -120), .rit(offsetHz: -120)), (.swapVfo, .swapVfo),
        ]
        for (command, rig) in table {
            #expect(Self.body(command) == [.rig(rig)], "\(command)")
        }
    }

    // MARK: - QSO party (`AS:3846-3943`)

    @Test func tour() throws {
        #expect(Self.body(.setTour(params: "")) == [Self.status(
            "TOUR vypnuto — zadej TOUR hhmm/mm (např. TOUR 1200/30) nebo hhmm/mm do pole Snt")])
        // Without an argument the Snt field is taken when it holds a slash (`EP:426`).
        let tour = try #require(Tour.parse("1200/30"))
        let set = EntryTexts.tourSet(tour)
        #expect(Self.body(.setTour(params: ""), Self.context(rst: "1200/30")) == [.setTour(tour, status: set)])
        #expect(set.czech == "TOUR 1200/30: sezení po 30 min od 1200Z — v každém sezení jde stanice pracovat znovu")
        #expect(Self.body(.setTour(params: "1200/2")) == [Self.status(
            "TOUR: neplatné „%s“ — formát hhmm/mm, sezení aspoň 5 minut (např. 1200/30)", "1200/2")])
        #expect(Self.body(.tourOff) == [.tourOff(status: .tr("TOUR vypnuto — dupe za celý závod"))])
        var ctx = Self.context()
        ctx.tour = tour
        ctx.now = Date(timeIntervalSince1970: 13 * 3600 + 10 * 60)
        #expect(Self.body(.setTour(params: ""), ctx) == [.status(EntryStatus.tr("TOUR %s: aktuální sezení od ", "1200/30")
                .appending(.verbatim("1300Z")))])
    }

    @Test func bonusRoverCountyLine() {
        #expect(Self.body(.bonusStations(calls: "")) == [.openDialog(.bonusStations)])
        #expect(Self.body(.bonusStations(calls: "w1aw, k1a")) == [
            .setBonusStations(["W1AW", "K1A"], status: .verbatim("Bonusové stanice (2): W1AW K1A")),
        ])
        #expect(Self.body(.roverQth(county: "")) == [.openDialog(.roverQth)])
        #expect(Self.body(.roverQth(county: "ny")) == [.setRoverQth("NY"), .status(.verbatim("Rover QTH: NY"))])
        #expect(Self.body(.roverQth(county: "xx")) == [.setRoverQth("XX"), .status(.verbatim("Rover QTH: XX")
                .appending(.verbatim(" — ")).appending(.tr("pozor: %s není v seznamu okresů závodu", "XX")))])
        #expect(Self.body(.countyLine(counties: "")) == [.openDialog(.countyLine)])
        #expect(Self.body(.countyLine(counties: "ny,ab")) == [
            .setCountyLine(["NY", "AB"]), Self.status("County line %s: každé QSO se zapíše %s×", "NY/AB", 2),
        ])
        #expect(Self.body(.countyLineOff) == [.setCountyLine([]), .status(.verbatim("County line vypnuto"))])
    }

    // MARK: - SCRIPT (`EP:438-454`)

    @Test func scriptRunsLinesInOrder() {
        let ctx = Self.context(script: ["run": ["7025", "+5", "CW", "TOUR", "SCRIPT run", "OK1ABC", "99999999999999999"]])
        #expect(Self.body(.runScript(name: "run"), ctx) == [
            .setFrequency(text: "7025.00"), .rigQsy(hz: 7_025_000), .status(.verbatim("QSY na 7025.00 kHz")),
            // `+5` is relative to the frequency the previous line set.
            .setFrequency(text: "7030.00"), .rigQsy(hz: 7_030_000), .status(.verbatim("QSY na 7030.00 kHz")),
            .setMode(.cw), .rigMode(.cw, freqHz: 7_030_000), Self.status("Mód %s", "CW"),
            // `CW` reset the report to 599, which has no slash: TOUR shows the state.
            Self.status("TOUR vypnuto — zadej TOUR hhmm/mm (např. TOUR 1200/30) nebo hhmm/mm do pole Snt"),
            Self.status("SCRIPT: vnořený skript „%s“ přeskočen", "RUN"),
            Self.status("SCRIPT %s: „%s“ není příkaz", "run", "OK1ABC"),
            .status(.verbatim("99999999999999999 kHz neleží v žádném pásmu")),
            Self.status("SCRIPT %s: provedeno %s příkazů", "run", 7),
        ])
    }

    @Test func missingScript() {
        #expect(Self.body(.runScript(name: "x")) == [Self.status("SCRIPT: skript „%s“ není v %s", "x", "/s")])
        #expect(Self.body(.runScript(name: "e"), Self.context(script: ["e": []]))
                == [Self.status("SCRIPT %s: provedeno %s příkazů", "e", 0)])
    }

    /// Every kind is planned (no case falls through to a crash) and starts/ends with the call field.
    @Test func everyCommandClearsAndRefocuses() {
        let samples: [CallFieldCommand] = [
            .qsy(freqHz: 1), .otherVfo(freqHz: 1), .split(txFreqHz: 1), .splitOff, .runScript(name: "x"),
            .rit(offsetHz: 1), .swapVfo, .changeMode(mode: .cw), .login(operator: ""), .wipeLog, .version,
            .exportAdif, .exportCabrillo, .importLog, .esmOn, .esmOff, .autoRunSp(enabled: true), .setTour(params: ""),
            .tourOff, .bonusStations(calls: ""), .roverQth(county: ""), .countyLine(counties: ""), .countyLineOff,
            .spotMe(comment: ""), .appAction(action: .exit), .toggle(setting: .cqRepeat, on: true),
            .cutNumbers(style: nil), .openSettingsTab(tabKey: "x"), .rescore, .openSetup, .networkOn, .networkOff,
            .invalid(message: "x"),
        ]
        #expect(Set(samples.map { EntryCommandKind($0) }).count == EntryCommandKind.allCases.count - 1)
        for command in samples {
            #expect(!Self.body(command).isEmpty, "\(command)")
        }
    }
}
