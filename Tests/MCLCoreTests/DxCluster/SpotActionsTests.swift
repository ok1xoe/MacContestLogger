import Foundation
import Testing
@testable import MCLCore

/// `SpotActions` against `ui/AppState.kt` (`:385-395`, `:840-905`, `:1015-1027`, `:2117-2128`, `:3944-3976`) and
/// `ui/EntryPanel.kt` (`:770-812`) of v1.1.1; the formatting measured on the JVM (`spots-core-probe.tsv`).
@Suite struct SpotActionsTests {

    static func translator(_ map: [String: String]) -> Translator {
        var entries: [JavaStringKey: String] = [:]
        for (key, value) in map {
            entries[JavaStringKey(key)] = value
        }
        return Translator(language: "en", translations: LanguageCatalog.Translations(entries))
    }

    // MARK: - cluster command

    @Test func clusterCommandMatchesTheJvm() throws {
        let rows = SpotsCoreProbeTable.area("command")
        #expect(rows.count == 12)
        let pattern = try Regex("^\\[(.*)\\] (-?[0-9]+) \\[(.*)\\]$").dotMatchesNewlines()
        for row in rows {
            let match = try #require(row.input.wholeMatch(of: pattern))
            let call = String(try #require(match.output[1].substring))
            let freqText = String(try #require(match.output[2].substring))
            let freq = try #require(Int64(freqText))
            let comment = String(try #require(match.output[3].substring))
            let outcome = SpotActions.clusterCommand(call: call, freqHz: freq, comment: comment, connected: true)
            switch outcome {
            case .accepted(let command):
                #expect("[" + command + "]" == row.result, "\(row.input)")
            case .rejected(let status):
                #expect(row.result == "invalid", "\(row.input)")
                #expect(status == .tr(SpotActions.missingCallOrFrequency))
            }
        }
    }

    /// `AS:3955`: the connection is checked first, also for an invalid call (the **main** connection).
    @Test func clusterCommandNeedsTheConnectionFirst() {
        #expect(SpotActions.clusterCommand(call: "", freqHz: 0, comment: "", connected: false)
            == .rejected(.tr("Spot: DX cluster není připojený (okno DX Cluster)")))
        #expect(SpotActions.clusterCommand(call: " ", freqHz: 14_025_000, comment: "", connected: true)
            == .rejected(.tr("Spot: chybí volačka nebo frekvence")))
        #expect(SpotActions.clusterCommand(call: "ok1abc", freqHz: 0, comment: "", connected: true)
            == .rejected(.tr("Spot: chybí volačka nebo frekvence")))
        #expect(SpotActions.sent("DX 14025.0 OK1ABC").czech == "Spot odeslán: DX 14025.0 OK1ABC")
    }

    /// `spotMe` (`AS:3970-3975`): the own call, comment `ifBlank { "CQ" }`, the suffix only after a send.
    @Test func spotMeUsesCqAndTheSuffix() {
        #expect(SpotActions.spotMeComment("") == "CQ")
        #expect(SpotActions.spotMeComment("\u{00A0}") == "CQ")
        #expect(SpotActions.spotMeComment(" up 5 ") == " up 5 ")
        #expect(SpotActions.spotMeSent("DX 14025.0 OK1K CQ").czech
            == "Spot odeslán: DX 14025.0 OK1K CQ (self-spot — ověř, že ho propozice závodu povolují)")
        let english = Self.translator([SpotActions.spotMeSuffix: " (self-spot — check the rules)"])
        #expect(SpotActions.spotMeSent("X").text(english) == "Spot odeslán: X (self-spot — check the rules)")
    }

    /// Spot It (`EP:805-813`): the typed call (Kotlin `trim()`), a command or a blank call → the last QSO.
    @Test func spotItTakesTheFieldOrTheLastQso() {
        let field = SpotActions.spotItTarget(call: " ok1abc ", isCommand: false, fieldFreqHz: 14_025_000,
                                             lastQso: (call: "DL1X", freqHz: 7_000_000))
        #expect(field == .accepted(SpotActions.DxTarget(call: "ok1abc", freqHz: 14_025_000)))
        let command = SpotActions.spotItTarget(call: "QSY 7000", isCommand: true, fieldFreqHz: 14_025_000,
                                               lastQso: (call: "DL1X", freqHz: 7_000_000))
        #expect(command == .accepted(SpotActions.DxTarget(call: "DL1X", freqHz: 7_000_000)))
        let nilCall = SpotActions.spotItTarget(call: "", isCommand: false, fieldFreqHz: 0,
                                               lastQso: (call: nil, freqHz: 7_000_000))
        #expect(nilCall == .accepted(SpotActions.DxTarget(call: "", freqHz: 7_000_000)))
        #expect(SpotActions.spotItTarget(call: "", isCommand: false, fieldFreqHz: 0, lastQso: nil)
            == .rejected(.tr("Spot: není co spotovat")))
        // A call in the field without a frequency is not spotted at 0 Hz.
        #expect(SpotActions.spotItTarget(call: "ok1abc", isCommand: false, fieldFreqHz: 0,
                                         lastQso: (call: "DL1X", freqHz: 7_000_000))
            == .rejected(.tr(SpotActions.noFrequency)))
        #expect(SpotActions.noFrequency == "Není zadaný kmitočet — připoj rádio nebo ho zadej do pole kmitočtu")
    }

    /// Ctrl+P (`AS:894-900`): a blank call refuses, the title is `"Spot " + call` as typed.
    @Test func spotWithCommentTexts() {
        #expect(SpotActions.commentTitle(call: " ") == nil)
        #expect(SpotActions.commentTitle(call: "ok1abc ") == "Spot ok1abc ")
        #expect(SpotActions.commentNoCall == "Ctrl+P: zadej volačku ke spotu")
        #expect(SpotActions.commentHint == "Komentář ke spotu")
    }

    // MARK: - Mark

    @Test func markMatchesTheJvm() throws {
        let rows = SpotsCoreProbeTable.area("mark")
        #expect(rows.count == 8)
        for row in rows {
            let freq = try #require(Int64(row.input))
            let spot = try #require(SpotActions.markSpot(freqHz: freq))
            let status = SpotActions.markStatus(freqHz: freq, translator: .source)
            #expect("[" + spot.dxCall + "] [" + status.czech + "]" == row.result, "\(row.input)")
            #expect(spot == DxSpot(spotter: "MARK", freqHz: Int(freq), dxCall: spot.dxCall, comment: "obsazeno",
                                   selfSpotted: true))
        }
        #expect(SpotActions.markSpot(freqHz: 0) == nil)
        #expect(SpotActions.markSpot(freqHz: -1) == nil)
    }

    /// `String.format(Locale.US, tr(...))`: translated, but always with a decimal point, whatever the display locale.
    @Test func markStatusKeepsThePointInEveryLanguage() {
        let english = Self.translator([SpotActions.markStatusKey: "Frequency %.1f kHz marked in the band map"])
        let status = SpotActions.markStatus(freqHz: 14_025_050, translator: english)
        #expect(status.text(english, decimalSeparator: ",") == "Frequency 14025.1 kHz marked in the band map")
    }

    // MARK: - remove

    /// `removeSpotOf` (`AS:863-880`): the typed call uppercased, else the nearest spot within 200 Hz.
    @Test func removeTargetUsesTheCallOrTheNearestSpot() {
        var asked: [(Int, Int)] = []
        let spot = DxSpot(spotter: "S", freqHz: 14_025_100, dxCall: "dl1abc", comment: "")
        let nearest: (Int, Int) -> DxSpot? = { freq, tolerance in
            asked.append((freq, tolerance))
            return spot
        }
        #expect(SpotActions.removeTarget(call: " ok1abc ", tunedFreqHz: 14_025_000, nearest: nearest) == "OK1ABC")
        #expect(asked.isEmpty)
        #expect(SpotActions.removeTarget(call: "\u{00A0}", tunedFreqHz: 14_025_000, nearest: nearest) == "dl1abc")
        #expect(asked.count == 1 && asked[0] == (14_025_000, 200))
        #expect(SpotActions.removeTarget(call: "", tunedFreqHz: 14_025_000, nearest: { _, _ in nil }) == nil)
        #expect(SpotActions.removeNoSpot == "Alt+D: na frekvenci ani v poli volačky není spot")
        #expect(SpotActions.removed("OK1ABC", blacklist: false).czech == "Spot OK1ABC odstraněn")
        #expect(SpotActions.removed("OK1ABC", blacklist: true).czech == "Spot OK1ABC odstraněn a dán na blacklist")
    }

    // MARK: - navigation

    /// `jumpToNextSpot` (`AS:844-851`): own spots ignore dupes; multipliers need `newMult && !dupe`.
    @Test func navigationPredicate() {
        for selfSpotted in [false, true] {
            for dupe in [false, true] {
                for newMult in [false, true] {
                    let own = SpotActions.navigable(selfSpotted: selfSpotted, dupe: dupe, newMult: newMult,
                                                    onlyMult: true, onlySelf: true)
                    #expect(own == selfSpotted)
                    let mult = SpotActions.navigable(selfSpotted: selfSpotted, dupe: dupe, newMult: newMult,
                                                     onlyMult: true, onlySelf: false)
                    #expect(mult == (newMult && !dupe))
                    let any = SpotActions.navigable(selfSpotted: selfSpotted, dupe: dupe, newMult: newMult,
                                                    onlyMult: false, onlySelf: false)
                    #expect(any == !dupe)
                }
            }
        }
    }

    /// The six sentences (`AS:853-860`); `onlyMult` wins when both are set; `direction > 0` = up, `0` = down.
    @Test func noSpotTexts() {
        #expect(SpotActions.noSpotText(direction: 1, onlyMult: true, onlySelf: true) == "Žádný násobič výš na pásmu")
        #expect(SpotActions.noSpotText(direction: -1, onlyMult: true, onlySelf: false) == "Žádný násobič níž na pásmu")
        #expect(SpotActions.noSpotText(direction: 1, onlyMult: false, onlySelf: true)
            == "Žádný vlastní spot výš na pásmu")
        #expect(SpotActions.noSpotText(direction: -1, onlyMult: false, onlySelf: true)
            == "Žádný vlastní spot níž na pásmu")
        #expect(SpotActions.noSpotText(direction: 1, onlyMult: false, onlySelf: false) == "Žádný spot výš na pásmu")
        #expect(SpotActions.noSpotText(direction: 0, onlyMult: false, onlySelf: false) == "Žádný spot níž na pásmu")
    }

    // MARK: - self-spot messages

    @Test func humanSelfSpotMessageFollowsTheDefaultLocale() throws {
        let rows = SpotsCoreProbeTable.area("selfFreq")
        #expect(rows.count == 5)
        for row in rows {
            let freq = try #require(Int(row.input))
            let parts = row.result.split(separator: " ").map(String.init)
            let spot = SelfSpot(spotter: "DL1X", freqHz: freq, rbn: false, snrDb: 12, wpm: 25, at: Date())
            #expect(SpotActions.selfSpotMessage(spot, translator: .source, decimalSeparator: ".")
                == "Byl jsi spotnut: DL1X na " + parts[0] + " kHz")
            #expect(SpotActions.selfSpotMessage(spot, translator: .source, decimalSeparator: ",")
                == "Byl jsi spotnut: DL1X na " + parts[1] + " kHz")
        }
    }

    /// RBN (`AS:388-391`): translated head, then literal `", <n> dB"` and `", <n> WPM"` when present.
    @Test func rbnSelfSpotMessage() {
        let at = Date()
        let both = SelfSpot(spotter: "DK8NE-#", freqHz: 14_025_050, rbn: true, snrDb: -3, wpm: 25, at: at)
        #expect(SpotActions.selfSpotMessage(both, translator: .source, decimalSeparator: ",")
            == "RBN: DK8NE-# tě slyší na 14025,1 kHz, -3 dB, 25 WPM")
        let none = SelfSpot(spotter: "DK8NE-#", freqHz: 7_000_000, rbn: true, snrDb: nil, wpm: nil, at: at)
        let english = Self.translator([SpotActions.rbnMessageKey: "RBN: %s hears you on %s kHz"])
        #expect(SpotActions.selfSpotMessage(none, translator: english, decimalSeparator: ".")
            == "RBN: DK8NE-# hears you on 7000.0 kHz")
        let wpmOnly = SelfSpot(spotter: "X-#", freqHz: 7_000_000, rbn: true, snrDb: nil, wpm: 30, at: at)
        #expect(SpotActions.selfSpotMessage(wpmOnly, translator: .source, decimalSeparator: ".")
            == "RBN: X-# tě slyší na 7000.0 kHz, 30 WPM")
    }

    // MARK: - Store and self-spot

    /// `selfSpot` (`AS:1020-1026`): `DxSpot(myCall, f, CALL, "self", true)`; blank → nothing.
    @Test func storeSpot() {
        #expect(SpotActions.storeSpot(myCall: "OK1K", call: " straße ", freqHz: 14_025_000)
            == DxSpot(spotter: "OK1K", freqHz: 14_025_000, dxCall: "STRASSE", comment: "self", selfSpotted: true))
        #expect(SpotActions.storeSpot(myCall: "OK1K", call: "\u{2003}", freqHz: 14_025_000) == nil)
        #expect(SpotActions.storeSpot(myCall: "", call: "ok1abc", freqHz: 0)
            == DxSpot(spotter: "", freqHz: 0, dxCall: "OK1ABC", comment: "self", selfSpotted: true))
        #expect(SpotActions.storeNoCall == "Store: zadej volačku")
        #expect(SpotActions.stored(call: " ok1abc ").czech == "ok1abc uloženo do bandmapy")
    }

    // MARK: - beacons

    @Test func beaconTexts() {
        #expect(SpotActions.beaconsUnreadable(fileName: "beacons.txt").czech == "BEACONS: nelze číst beacons.txt")
        #expect(SpotActions.beaconsUnreadable(fileName: nil).czech == "BEACONS: nelze číst null")
        let spot = DxSpot(spotter: "BEACONS", freqHz: 14_100_000, dxCall: "4U1UN", comment: "")
        let clean = BeaconFile.Beacons(hours: 48, beacons: [spot, spot], skipped: [])
        #expect(SpotActions.beaconsLoaded(clean).czech == "BEACONS: 2 majáků v bandmapě na 48 h")
        let skipped = BeaconFile.Beacons(hours: 1, beacons: [], skipped: ["x", "y", "z"])
        #expect(SpotActions.beaconsLoaded(skipped).czech
            == "BEACONS: 0 majáků v bandmapě na 1 h · 3 řádků nešlo přečíst")
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(SpotActions.beaconsUntil(now: now, hours: 24) == Date(timeIntervalSince1970: 1_000 + 86_400))
    }
}
