import Foundation
import Testing
@testable import MCLCore

/// Java parity: entry-window logic against Java v1.1.1 (sections `CMD`, `ESM`, `KEY`, `SCP`,
/// `CH` and `MISC` for runmode, sked, message and macro scripts): hand-made edges, the full ESM table (2⁷ states ×
/// 2² options via `State(index:)`/`Options(index:)`) and seeded fuzzers over the same inputs Java saw.
/// The reference `Fixtures/core-a-java.json.gz` from a maintainer-only probe (instructions kept with the probe).
///
/// Input rows are taken from the reference, outputs are computed by Swift (`*CoreParitySections`). A change of inputs =
/// "REGENERATE REFERENCE", a different output = "MISMATCH". The match is exact (texts by UTF-16 units). The gate
/// prints nothing; each item runs on its own thread (not in the shared pool), concurrently at most as many as there are
/// cores. The measured tables of the individual tasks (`*MeasuredTests`) stay as unit tests — the gate adds
/// the full ESM table, fuzzers and pinned `ShortcutAction` labels to them.
@Suite struct JavaCoreParityTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    static let names: [String] = {
        var all: [String] = EntryCoreParitySections.names
        all += DataCoreParitySections.names
        all += MiscCoreParitySections.names
        return all
    }()

    /// Rows per item in the Java reference — against a broken generator (empty fuzzer, missing corpus),
    /// where inputs taken from the reference would still match.
    static let pinnedEntry: [String: Int] = [
        "cmd.FUZZ": 14_410, "esm.TABLE": 1_024, "esm.PROG": 3_874, "key.PARSE": 11_306, "key.FMT": 3_238,
        "key.ACT": 560, "key.BIND": 1_002,
    ]
    static let pinnedData: [String: Int] = [
        "scp.LOAD": 1_000, "scp.FIND": 3_280, "scp.MERGE": 5_200, "scp.VAL": 328, "ch.PARSE": 1_600,
        "ch.LOAD": 800, "ch.PRE": 2_520, "ch.UPD": 600,
    ]
    static let pinnedMisc: [String: Int] = [
        "run.EVT": 4_140, "sked.PARSE": 6_000, "sked.AT": 3_000, "sked.LIST": 800, "msg.LOG": 2_598,
        "macro.LOAD": 800,
    ]

    static func pinned(_ name: String) -> Int? {
        let groups: [[String: Int]] = [pinnedEntry, pinnedData, pinnedMisc]
        return groups.lazy.compactMap { $0[name] }.first
    }

    @Test func entryWindowLogicMatchesJava() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("core-a-java")
            #expect(reference.map(\.relative) == Self.names, "set of reference items")
            for entry in reference {
                #expect(entry.lines.count == Self.pinned(entry.relative),
                        "\(entry.relative): number of reference rows (pinned)")
            }
            let mine: [JavaCoreParityFixture.Entry] = try await JavaCoreParityFixture.replayAll(reference)
            let report = JavaNetParityFixture.differences(reference: reference, mine: mine, regenerate: Self.regenerate,
                                                          label: "core, part 1")
            #expect(report == nil, Comment(rawValue: report ?? ""))
        }
    }
}
