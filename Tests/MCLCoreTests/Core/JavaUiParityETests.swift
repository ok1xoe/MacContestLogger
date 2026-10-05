import Foundation
import Testing
@testable import MCLCore

/// Java parity: the rig and keying logic against the real Kotlin code of v1.1.1: the private
/// `CatConnection.format` over a fuzz of rig states (`cat.STATUS`); the tuning of a headless `AppState` — `qsy`,
/// `tuneTo`, `updateTunedFreq`, `returnToPreviousFrequency`, `jumpToCqFrequency`, `onCqSent`, `setRit`, `stepRit`
/// and the entry window's `stepBand`, `tuneStep` and wheel (`rig.TUNE`); `activateVfo`, `requestFocusVfo`,
/// `toggleSo2rStereo` and `syncRadioModeFromConfig` over SO1V/SO2V/SO2R sequences (`vfo.SWITCH`); the private
/// waterfall `heat` and the `render` loop (`wf.HEAT`); `ContestRecorder.segment` and the read of
/// `playQsoRecording` (`rec.SEG`). The reference `Fixtures/ui-e-java.json.gz` comes from a maintainer-only probe
/// (fixture `e`, instructions kept with the probe). The generator never opens a port, a sound device or a daemon.
///
/// Input rows are taken from the reference, outputs are computed by Swift (`UiParityESections`). A change of inputs =
/// "REGENERATE REFERENCE", a different output = "MISMATCH". The gate prints nothing; each item runs on its own
/// thread, not in the shared pool.
@Suite struct JavaUiParityETests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Rows per item in the Java reference — against a broken generator (an empty fuzzer, a missing case kind),
    /// where inputs taken from the reference would still match.
    static let pinned: [String: Int] = [
        "cat.STATUS": 3_064, "rig.TUNE": 4_416, "vfo.SWITCH": 2_880, "wf.HEAT": 5_406, "rec.SEG": 340,
    ]

    @Test func rigAndKeyingMatchKotlin() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("ui-e-java")
            #expect(reference.map(\.relative) == UiParityESections.names, "set of reference items")
            for entry in reference {
                #expect(entry.lines.count == Self.pinned[entry.relative],
                        "\(entry.relative): number of reference rows (pinned)")
            }
            let mine: [UiParityESections.Entry] = try await UiParityESections.replayAll(reference)
            let report = JavaNetParityFixture.differences(reference: reference, mine: mine, regenerate: Self.regenerate,
                                                          label: "rig and keying")
            #expect(report == nil, Comment(rawValue: report ?? ""))
        }
    }

    /// The fuzz reaches every operation and every outcome the sections are meant to compare: each tuning and VFO
    /// operation, a failing rig, a missing CAT, the RIT bounds, odd recording lengths, a missing recording.
    @Test func referenceCoversTheCases() throws {
        let reference = try JavaIoParityFixture.reference("ui-e-java")
        func lines(_ name: String) throws -> [[String]] {
            let entry = try #require(reference.first { $0.relative == name })
            return entry.lines.map(JavaEngineParityTests.fields)
        }
        let tune: [[String]] = try lines("rig.TUNE")
        let tuneOps = Set(tune.filter { $0[1] == "in" && $0[0].split(separator: "/").count == 3 }.map { $0[2] })
        #expect(tuneOps == ["Q", "T", "U", "P", "C", "S", "R", "r", "B", "A", "W"])
        let tuneOut: [String] = tune.filter { $0[1] == "out" && $0.count > 7 }.map { $0[7] }
        #expect(tuneOut.contains { $0.hasPrefix("RIT: p") }, "RIT without CAT")
        #expect(tuneOut.contains("RIT +9999 Hz") && tuneOut.contains("RIT -9999 Hz"), "RIT bounds")
        #expect(tuneOut.contains("Alt+F8: \\u017E\\u00E1dn\\u00E1 p\\u0159edchoz\\u00ED frekvence"), "no previous")
        let vfo: [[String]] = try lines("vfo.SWITCH")
        let vfoOps = Set(vfo.filter { $0[1] == "in" && $0[0].split(separator: "/").count == 3 }.map { $0[2] })
        #expect(vfoOps == ["M", "A", "F", "X", "Q", "U"])
        let vfoStatus: [String] = vfo.filter { $0[1] == "out" && $0.count > 8 }.map { $0[8] }
        #expect(vfoStatus.contains { $0.hasPrefix("SO2V: ") }, "a failing selectVfo")
        #expect(vfoStatus.contains { $0.hasPrefix("Aktivn\\u00ED rig 2") }, "SO2R")
        let segments: [[String]] = try lines("rec.SEG").filter { $0[1] == "out" }
        #expect(segments.contains { $0[2] == "~" }, "no recording of the hour")
        #expect(segments.contains { $0.count == 7 && $0[5] != "0" && $0[4] != $0[5] }, "a segment cut by the file")
    }
}
