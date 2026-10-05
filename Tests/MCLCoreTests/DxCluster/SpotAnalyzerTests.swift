import Foundation
import Testing
@testable import MCLCore

/// `SpotAnalyzer` status, mode, prediction and grid lookup, read from `ui/contest/ContestController.kt` (v1.1.1);
/// the values are the JVM's (`SpotAnalysisJava`, maintainer-only probe).
@Suite struct SpotAnalyzerTests {

    typealias F = SpotAnalysisFixture

    /// CQ WW CW with DL1ABC (20 m), JA1XYZ (15 m) and W1AW (40 m) logged.
    static func cqww() throws -> SpotAnalyzer {
        let env = try F.environment()
        try env.activate("cq-ww-cw")
        try env.log("DL1ABC", "20m", "CW", ("rst", "599"), ("zone", "14"))
        try env.log("JA1XYZ", "15m", "CW", ("rst", "599"), ("zone", "25"))
        try env.log("W1AW", "40m", "CW", ("rst", "599"), ("zone", "5"))
        return env.analyzer()
    }

    // MARK: - spotStatus (`:487-504`)

    @Test func outsideAContestEverythingIsNeutral() throws {
        let a = try F.environment().analyzer()
        let spot = F.spot("OK1RR", 14_025_000, "DL1ABC", "")
        #expect(a.spotStatus(spot) == .neutral)
        #expect(a.spotRows([spot]).isEmpty)
        #expect(a.predictExchange(spot).isEmpty)
        #expect(a.multiplierGrid(kind: "dxcc", spots: [spot]) == .unavailable)
        #expect(!a.needsHamQthLookup && !a.needsGridLookup)
        // `:566` the mode still resolves: band plan, else the primary mode (CW outside a contest).
        #expect(a.resolveSpotMode(call: "OK1ABC", freqHz: 3_000_000, comment: "") == "CW")
    }

    @Test func dupeNewAndDoubleMultipliers() throws {
        let a = try Self.cqww()
        #expect(a.spotStatus(F.spot("OK1RR", 14_025_000, "DL1ABC", "")) == SpotStatus(dupe: true, newMultCount: 0))
        #expect(a.spotStatus(F.spot("OK1RR", 14_030_000, "DL2XYZ", "")) == .neutral)
        let double = a.spotStatus(F.spot("OK1RR", 14_010_000, "W1AW", ""))
        #expect(double == SpotStatus(dupe: false, newMultCount: 2) && double.newMult)
        // Dupe on 40 m, yet the callbook zone 4 (not the logged 5) is a new zone there — Kotlin counts both.
        #expect(a.spotStatus(F.spot("OK1RR", 7_010_000, "W1AW", "")) == SpotStatus(dupe: true, newMultCount: 1))
    }

    @Test func blankCallNoBandAndOffContestModeAreNeutral() throws {
        let a = try Self.cqww()
        #expect(a.spotStatus(F.spot("OK1RR", 14_015_000, "   ", "")) == .neutral)       // `:490` isBlank
        #expect(a.spotStatus(F.spot("OK1RR", 3_000_000, "OK1ABC", "")) == .neutral)    // `:491` no band
        #expect(a.spotStatus(F.spot("OK1RR", 14_250_000, "LU1ABC", "SSB")) == .neutral) // `:494` PHONE in CW
        #expect(a.spotStatus(F.spot("OK1RR", 14_074_000, "VE3ABC", "")) == .neutral)   // `:522` FT8 frequency
        #expect(a.spotStatus(F.spot("OK1RR", 14_040_000, "K1ABC", "RTTY")) == .neutral)
    }

    @Test func skimmerAndUnknownCommentModeAreEvaluated() throws {
        let a = try Self.cqww()
        // Skimmer comment: mode CW from the comment → relevant.
        #expect(a.spotStatus(F.spot("DK0SK-#", 14_005_000, "W2XX", "CW 99999999999 dB")).newMultCount == 2)
        // An unknown comment mode falls back to the band plan (CW segment) → relevant.
        #expect(a.spotStatus(F.spot("OK1RR", 14_045_000, "K2ZZ", "XYZ")).newMultCount == 2)
        #expect(a.resolveSpotMode(call: "K2ZZ", freqHz: 14_045_000, comment: "XYZ") == "CW")
    }

    @Test func undeterminableModeIsColorRelevant() throws {
        let a = try Self.cqww()
        // `:511` no comment mode, not a digi frequency, outside the band plan (60 m) → evaluated.
        let spot = F.spot("OK1RR", 5_354_000, "DL1ABC", "")
        #expect(a.spotModeCategory(spot) == nil)
        #expect(a.isColorRelevant(spot))
    }

    // MARK: - mode (`:518-574`)

    @Test func categoryToModeAndSpotModes() throws {
        #expect(SpotAnalyzer.categoryToMode(.cw) == "CW")
        #expect(SpotAnalyzer.categoryToMode(.phone) == "SSB")
        #expect(SpotAnalyzer.categoryToMode(.digi) == "RTTY")
        let a = try Self.cqww()
        #expect(a.resolveSpotMode(call: "VE3ABC", freqHz: 14_074_000, comment: "") == "FT8")
        #expect(a.spotCategory(F.spot("OK1RR", 14_074_000, "VE3ABC", "")) == "DIGI")
        #expect(a.resolveSpotMode(call: "LU1ABC", freqHz: 14_250_000, comment: "SSB") == "SSB")
        #expect(a.spotCategory(F.spot("OK1RR", 14_250_000, "LU1ABC", "SSB")) == "PHONE")
    }

    // MARK: - prediction (`:151-198`)

    @Test func predictionUsesEstimateCallbookZoneAndHqCalls() throws {
        let a = try Self.cqww()
        #expect(F.mapText(a.predictExchange(F.spot("OK1RR", 14_025_000, "DL1ABC", ""))) == "{zone=14}")
        // The callbook CQ zone 4 overrides the DXCC estimate 5 of the CQ_ZONE field.
        #expect(F.mapText(a.predictExchange(F.spot("OK1RR", 14_010_000, "W1AW", ""))) == "{zone=4}")
        #expect(a.needsHamQthLookup && !a.needsGridLookup)

        let env = try F.environment()
        try env.activate("iaru-hf")
        let iaru = env.analyzer()
        #expect(F.mapText(iaru.predictExchange(F.spot("OK1RR", 14_030_000, "DA0HQ", ""))) == "{exch=DARC}")
        #expect(F.mapText(iaru.predictExchange(F.spot("OK1RR", 14_036_000, "w1aw/4 ", ""))) == "{exch=ARRL}")
        #expect(F.mapText(iaru.predictExchange(F.spot("OK1RR", 21_030_000, "8N1HQ", ""))) == "{exch=JARL}")
        #expect(F.mapText(iaru.predictExchange(F.spot("OK1RR", 14_040_000, "DL5AA", ""))) == "{exch=28}")
        #expect(!iaru.needsHamQthLookup)
    }

    @Test func hqCallsSplitOnCommaAndSemicolon() throws {
        let env = try F.environment()
        try env.activate("iaru-hf")
        let map = SpotAnalyzer.buildHqCalls(definition: env.runtime.definition, registry: env.runtime.multiplierRegistry)
        #expect(map["8N1HQ"] == "JARL" && map["8N6HQ"] == "JARL")   // `JARL,,8N1HQ;8N6HQ`
        #expect(map["W1AW/4"] == "ARRL")
        #expect(SpotAnalyzer.buildHqCalls(definition: nil, registry: env.runtime.multiplierRegistry).isEmpty)
    }

    // MARK: - grid of a spot (`:114-142`)

    @Test func gridFromCommentCsvAndCallbookWithOneLogPerCall() throws {
        let env = try F.environment()
        try env.activate("ww-digi")
        let a = env.analyzer()
        #expect(a.needsGridLookup && a.needsHamQthLookup)
        #expect(a.gridForSpot(F.spot("OK1RR", 14_074_000, "DL1AAH", "FT8 -12 dB JO52")) == "JO52")
        #expect(a.gridForSpot(F.spot("OK1RR", 14_080_000, "DL1AE", "FT8")) == "JO31")        // CSV
        #expect(a.gridForSpot(F.spot("OK1RR", 28_074_000, "JA1ABC", "")) == "PM95")          // callbook
        #expect(a.gridForSpot(F.spot("OK1RR", 21_075_000, "JA1XXX", "FT8 jo52 pm96")) == "PM96")
        #expect(a.gridForSpot(F.spot("OK1RR", 14_077_000, "K9ZZZ", "FT8")) == nil)
        let first = env.lines.take()
        #expect(first.first == "DL1AAH (DL): „FT8 -12 dB JO52“")
        #expect(first.contains("  → JO31 (z CSV)") && first.contains("  → PM95 (z callbooku)"))
        #expect(first.last == "  → grid nezjištěn")
        // Once per callsign until reset (Kotlin `gridLogged`).
        _ = a.gridForSpot(F.spot("OK1RR", 7_074_000, "dl1aah", ""))
        #expect(env.lines.take().isEmpty)
        env.gridLog.reset()
        _ = a.gridForSpot(F.spot("OK1RR", 7_074_000, "DL1AAH", ""))
        #expect(!env.lines.take().isEmpty)
    }

    @Test func gridLogTranslatesOnlyTheKotlinTrTexts() throws {
        let env = try F.environment()
        let messages = MessageBox()
        let log = SpotGridLog { messages.add($0) }
        try env.activate("ww-digi")
        let a = SpotAnalyzer(runtime: env.runtime, gridDatabase: env.gridDb, gridFieldMap: env.fieldMap,
                             gridLog: log)
        _ = a.gridForSpot(F.spot("OK1RR", 14_074_000, "DL1AAH", "FT8 JO52"))
        _ = a.gridForSpot(F.spot("OK1RR", 14_080_000, "DL1AE", ""))
        _ = a.gridForSpot(F.spot("OK1RR", 14_077_000, "K9ZZZ", ""))
        let all = messages.all()
        #expect(all.contains(ContestMessage("  → %s (z těla zprávy)", .string("JO52"))))
        #expect(all.contains(.verbatim("  → JO31 (z CSV)")))
        #expect(all.contains(ContestMessage("  → grid nezjištěn")))
    }

    final class MessageBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ContestMessage] = []

        func add(_ message: ContestMessage) {
            lock.lock()
            items.append(message)
            lock.unlock()
        }

        func all() -> [ContestMessage] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }

    @Test func gridOutsideAGridContestIsNotLogged() throws {
        let env = try F.environment()
        try env.activate("cq-ww-cw")
        #expect(env.analyzer().gridForSpot(F.spot("OK1RR", 14_010_000, "W1AW", "")) == "FN31")
        #expect(env.lines.take().isEmpty)   // `:118` needsGridLookup() && …
    }

    // MARK: - staleness (Kotlin reads the session and my station live)

    @Test func adoptAndDeactivateMakeAnAnalyzerStale() throws {
        let env = try F.environment()
        try env.activate("cq-ww-cw")
        let before = env.analyzer()
        #expect(before.isCurrent(for: env.runtime))
        try env.log("DL1ABC", "20m", "CW", ("rst", "599"), ("zone", "14"))
        #expect(before.isCurrent(for: env.runtime))   // logging into the same live session
        let outcome = try #require(env.runtime.replayed([]))
        #expect(env.runtime.adopt(outcome, forContestId: "cq-ww-cw"))
        #expect(!before.isCurrent(for: env.runtime))
        // The stale snapshot still sees the orphaned session's dupe; a rebuilt one sees the adopted (empty) session.
        let spot = F.spot("OK1RR", 14_025_000, "DL1ABC", "")
        #expect(before.spotStatus(spot).dupe)
        let after = env.analyzer()
        #expect(after.isCurrent(for: env.runtime) && !after.spotStatus(spot).dupe)
        env.runtime.deactivate()
        #expect(!after.isCurrent(for: env.runtime))
        #expect(env.analyzer().spotStatus(spot) == .neutral)
    }

    @Test func stationChangeMakesAnAnalyzerStale() throws {
        final class Station: @unchecked Sendable {
            var call = "OK1XOE"
            var grid = "JN79"
        }
        let station = Station()
        let dxcc = F.dxcc()
        let runtime = ContestRuntime(dxcc: dxcc, registry: nil, available: [], contestsDir: nil,
                                     myCall: { station.call }, myGrid: { station.grid })
        let analyzer = SpotAnalyzer(runtime: runtime)
        #expect(analyzer.isCurrent(for: runtime))
        station.grid = "FN31"
        #expect(!analyzer.isCurrent(for: runtime))
        station.grid = "JN79"
        station.call = "W1AW"
        #expect(!analyzer.isCurrent(for: runtime))
    }

    // MARK: - band plan (`:535-553`)

    @Test func bandPlanUsesMyRegion() throws {
        let a = try F.environment().analyzer()
        #expect(a.bandPlanCategory(14_000_000) == .cw)
        #expect(a.bandPlanCategory(14_200_000) == .phone)
        #expect(a.bandPlanCategory(5_000_000) == nil)
        #expect(a.bandPlanSegments(lo: 14_350_000, hi: 14_000_000).isEmpty)
    }

    @Test func javaRoundAndCallbookKey() {
        #expect(SpotAnalyzer.javaRound(2.5) == 3)
        #expect(SpotAnalyzer.javaRound(-2.5) == -2)
        #expect(SpotAnalyzer.javaRound(.nan) == 0)
        #expect(SpotAnalyzer.javaRound(359.49) == 359)
        #expect(SpotAnalyzer.callbookKey("\u{00A0}w1aw ") == "W1AW")   // Kotlin trim drops NBSP
    }
}
