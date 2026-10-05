import Foundation

/// A status-line text of the entry window: translatable pieces concatenated without a separator (Kotlin
/// `tr(a) + tr(b)`, `"Pozor: $v"`, `tr(…) + "…"`). Translated where it is shown.
public struct EntryStatus: Equatable, Sendable {

    public let parts: [ContestMessage]

    public init(_ parts: [ContestMessage]) {
        self.parts = parts
    }

    /// Kotlin `tr(key, args…)`.
    public static func tr(_ key: String, _ args: Translator.Arg...) -> EntryStatus {
        EntryStatus([ContestMessage(key, parts: args.map { ContestMessage.Part.value($0) })])
    }

    /// A Kotlin string without `tr`.
    public static func verbatim(_ text: String) -> EntryStatus {
        EntryStatus([.verbatim(text)])
    }

    /// This text followed by `other`.
    public func appending(_ other: EntryStatus) -> EntryStatus {
        EntryStatus(parts + other.parts)
    }

    public func text(_ translator: Translator, decimalSeparator: String = ".") -> String {
        parts.map { $0.text(translator, decimalSeparator: decimalSeparator) }.joined()
    }

    /// The Czech text.
    public var czech: String {
        text(Translator.source)
    }
}

/// Fixed texts of the entry window that the core hands to the UI (`EP` = `ui/EntryPanel.kt`, `AS` = `ui/AppState.kt`
/// of v1.1.1). Keys are the Czech originals; the app translates them with `tr`.
public enum EntryTexts {

    /// What the local entry window cannot do (radio, keyer, spots, network).
    public static let unavailable = "Zatím nedostupné"

    // MARK: - note (Ctrl+N, `AS:911-929`)

    /// `AS:915` — Ctrl+N with an empty call and an empty logbook.
    public static let noteEmptyLog = "Ctrl+N: deník je prázdný"
    /// `AS:918` — prompt title for the QSO in progress.
    public static let noteTitleCurrent = "Poznámka k rozdělanému QSO"
    /// `AS:918` — prompt title for the last QSO (`%s` = its call).
    public static let noteTitleLast = "Poznámka k QSO %s"
    /// `AS:919` — prompt hint.
    public static let noteHint = "Uloží se do komentáře QSO"
    /// `AS:922` — the note waits for the QSO. The source key is spelt correctly ("Poznámka", with "á") and is the
    /// key the shipped `lang_en`/`lang_de` translate.
    public static let notePending = "Poznámka se uloží se zápisem QSO"
    /// `AS:926` — the note was saved to the last QSO (`%s` = its call).
    public static let noteSaved = "Poznámka uložena k %s"

    // MARK: - forced log (Ctrl+Alt+Enter, `EP:592-597`)

    /// Prompt title (`%s` = the call).
    public static let forcedTitle = "Vynucený zápis %s"
    public static let forcedHint = "Poznámka (prázdné = „Forced QSO“) — QSO se zapíše i s neplatnou výměnou"
    /// The comment of a forced QSO whose note was left blank (Kotlin `note.ifBlank { "Forced QSO" }`, not translated).
    public static let forcedDefaultNote = "Forced QSO"

    /// The note of a forced log: Kotlin `note.ifBlank { "Forced QSO" }`.
    public static func forcedNote(_ note: String) -> String {
        KotlinStrings.isBlank(note) ? forcedDefaultNote : note
    }

    // MARK: - post-contest paper time (`EP:483-492`)

    public static let paperTimeMissing = "Dodatečné zadání: zadej čas QSO (HHmm, nebo 2026-11-28 1432)"

    // MARK: - multiplier chips (`EP:1888-1893`)

    /// `shortState(s)`: the Czech translation key of the chip state (the app shows it through `tr`).
    public static func shortState(_ state: MultiplierEvalResult.MultiplierState) -> String {
        switch state {
        case .knownNewMultiplier: "NOVÝ"
        case .knownAlreadyWorked: "už"
        case .unknownAccepted: "neznámý"
        case .suspicious: "podezřelý"
        case .invalidFormat: "chybný"
        }
    }

    // MARK: - TOUR (`AS:3846-3876`)

    /// `setTour("")` — the current state; `nil` tour = off.
    public static func tourState(_ tour: Tour?, now: Date) -> EntryStatus {
        guard let tour else {
            return .tr("TOUR vypnuto — zadej TOUR hhmm/mm (např. TOUR 1200/30) nebo hhmm/mm do pole Snt")
        }
        let start: String = (try? tour.sessionStart(at: now)).map(hhmmZ) ?? ""
        return EntryStatus.tr("TOUR %s: aktuální sezení od ", .string(tour.format())).appending(.verbatim(start))
    }

    /// `setTour(params)` with a text `Tour.parse` rejects.
    public static func tourInvalid(_ params: String) -> EntryStatus {
        .tr("TOUR: neplatné „%s“ — formát hhmm/mm, sezení aspoň 5 minut (např. 1200/30)", .string(params))
    }

    /// `setTour(params)` after the setup was saved.
    public static func tourSet(_ tour: Tour) -> EntryStatus {
        let start = String(format: "%02d%02dZ", tour.startMinute / 60, tour.startMinute % 60)
        return EntryStatus.tr("TOUR %s: sezení po %s min od ", .string(tour.format()), .int(tour.durationMinutes))
            .appending(.verbatim(start))
            .appending(.tr(" — v každém sezení jde stanice pracovat znovu"))
    }

    public static let tourOff = "TOUR vypnuto — dupe za celý závod"

    /// `updateSetup` without an active contest.
    public static let noActiveContest = "Není aktivní závod"

    /// `DateTimeFormatter.ofPattern("HHmm'Z'").withZone(UTC)`.
    static func hhmmZ(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let parts: DateComponents = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d%02dZ", parts.hour ?? 0, parts.minute ?? 0)
    }

    // MARK: - run mode, ESM, toggles (`AS:1371-1376, 1777-1866, 2213-2222`)

    public static func esm(_ enabled: Bool) -> EntryStatus {
        enabled ? .tr("ESM zapnuto — Enter vysílá zprávy") : .tr("ESM vypnuto")
    }

    public static func autoRunSwitch(_ enabled: Bool) -> EntryStatus {
        enabled
            ? .tr("Automatické přepínání Run/S&P zapnuto")
            : .tr("Automatické přepínání Run/S&P vypnuto (Alt+F11 zapne)")
    }

    /// `repeatLabel()` = `String.format(Locale.US, "%.1f s", seconds)`.
    public static func repeatLabel(_ seconds: Double) -> String {
        JavaFormat.fixed(seconds, precision: 1) + " s"
    }

    public static func cqRepeat(_ on: Bool, repeatSeconds: Double) -> EntryStatus {
        on
            ? .tr("Opakování CQ po %s (Esc nebo psaní volačky zastaví, Ctrl+R změní)", .string(repeatLabel(repeatSeconds)))
            : .tr("Opakování CQ vypnuto")
    }

    public static func postContest(_ on: Bool) -> EntryStatus {
        on
            ? .tr("Dodatečné zadání: čas QSO zadávej do pole Čas (HHmm, přes půlnoc se datum posune samo), nic se nevysílá")
            : .tr("Dodatečné zadání ukončeno — QSO zase dostávají aktuální čas")
    }

    /// `updateWorkDupes` — the "off" text is not translated in Kotlin.
    public static func workDupes(_ on: Bool) -> EntryStatus {
        on ? .tr("Dupe v Run se dělá jako nové QSO (WORKDUPE)") : .verbatim("Dupe v Run: QSO B4 (NOWORKDUPE)")
    }

    public static func autoReload(_ on: Bool) -> EntryStatus {
        on
            ? .tr("Při startu se otevře poslední závod (AUTORELOAD)")
            : .tr("Při startu úvodní dialog (NOAUTORELOAD)")
    }

    /// `updateCutNumbers` — `CutStyle.label` is passed as an argument (not translated on its own in Kotlin).
    public static func cutNumbers(_ style: CutStyle?) -> EntryStatus {
        guard let style else { return .tr("Cut čísla vypnuta") }
        return .tr("Cut čísla: %s", .string(style.label))
    }

    /// `setOperator(call, persist)`.
    public static func operatorSet(_ op: String, persisted: Bool) -> EntryStatus {
        let base: EntryStatus = .tr("Operátor: %s", .string(op))
        return persisted ? base.appending(.tr(" (uloženo do nastavení stanice)")) : base
    }

    /// `showVersion()` (`AS:1140-1142`). Kotlin: `"MacContestLogger ${appVersion()} · Java ${Runtime.version()}"`
    /// with `appVersion()` = the jpackage version or `tr("vývojová verze")`. Swift names its own runtime instead of
    /// Java (`MacContestLogger <version> · Swift <version> · macOS <version>`).
    public static func version(appVersion: String?, runtime: String) -> EntryStatus {
        let version: EntryStatus = appVersion.map { .verbatim($0) } ?? .tr("vývojová verze")
        return EntryStatus.verbatim("MacContestLogger ").appending(version).appending(.verbatim(" · " + runtime))
    }

    /// `Swift <compiler version> · macOS <version>` for `version`.
    public static func runtimeDescription() -> String {
        let os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        let macOS: String = "\(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : "")
        return "Swift " + swiftVersion + " · macOS " + macOS
    }

    private static var swiftVersion: String {
        #if compiler(>=6.4)
        return "6.4"
        #elseif compiler(>=6.3)
        return "6.3"
        #elseif compiler(>=6.2)
        return "6.2"
        #elseif compiler(>=6.1)
        return "6.1"
        #else
        return "6.0"
        #endif
    }

    /// `wipeLog()` (`AS:1148-1152`).
    public static func wipedLog(_ count: Int) -> EntryStatus {
        .tr("Deník vymazán (%s QSO)", .int(count))
    }

    /// `requestRescore(manual = true)` without an active contest.
    public static let rescoreNoContest = "Přepočet skóre: není aktivní závod"

    // MARK: - COPYLOG, RELOAD (`AS:2080-2099`)

    public static let copyLogNoDatabase = "COPYLOG: není otevřená databáze"

    /// `COPYLOG: záloha <file name>`.
    public static func copyLogDone(_ fileName: String) -> EntryStatus {
        .tr("COPYLOG: záloha %s", .string(fileName))
    }

    /// The failure text is not translated in Kotlin (`"COPYLOG: ${it.message}"`).
    public static func copyLogFailed(_ message: String) -> EntryStatus {
        .verbatim("COPYLOG: " + message)
    }

    /// `yyyyMMdd-HHmmss` (UTC) of the COPYLOG backup name.
    public static func copyLogStamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let c: DateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return day + "-" + String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// The backup file name: `<name without .sqlite>-<stamp>.sqlite` (Kotlin `removeSuffix(".sqlite")`).
    public static func copyLogFileName(_ databaseFileName: String, at date: Date) -> String {
        let suffix: [UInt16] = Array(".sqlite".utf16)
        let units: [UInt16] = Array(databaseFileName.utf16)
        let base: String = units.count >= suffix.count && Array(units.suffix(suffix.count)) == suffix
            ? JavaChar.string(Array(units.dropLast(suffix.count)))
            : databaseFileName
        return base + "-" + copyLogStamp(date) + ".sqlite"
    }

    /// `reloadAll()`: the second half is not translated in Kotlin.
    public static func reloaded(contestOpen: Bool) -> EntryStatus {
        let base: EntryStatus = .tr("Definice závodů znovu načteny")
        return contestOpen ? base.appending(.verbatim(" a závod otevřen")) : base
    }
}
