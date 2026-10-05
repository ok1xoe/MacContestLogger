import Foundation
import Testing
@testable import MCLCore

/// Java parity: logic arm against Java v1.1.1: the pure logic
/// of `cat/ radio/ keyer/ voice/ audio/ footswitch/ so2r/ digital/ rotator/` over a hand-made corpus,
/// seeded fuzzers, `rigctl -l` and PCM fixtures. The reference `Fixtures/radio-logic-java.json.gz`
/// from a maintainer-only probe (instructions in the `README.md` there).
///
/// Exact match (texts, bytes, integers, `Double.toString`), only the DSP `Fft.magnitudesDb` with a tolerance of
/// 1e-9 dB and the brightness `normalizedRows` 1e-6 (libm). A change of input in the repo (corpus,
/// `rigctl -l`, WAV) = "REGENERATE REFERENCE", different output = "MISMATCH". The gate prints nothing.
@Suite struct JavaRadioParityTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Rows per item in the Java reference — against a broken generator (empty fuzzer, missing
    /// corpus section) where inputs taken from the reference would still match.
    static let pinnedLines: [String: Int] = [
        "hamlib-modes": 707, "mode-control": 384, "cw-builder": 28622, "cut-style": 1827, "split": 10124,
        "frequency-steps": 814, "antenna": 146, "band-notes": 203, "transverter": 185, "audio-to-rf": 609,
        "voice": 641, "mac-speech": 36, "rx-text": 801, "text-tokens": 4501, "recent-calls": 601, "xmlrpc": 2369,
        "rig-list": 358, "rig-model-filter": 915, "serial-params": 2800, "normalize-device": 27, "rotator": 16067,
        "otrsp": 401, "edge-detector": 241, "contest-recorder": 439, "to-samples": 201, "dsp": 510,
    ]

    @Test func logicArmMatchesJava() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("radio-logic-java")
            #expect(reference.map(\.relative) == JavaRadioParitySections.names, "set of reference items")
            for entry in reference {
                #expect(entry.lines.count == Self.pinnedLines[entry.relative],
                        "\(entry.relative): number of reference rows (pinned)")
            }
            let fuzzTemplates: Int = reference.first { $0.relative == "cw-builder" }?.lines
                .filter { $0.contains("\",\"in\",\"f\",") }.count ?? 0
            let fuzzComments: Int = reference.first { $0.relative == "split" }?.lines
                .filter { $0.contains("\",\"in\",\"f\",") }.count ?? 0
            #expect(fuzzTemplates == 3000, "CW fuzzer templates")
            #expect(fuzzComments == 5000, "SPLIT fuzzer comments")

            var byName: [String: JavaRadioParityFixture.Entry] = [:]
            for entry in reference { byName[entry.relative] = entry }
            let context = JavaRadioParitySections.Context(corpus: try JavaRadioParityFixture.corpusLines(), reference: byName)
            let names = JavaRadioParitySections.names
            let mine: [JavaRadioParityFixture.Entry] = try await withThrowingTaskGroup(
                of: (Int, JavaRadioParityFixture.Entry).self
            ) { group in
                for (index, name) in names.enumerated() {
                    group.addTask { (index, try JavaRadioParitySections.run(name, context)) }
                }
                var results = [JavaRadioParityFixture.Entry?](repeating: nil, count: names.count)
                for try await (index, entry) in group {
                    results[index] = entry
                }
                return results.compactMap { $0 }
            }
            let report = JavaIoParityFixture.differences(reference: reference, mine: mine, arm: "radio logic",
                                                         regenerate: Self.regenerate)
            let deviation = JavaRadioParitySections.deviation
            #expect(report == nil, Comment(rawValue: JavaRadioParityFixture.capped(report ?? "")
                + "\n(DSP: largest deviation dB \(deviation.db), brightness \(deviation.norm))"))
        }
    }
}
