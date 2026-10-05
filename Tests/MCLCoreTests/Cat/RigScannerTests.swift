import Testing
@testable import MCLCore

/// Port of the Java `cat/RigScannerTest` (pure `buildCandidates`; `scan` over stand-ins in `RigScannerScanTests`)
/// + `RS.*` measurements over the real `rigctl -l` (`Fixtures/hamlib-rigctl-l-4.7.1.txt`).
@Suite struct RigScannerTests {

    private let all: [RigModel] = [
        RigModel(number: 2037, mfg: "Kenwood", model: "TS-590SG"),
        RigModel(number: 3073, mfg: "Icom", model: "IC-7300"),
        RigModel(number: 9999, mfg: "Foo", model: "Bar"),
    ]

    @Test func selectedModelTriedFirstAcrossAllBauds() {
        let c = RigScanner.buildCandidates(selectedModel: 2037, selectedLabel: "Kenwood TS-590SG", all: all,
                                           bauds: [9600, 38400])
        #expect(c[0] == RigScanner.Candidate(model: 2037, label: "Kenwood TS-590SG", baud: 9600))
        #expect(c[1] == RigScanner.Candidate(model: 2037, label: "Kenwood TS-590SG", baud: 38400))
    }

    @Test func dedupesByModelAndBaud() {
        // TS-590SG is both selected and among the common models → must not appear twice with the same baud
        let c = RigScanner.buildCandidates(selectedModel: 2037, selectedLabel: "Kenwood TS-590SG", all: all, bauds: [9600])
        #expect(c.filter { $0.model == 2037 && $0.baud == 9600 }.count == 1)
    }

    @Test func includesCommonModelsAndExcludesUnknown() {
        let c = RigScanner.buildCandidates(selectedModel: 2037, selectedLabel: "Kenwood TS-590SG", all: all, bauds: [9600])
        #expect(c.contains { $0.model == 3073 }, "IC-7300 should be among the candidates")
        #expect(!c.contains { $0.model == 9999 }, "an unknown rig should not be among the candidates")
    }

    /// `RS.candidates.count` = 108 (27 models × 4 bauds), order follows the hamlib list, `contains` after
    /// `toLowerCase` (`IC-7300` also catches `IC-7300MK2`, `FT-897` also `FT-897D`).
    @Test func measuredCandidatesOverRealRigList() throws {
        let rigs: [RigModel] = try HamlibRigListFixture.lines().compactMap { HamlibRigList.parseLine($0) }
        let bauds: [Int] = [4800, 9600, 38400, 115200]
        let c = RigScanner.buildCandidates(selectedModel: 2037, selectedLabel: "2037 \u{2014} Kenwood TS-590SG",
                                           all: rigs, bauds: bauds)
        #expect(c.count == 108)
        let models: [Int] = [
            2037, 1022, 1023, 1028, 1035, 1040, 1042, 1043, 1044, 2004, 2014, 2016, 2028, 2029,
            2031, 2039, 2041, 2043, 2047, 3023, 3046, 3070, 3073, 3078, 3081, 3085, 3094,
        ]
        var expected: [String] = []
        for model in models {
            for baud in bauds {
                expected.append("\(model)@\(baud)")
            }
        }
        #expect(c.map { "\($0.model)@\($0.baud)" } == expected)
        let labels: String = c.filter { $0.baud == 4800 }.map { "\($0.model)=\(ProbeText.esc($0.label)) | " }.joined()
        let javaLabels = "2037=2037 \\u2014 Kenwood TS-590SG | 1022=1022 \\u2014 Yaesu FT-857 | "
            + "1023=1023 \\u2014 Yaesu FT-897 | 1028=1028 \\u2014 Yaesu FT-950 | 1035=1035 \\u2014 Yaesu FT-991 | "
            + "1040=1040 \\u2014 Yaesu FTDX-101D | 1042=1042 \\u2014 Yaesu FTDX-10 | 1043=1043 \\u2014 Yaesu FT-897D | "
            + "1044=1044 \\u2014 Yaesu FTDX-101MP | 2004=2004 \\u2014 Kenwood TS-570D | "
            + "2014=2014 \\u2014 Kenwood TS-2000 | 2016=2016 \\u2014 Kenwood TS-570S | "
            + "2028=2028 \\u2014 Kenwood TS-480 | 2029=2029 \\u2014 Elecraft K3 | 2031=2031 \\u2014 Kenwood TS-590S | "
            + "2039=2039 \\u2014 Kenwood TS-990S | 2041=2041 \\u2014 Kenwood TS-890S | "
            + "2043=2043 \\u2014 Elecraft K3S | 2047=2047 \\u2014 Elecraft K4 | 3023=3023 \\u2014 Icom IC-746 | "
            + "3046=3046 \\u2014 Icom IC-746PRO | 3070=3070 \\u2014 Icom IC-7100 | 3073=3073 \\u2014 Icom IC-7300 | "
            + "3078=3078 \\u2014 Icom IC-7610 | 3081=3081 \\u2014 Icom IC-9700 | 3085=3085 \\u2014 Icom IC-705 | "
            + "3094=3094 \\u2014 Icom IC-7300MK2 | "
        #expect(labels == javaLabels)
    }
}
