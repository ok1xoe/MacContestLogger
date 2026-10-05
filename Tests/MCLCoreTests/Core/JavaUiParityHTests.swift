import Foundation
import Testing
@testable import MCLCore

/// Java parity: the info, statistics and tool logic against the real Kotlin code of v1.1.1, over a synthetic corpus
/// (`Fixtures/ui-gate/tools-h.txt`): the timers of the Info window over logs with pauses and band changes
/// (`info.TIMERS`); its lines, headers, short-term rates, goal status and trend (`info.LINES`); the goal editor
/// (`goals.EDIT`); the statistics, score and dupesheet views (`stats.VIEWS`); sked and TOUR watches (`sked.WATCH`);
/// QTC series with bad lines, band notes and move multipliers (`qtc.SESSION`); the world map, propagation and the
/// multiplier grid (`map.WORLD`); the pileup simulator over a seeded random (`sim.SESSION`). The reference
/// `Fixtures/ui-h-java.json.gz` comes from a maintainer-only probe (fixture `h`, instructions kept with the probe). The
/// generator opens no audio device, keys nothing, binds no socket and opens no URL.
///
/// Input rows are taken from the reference (the `defs` and the `corpus` row are rebuilt by Swift from its own files),
/// outputs are computed by Swift (`UiParityHSections`, `UiParityHTools`). A change of inputs = "REGENERATE REFERENCE",
/// a different output = "MISMATCH". The gate prints nothing; each item runs on its own thread, not in the shared pool.
@Suite struct JavaUiParityHTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Rows per item in the Java reference — against a broken generator (an empty corpus, a missing log), where inputs
    /// taken from the reference would still match.
    static let pinned: [String: Int] = [
        "info.TIMERS": 9_660, "info.LINES": 2_676, "goals.EDIT": 254, "stats.VIEWS": 1_504, "sked.WATCH": 94,
        "qtc.SESSION": 270, "map.WORLD": 562, "sim.SESSION": 318,
    ]

    @Test func infoAndToolsMatchKotlin() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("ui-h-java")
            #expect(reference.map(\.relative) == UiParityHSections.names, "set of reference items")
            for entry in reference {
                #expect(entry.lines.count == Self.pinned[entry.relative],
                        "\(entry.relative): number of reference rows (pinned)")
            }
            let mine: [UiParityHSections.Entry] = try await UiParityHSections.replayAll(reference)
            let report = JavaNetParityFixture.differences(reference: reference, mine: mine, regenerate: Self.regenerate,
                                                          label: "info and tools")
            #expect(report == nil, Comment(rawValue: report ?? ""))
        }
    }

    /// The corpus and the scripts reach what the sections are meant to compare: pauses, band changes, a goal status of
    /// every kind, the off time modes with and without rules, a dupe in the dupesheet, a TOUR change, a sked reminder,
    /// bad QTC lines, a refused QTC (limit), a map ring of every class, a simulator mistake.
    @Test func referenceCoversTheCases() throws {
        let reference = try JavaIoParityFixture.reference("ui-h-java")
        func rows(_ name: String, _ area: String, _ kind: String = "out") throws -> [String] {
            let entry = try #require(reference.first { $0.relative == name })
            return entry.lines.map(JavaEngineParityTests.fields).filter { $0[0].hasPrefix(area + "/") && $0[1] == kind }
                .map { JavaIoParityFixture.untx($0[2]) ?? "" }
        }
        let offTimes = try rows("info.TIMERS", "offtime")
        #expect(offTimes.contains { $0.hasSuffix("ok=true") }, "an off time that reached its minimum")
        #expect(offTimes.contains { $0.contains("value=~") }, "an off time without a value")
        #expect(try rows("info.TIMERS", "bandchg").contains { $0.hasSuffix("state=over") }, "band changes over the limit")
        #expect(try rows("info.TIMERS", "onband").contains { $0.hasSuffix("ok=true") }, "a band time that reached its minimum")
        let status = Set(try rows("info.LINES", "status"))
        #expect(status == ["none", "met", "close", "missed"], "every goal status")
        #expect(try rows("info.LINES", "trend").contains { $0.contains(":missed") && $0.contains(":met") }, "a trend with goals")
        #expect(try rows("goals.EDIT", "import").contains { $0.contains("nerozpozn") }, "an import with ignored lines")
        #expect(try rows("stats.VIEWS", "dupesheet").contains { $0.contains(" *") }, "a highlighted dupesheet call")
        #expect(try rows("stats.VIEWS", "score").count == 4, "the score tables")
        let reminders = try rows("sked.WATCH", "skedWatch")
        #expect(reminders.contains { $0.hasPrefix("Sked ") || $0.contains("UTC") }, "a sked reminder")
        #expect(try rows("sked.WATCH", "tourWatch").contains { $0.hasPrefix("[") }, "the TOUR sessions")
        #expect(try rows("sked.WATCH", "tourWatch").count > 8, "TOUR messages and counters")
        let saves = try rows("qtc.SESSION", "qtcSave")
        #expect(saves.contains { $0.hasPrefix("true|") }, "a saved QTC series")
        #expect(saves.contains { $0.hasPrefix("false|") }, "a refused QTC series")
        #expect(try rows("qtc.SESSION", "qtcParse").contains { $0.contains("canSave=false") }, "bad QTC lines")
        let rings = try rows("map.WORLD", "geoRing")
        for kind in ["land:", "antarctic:", "archipelago:"] {
            #expect(rings.contains { $0.hasPrefix(kind) }, "a ring of class \(kind)")
        }
        #expect(try rows("map.WORLD", "propagation").contains { $0.hasPrefix("msg:") }, "a propagation message")
        let logged = try rows("sim.SESSION", "simLogged")
        #expect(logged.contains { $0.hasPrefix("\u{2713}") }, "a correct simulated QSO")
        #expect(logged.contains { $0.hasPrefix("\u{2717}") }, "a wrong simulated QSO")
    }
}
