import Foundation
import Testing
@testable import MCLCore

/// The helpers of the Settings tab tools. Values marked "probe" are measured on the JVM by
/// a maintainer-only probe (`settings-tools-probe.tsv`); the rest is read from
/// `ui/configurer/{HardwareTab,ModeTabs,ContestTab,VoiceKeyerTabs}.kt`.
@Suite struct SettingsToolTextsTests {

    /// Probe `found`: the frequency as a Kotlin `Double` template.
    @Test func foundTextMatchesKotlin() {
        let cases: [(Int64, String)] = [
            (14_025_000, "14025.0"), (7_000_000, "7000.0"), (1_700_000, "1700.0"), (470_000_000, "470000.0"),
            (7_074_123, "7074.123"), (3_573_001, "3573.001"), (144_300_000, "144300.0"), (50_313_500, "50313.5"),
            (1_800_010, "1800.01"),
        ]
        for (freq, khz) in cases {
            let outcome = RigScanner.Outcome(candidate: RigScanner.Candidate(model: 2014, label: "Kenwood TS-590S",
                                                                             baud: 9600), freqHz: freq)
            #expect(SettingsTools.found(outcome) == "Nalezeno: Kenwood TS-590S @ 9600 baud (" + khz + " kHz)")
        }
    }

    /// Probe `probe`: the baud goes into `%s` as a plain number.
    @Test func probingTextFormatsTheBaudPlainly() {
        let text: String = Translator.source.translate(SettingsTools.probing, [.string("Icom IC-7300"),
                                                                                .string(String(115_200))],
                                                         decimalSeparator: ".")
        #expect(text == "Zkouším Icom IC-7300 @ 115200…")
        #expect(SettingsTools.scanBauds == [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200])
    }

    /// `MT:89, 92`: the port falls back to 7362 when Kotlin's `toIntOrNull` fails; the answer is a literal.
    @Test func fldigiPortAndAnswer() {
        #expect(SettingsTools.fldigiPort("") == 7362)
        #expect(SettingsTools.fldigiPort("7363") == 7363)
        #expect(SettingsTools.fldigiPort(" 7363") == 7362)
        #expect(SettingsTools.fldigiPort("99999") == 99999)
        #expect(SettingsTools.fldigiPort("99999999999") == 7362)
        #expect(SettingsTools.fldigiAnswer(version: "4.2.05", modem: "BPSK31") == "fldigi 4.2.05, modem BPSK31")
    }

    /// The Java message of the client's errors; a refused connection has none (`null`).
    @Test func fldigiErrorMessages() {
        #expect(SettingsTools.fldigiErrorMessage(JavaIOError(nil, javaClass: "java.net.ConnectException")) == nil)
        #expect(SettingsTools.fldigiErrorMessage(JavaIOError("fldigi: HTTP 404")) == "fldigi: HTTP 404")
        #expect(SettingsTools.fldigiErrorMessage(XmlRpc.Failure(message: "no such method")) == "no such method")
        #expect(SettingsTools.fldigiErrorMessage(JavaIllegalArgumentError(message: "unsupported URI x"))
            == "unsupported URI x")
    }

    /// Java's pseudo-mixer is not listed beside „Výchozí systémové".
    @Test func deviceChoicesDropThePseudoDefault() {
        #expect(SettingsTools.deviceChoices(["Default Audio Device", "MacBook Speakers", "USB Audio CODEC"])
            == ["MacBook Speakers", "USB Audio CODEC"])
        #expect(SettingsTools.deviceChoices(["Default Audio Device"]) == [])
    }

    /// Probe `yaml`, `sets`, `scp` over the probe's synthetic tree.
    @Test func countsMatchKotlin() throws {
        let work: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-tools-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: work) }
        let manager = FileManager.default
        let withContests: URL = work.appendingPathComponent("with-contests")
        let contests: URL = withContests.appendingPathComponent("contests")
        try manager.createDirectory(at: contests, withIntermediateDirectories: true)
        for name in ["a.yaml", "b.YAML", ".yaml", "c.yml", "d.yaml.bak", "e.yaml"] {
            try Data("x".utf8).write(to: contests.appendingPathComponent(name))
        }
        try manager.createDirectory(at: contests.appendingPathComponent("sub.yaml"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: withContests.appendingPathComponent("root.yaml"))
        let sets: URL = withContests.appendingPathComponent("multipliers")
        try manager.createDirectory(at: sets, withIntermediateDirectories: true)
        for name in ["m1.yaml", "m2.yaml", "m3.csv"] {
            try Data("x".utf8).write(to: sets.appendingPathComponent(name))
        }
        let flat: URL = work.appendingPathComponent("flat")
        try manager.createDirectory(at: flat, withIntermediateDirectories: true)
        for name in ["one.yaml", "two.yaml"] {
            try Data("x".utf8).write(to: flat.appendingPathComponent(name))
        }
        try Data("a file, not a directory".utf8).write(to: flat.appendingPathComponent("contests"))
        let fileRoot: URL = work.appendingPathComponent("file-root.yaml")
        try Data("x".utf8).write(to: fileRoot)

        let roots: [(String, Int, Int)] = [
            (withContests.path, 4, 2), (withContests.path + "/", 4, 2), (flat.path, 2, 0),
            (work.appendingPathComponent("missing").path, 0, 0), (fileRoot.path, 0, 0),
        ]
        for (root, yaml, multipliers) in roots {
            #expect(SettingsTools.contestYamlCount(contestDataDir: root) == yaml, "\(root)")
            #expect(SettingsTools.multiplierYamlCount(contestDataDir: root) == multipliers, "\(root)")
        }

        let scp: URL = work.appendingPathComponent("master.scp")
        try Data("# comment\nOK1XOE\nok2abc\n\nDL1ABC\nOK1XOE\n".utf8).write(to: scp)
        #expect(SettingsTools.scpCount("") == 0)
        #expect(SettingsTools.scpCount("   ") == 0)
        #expect(SettingsTools.scpCount(work.appendingPathComponent("none.scp").path) == 0)
        #expect(SettingsTools.scpCount(scp.path) == 3)
        #expect(SettingsTools.scpCount(work.path) == 0)

        let history: URL = work.appendingPathComponent("history.txt")
        try Data("!!Order!!,Call,Name\nOK1XOE,TOMAS\nDL1ABC,HANS\n".utf8).write(to: history)
        #expect(SettingsTools.callHistoryCount(" ") == 0)
        #expect(SettingsTools.callHistoryCount(history.path) == CallHistory.load(history.path).size)
        #expect(SettingsTools.callHistoryCount(history.path) == 2)
    }
}
