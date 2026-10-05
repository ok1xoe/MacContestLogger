import Foundation
import Testing
@testable import MCLCore

/// Port of `N1mmListenerTest.java` (2 tests). Dropping is verified by order (see `WsjtxListenerTests`).
@Suite(.ioSafetyNet) struct N1mmListenerTests {

    @Test func deliversContactInfo() async throws {
        let received = Inbox<String>()
        let listener = try N1mmListener(bindHost: "127.0.0.1", bindPort: 0) { received.offer($0) }
        defer { listener.close() }
        listener.start()
        UdpTestSocket().send(Array("<contactinfo><call>AA5A</call></contactinfo>".utf8), toPort: listener.boundPort)
        #expect(await onOwnThread { received.take() } == "<contactinfo><call>AA5A</call></contactinfo>")
    }

    @Test func ignoresNonContactInfo() async throws {
        let received = Inbox<String>()
        let listener = try N1mmListener(bindHost: "127.0.0.1", bindPort: 0) { received.offer($0) }
        defer { listener.close() }
        listener.start()
        let tx = UdpTestSocket()
        tx.send(Array("<AppInfo><app>RUMlogNG</app></AppInfo>".utf8), toPort: listener.boundPort)
        tx.send(Array("<contactinfo>m</contactinfo>".utf8), toPort: listener.boundPort)
        #expect(await onOwnThread { received.take() } == "<contactinfo>m</contactinfo>")
        #expect(received.count == 0)
    }
}
