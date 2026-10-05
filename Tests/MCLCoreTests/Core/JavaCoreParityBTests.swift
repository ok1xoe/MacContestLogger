import Foundation
import Testing
@testable import MCLCore

/// Java parity: statistics and tools against Java v1.1.1 (sections `STAT`, `GOAL`, `QTC`, `INFO`,
/// `SIM`, `I18N`): seeded fuzzers of logs, goal files, QTC rows, DXCC entities, the simulator operator,
/// language files and `tr(cs, args)` patterns over the same inputs Java saw. The reference
/// `Fixtures/core-b-java.json.gz` from a maintainer-only probe (`SECTIONS_B`, instructions kept with the probe);
/// the first fixture (`core-a-java.json.gz`) stays unchanged.
///
/// The infrastructure is shared with `JavaCoreParityTests` (`JavaCoreParityFixture.replayAll`): input rows from the reference,
/// outputs computed by Swift (`Stat`/`Goal`/`Tool`/`I18nCoreParitySections`). A change of inputs = "REGENERATE REFERENCE",
/// a different output = "MISMATCH". The match is exact; the suite prints nothing. The measured tables (`*MeasuredTests`)
/// stay as unit tests — the parity suite adds fuzzers to them.
@Suite struct JavaCoreParityBTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    static let names: [String] = {
        var all: [String] = StatCoreParitySections.names
        all += GoalCoreParitySections.names
        all += ToolCoreParitySections.names
        all += I18nCoreParitySections.names
        return all
    }()

    /// Rows per item in the Java reference — against a broken generator (empty fuzzer), where inputs
    /// taken from the reference would still match.
    static let pinnedStat: [String: Int] = ["stat.LOG": 8_120, "stat.GUARD": 3_512]
    static let pinnedGoal: [String: Int] = [
        "goal.PARSE": 2_800, "goal.TIME": 3_000, "goal.DERIVE": 800, "goal.FMT": 1_200, "goal.READ": 600,
    ]
    static let pinnedTool: [String: Int] = [
        "qtc.SERIAL": 4_000, "qtc.PARSE": 4_200, "qtc.CAND": 1_400, "qtc.CAB": 800, "info.FOR": 5_000,
        "sim.RUN": 12_892, "sim.SRC": 160, "sim.ED": 3_000, "sim.CW": 960,
    ]
    static let pinnedI18n: [String: Int] = ["i18n.LOAD": 1_800, "i18n.FMT": 4_000]

    static func pinned(_ name: String) -> Int? {
        let groups: [[String: Int]] = [pinnedStat, pinnedGoal, pinnedTool, pinnedI18n]
        return groups.lazy.compactMap { $0[name] }.first
    }

    @Test func statisticsAndToolsMatchJava() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("core-b-java")
            #expect(reference.map(\.relative) == Self.names, "set of reference items")
            for entry in reference {
                #expect(entry.lines.count == Self.pinned(entry.relative),
                        "\(entry.relative): number of reference rows (pinned)")
            }
            let mine: [JavaCoreParityFixture.Entry] = try await JavaCoreParityFixture.replayAll(reference)
            let report = JavaNetParityFixture.differences(reference: reference, mine: mine, regenerate: Self.regenerate,
                                                          label: "core, part 2")
            #expect(report == nil, Comment(rawValue: report ?? ""))
        }
    }
}
