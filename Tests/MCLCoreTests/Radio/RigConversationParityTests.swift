import Foundation
import Testing
@testable import MCLCore

/// Java parity: conversation arm against Java v1.1.1 (5.3): the same scripts
/// (`Fixtures/radio-gate/conversation.txt`) as a maintainer-only probe against the Swift
/// stand-ins (`ConversationServer`, `FakeHttpServer`, own UDP receiver, pseudo-terminal, byte transport)
/// and the Swift clients (`RigctldClient` ± `TransverterRig`, `CatCwKeyer`, `RigPoller`, `RotctldClient`,
/// `FldigiClient`, `N1mmRotorUdp`, `Otrsp`, `WinkeyerKeyer`). Reference `Fixtures/radio-conversation-java.json.gz`.
///
/// Exact match: request bytes per connection, the result of every call (`RigState` of all 6 fields, or
/// `EXC Class: message`, for `CatException` also the class and text of the cause), `CatTrafficLog` without times, `isConnected()`.
/// A change of script = "REGENERATE REFERENCE", a different result = "MISMATCH". The gate prints nothing. Only 127.0.0.1 with OS-assigned
/// ports (never 4532/4533), no radio, serial port or sound; blocking I/O only on dedicated threads.
@Suite(.ioSafetyNet) struct RigConversationParityTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Rows per item in the Java reference and scenarios per section — against a broken generator, where
    /// scripts taken from the file would still match (empty section, lost outputs).
    static let pinnedLines: [String: Int] = [
        "rigctld": 1084, "cat-cw": 79, "rig-poller": 53, "rotctld": 55, "fldigi": 49, "n1mm-udp": 11, "otrsp": 17,
        "winkeyer": 48,
    ]
    static let pinnedScenarios: [String: Int] = [
        "rigctld": 43, "cat-cw": 3, "rig-poller": 3, "rotctld": 9, "fldigi": 7, "n1mm-udp": 2, "otrsp": 2, "winkeyer": 5,
    ]

    @Test func conversationArmMatchesJava() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("radio-conversation-java")
            let sections = try RigConversationScripts.parse(try RigConversationScripts.scriptLines())
            for entry in reference {
                #expect(entry.lines.count == Self.pinnedLines[entry.relative], "\(entry.relative): number of reference rows (pinned)")
                let scenarios: Int = entry.lines.filter { JavaEngineParityTests.isInput($0) && !$0.hasPrefix("[\"/defaults\"") }.count
                #expect(scenarios == Self.pinnedScenarios[entry.relative], "\(entry.relative): number of scenarios (pinned)")
            }
            var mine: [RigConversationScripts.Entry] = []
            for section in sections {
                mine.append(try await RigConversationScripts.run(section))
            }
            let report = JavaIoParityFixture.differences(reference: reference, mine: mine, arm: "radio conversation",
                                                         regenerate: Self.regenerate)
            #expect(report == nil, Comment(rawValue: JavaRadioParityFixture.capped(report ?? "")))
        }
    }
}
