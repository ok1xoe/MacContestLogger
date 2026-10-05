import Foundation
import Testing
@testable import MCLCore

/// Java parity: the logic the GUI work moved from the Kotlin UI of v1.1.1 into the core, against the real Kotlin code:
/// `ContestController` over seeded QSO scripts for all 22 `contest-data` definitions (`ctl.RUN`), `sentExchangeText`
/// and `sentExchangeFlat` (`sent.EXCH`), `parseFreqHz`, `String.format("%.2f")` and `BAND_ROWS` (`freq.PARSE`),
/// `parseEpoch` (`act.EPOCH`) and `cabrilloFileName` (`name.CAB`). The reference `Fixtures/ui-a-java.json.gz` comes
/// from a maintainer-only probe (instructions kept with the probe).
///
/// Input rows are taken from the reference (except `defs`, which Swift computes from its own definition files), outputs
/// are computed by Swift (`UiParitySections`). A change of inputs = "REGENERATE REFERENCE", a different output =
/// "MISMATCH". The match is exact (texts by UTF-16 units). The gate prints nothing; each item runs on its own thread,
/// not in the shared pool.
@Suite struct JavaUiParityTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Rows per item in the Java reference — against a broken generator (an empty fuzzer, a missing definition),
    /// where inputs taken from the reference would still match.
    static let pinned: [String: Int] = [
        "ctl.RUN": 2_680, "sent.EXCH": 3_385, "freq.PARSE": 5_004, "act.EPOCH": 5_322, "name.CAB": 8_069,
    ]

    @Test func movedUiLogicMatchesKotlin() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("ui-a-java")
            #expect(reference.map(\.relative) == UiParitySections.names, "set of reference items")
            for entry in reference {
                #expect(entry.lines.count == Self.pinned[entry.relative],
                        "\(entry.relative): number of reference rows (pinned)")
            }
            let mine: [UiParitySections.Entry] = try await UiParitySections.replayAll(reference)
            let report = JavaNetParityFixture.differences(reference: reference, mine: mine, regenerate: Self.regenerate,
                                                          label: "UI logic")
            #expect(report == nil, Comment(rawValue: report ?? ""))
        }
    }

    /// The reference covers every `contest-data` definition in `ctl.RUN` (not only CQ WW CW).
    @Test func controllerSectionCoversAllDefinitions() throws {
        let reference = try JavaIoParityFixture.reference("ui-a-java")
        let run = try #require(reference.first { $0.relative == "ctl.RUN" })
        let headers: [String] = run.lines.compactMap { line in
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count == 3, fields[1] == "in", fields[0].hasPrefix("d/") else { return nil }
            return fields[2]
        }
        #expect(headers.count == 22)
        #expect(headers.contains("cq-ww-cw") && headers.contains("wae-cw") && headers.contains("iaru-r1-vhf"))
    }
}
