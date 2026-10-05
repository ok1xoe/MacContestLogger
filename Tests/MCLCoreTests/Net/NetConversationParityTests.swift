import Foundation
import Testing
@testable import MCLCore

/// Java parity: conversation arm against Java v1.1.1 (5.3): the same scripts
/// (`Fixtures/net-gate/conversation.txt`) as a maintainer-only probe against the Swift
/// clients (`DxClusterClient`, `WsjtxListener`, `AdifUdpListener`, `N1mmListener` + `N1mmContactParser`,
/// `UdpBroadcaster`, `HamQthClient`/`QrzClient` nad `URLSessionHttpGetter`, `ClubLogClient`, `ScorePoster`,
/// `MqttSyncTransport`) and the Swift stand-ins (POSIX sockets, `FakeHttpServer`, a hand-driven MQTT broker).
/// Reference `Fixtures/net-conversation-java.json.gz`.
///
/// Exact match: the bytes the client sends (telnet lines, datagrams, the normalised HTTP request, every
/// MQTT packet whole — CONNECT, SUBSCRIBE, PUBLISH incl. DUP, PUBACK, DISCONNECT), the result of each call or
/// `EXC Class: message`, listener events in order, log texts (`UdpBroadcaster`, `HamQthLog` without time).
/// A change of script = "REGENERATE REFERENCE", a different result = "MISMATCH". The gate prints nothing. Only 127.0.0.1/::1
/// with OS-assigned ports (never 4532/4533), no real service; blocking I/O only on dedicated threads.
@Suite(.ioSafetyNet) struct NetConversationParityTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Rows per item in the Java reference and scenarios per section — against a broken generator, where
    /// scripts taken from the file would still match (empty section, lost outputs).
    static let pinnedLines: [String: Int] = [
        "telnet": 52, "udp-rx": 37, "udp-mcast": 5, "udp-tx": 12, "http": 92, "mqtt": 137,
    ]
    static let pinnedScenarios: [String: Int] = [
        "telnet": 8, "udp-rx": 6, "udp-mcast": 1, "udp-tx": 2, "http": 8, "mqtt": 8,
    ]

    /// An item with multicast on `lo0` — separate, so the runner without multicast on loopback skips it.
    static let multicast = "udp-mcast"

    @Test func conversationArmMatchesJava() async throws {
        try await JavaV111Gate.run {
            try await compare { $0 != Self.multicast }
        }
    }

    /// Two multicast listeners on one port (`SO_REUSEPORT`) and a unicast bind to the same port; the group only on `lo0`.
    @Test(.enabled(if: UdpIoMeasuredTests.loopbackMulticastAvailable, "the runner cannot do multicast on the lo0 loopback"))
    func multicastBindsMatchJava() async throws {
        try await compare { $0 == Self.multicast }
    }

    func compare(_ include: (String) -> Bool) async throws {
        let all = try JavaIoParityFixture.reference("net-conversation-java")
        #expect(all.map(\.relative) == ["telnet", "udp-rx", "udp-mcast", "udp-tx", "http", "mqtt"], "set of reference items")
        let reference = all.filter { include($0.relative) }
        let sections = try NetConversationScripts.parse(try NetConversationScripts.scriptLines()).filter { include($0.name) }
        for entry in reference {
            #expect(entry.lines.count == Self.pinnedLines[entry.relative], "\(entry.relative): number of reference rows (pinned)")
            let scenarios: Int = entry.lines.filter { JavaEngineParityTests.isInput($0) }.count
            #expect(scenarios == Self.pinnedScenarios[entry.relative], "\(entry.relative): number of scenarios (pinned)")
        }
        var mine: [NetConversationScripts.Entry] = []
        for section in sections {
            mine.append(try await NetConversationScripts.run(section))
        }
        let report = JavaIoParityFixture.differences(reference: reference, mine: mine, arm: "network conversation",
                                                     regenerate: Self.regenerate)
        #expect(report == nil, Comment(rawValue: JavaRadioParityFixture.capped(report ?? "")))
    }
}
