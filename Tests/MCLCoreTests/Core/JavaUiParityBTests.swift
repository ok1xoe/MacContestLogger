import Foundation
import Testing
@testable import MCLCore

/// Java parity: the logbook logic the entry window and the log table moved into the core, against the real Kotlin code
/// of v1.1.1: the dupe index over insert/update/bulk/delete/delete-last/tombstone/wipe sequences (`dupe.IDX`, Kotlin
/// rebuilds `DupeChecker(logbook.findAll())`), `ContestStats` and `OperatingGuard.check` (`stats.RULES`, Kotlin
/// `ContestStats.of` over the whole log), the QSO marks of all 22 `contest-data` definitions (`marks.LOG`, Kotlin
/// `ContestController.qsoMarks`, a full replay) and the in-cell edit of the log table (`edit.CELL`, the private
/// `applyEdit` of `LogTable.kt`). The reference `Fixtures/ui-b-java.json.gz` comes from a maintainer-only probe (fixture
/// `b`, instructions kept with the probe).
///
/// Input rows are taken from the reference (except `defs`, which Swift computes from its own definition files), outputs
/// are computed by Swift (`UiParityBSections`) with the incremental technique the app uses. A change of inputs =
/// "REGENERATE REFERENCE", a different output = "MISMATCH". The match is exact (texts by UTF-16 units). The gate
/// prints nothing; each item runs on its own thread, not in the shared pool.
@Suite struct JavaUiParityBTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Rows per item in the Java reference — against a broken generator (an empty fuzzer, a missing definition),
    /// where inputs taken from the reference would still match.
    static let pinned: [String: Int] = [
        "dupe.IDX": 2_524, "stats.RULES": 1_324, "marks.LOG": 2_663, "edit.CELL": 4_800,
    ]

    @Test func movedLogbookLogicMatchesKotlin() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("ui-b-java")
            #expect(reference.map(\.relative) == UiParityBSections.names, "set of reference items")
            for entry in reference {
                #expect(entry.lines.count == Self.pinned[entry.relative],
                        "\(entry.relative): number of reference rows (pinned)")
            }
            let mine: [UiParityBSections.Entry] = try await UiParityBSections.replayAll(reference)
            let report = JavaNetParityFixture.differences(reference: reference, mine: mine, regenerate: Self.regenerate,
                                                          label: "logbook logic")
            #expect(report == nil, Comment(rawValue: report ?? ""))
        }
    }

    /// The reference covers every `contest-data` definition in `marks.LOG` and every step kind of `dupe.IDX`.
    @Test func referenceCoversDefinitionsAndSteps() throws {
        let reference = try JavaIoParityFixture.reference("ui-b-java")
        let marks = try #require(reference.first { $0.relative == "marks.LOG" })
        let headers: [String] = marks.lines.compactMap { line in
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count == 3, fields[1] == "in", fields[0].hasPrefix("d/") else { return nil }
            return fields[2]
        }
        #expect(headers.count == 22)
        let dupe = try #require(reference.first { $0.relative == "dupe.IDX" })
        var kinds: Set<String> = []
        for line in dupe.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            if fields.count > 2, fields[1] == "in", fields[0].contains("/") {
                kinds.insert(fields[2])
            }
        }
        #expect(kinds == ["I", "U", "B", "D", "L", "T", "W"])
    }
}
