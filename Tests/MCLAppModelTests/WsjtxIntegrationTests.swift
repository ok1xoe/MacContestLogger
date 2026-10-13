import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// WSJT-X / JTDX in the app: the DX Call mirrored into the entry window (rig 2's instance into VFO B), the decode
/// list cleared on a band change, HighlightCallsign back to the instance, JTDX's TCP logbook and the launcher (a
/// recording fake — nothing is started). Loopback sockets only.
@MainActor @Suite struct WsjtxIntegrationTests {

    static func status(id: String, dialHz: Int64, dxCall: String) -> [UInt8] {
        var out = WsjtxDataOutput()
        out.writeInt(WsjtxProtocol.magic)
        out.writeInt(WsjtxProtocol.schema)
        out.writeInt(WsjtxProtocol.status)
        WsjtxCodec.writeString(&out, id)
        out.writeLong(dialHz)
        WsjtxCodec.writeString(&out, "FT8")
        WsjtxCodec.writeString(&out, dxCall)
        WsjtxCodec.writeString(&out, "")
        WsjtxCodec.writeString(&out, "FT8")
        out.writeBoolean(false)
        out.writeBoolean(false)
        return out.bytes
    }

    final class Launches: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(String, [String])] = []
        func add(_ path: String, _ args: [String]) { lock.withLock { items.append((path, args)) } }
        var all: [(String, [String])] { lock.withLock { items } }
    }

    private static func make(launches: Launches = Launches(), tcp: Bool = false,
                             configure: @escaping (inout AppConfig) -> Void = { _ in }) async throws -> IntegrationApp {
        try await IntegrationApp.make(configure: { config, _ in
            ReceiveIntegrationTests.enableWsjtx(&config)
            configure(&config)
        }, adjust: { environment in
            environment.network.launchApp = { path, args in launches.add(path, args) }
            if tcp {
                environment.network.udp.makeAdifTcpListener = { host, _, handler in
                    checkLoopbackHost(host)
                    return try AdifTcpListener(bindHost: "127.0.0.1", bindPort: 0, handler: handler)
                }
            }
        })
    }

    @Test func dxCallGoesToTheEntryWindowOfItsRig() async throws {
        let sender = UdpSink()
        defer { sender.close() }
        let app = try await Self.make { config in config.wsjtx.radio2Id = "Radio2" }
        await eventually("listening") { app.integrations.wsjtxPort != nil }
        let port: Int = try #require(app.integrations.wsjtxPort)
        sender.send(Self.status(id: "WSJT-X", dialHz: 14_074_000, dxCall: "K1ZZ"), toPort: port)
        await eventually("mirrored") { app.model.entry.form.call == "K1ZZ" }
        sender.send(Self.status(id: "WSJT-X - Radio2", dialHz: 7_074_000, dxCall: "JA1ABC"), toPort: port)
        await eventually("rig 2") { app.model.vfoB.entry.form.call == "JA1ABC" }
        #expect(app.model.entry.form.call == "K1ZZ")
        #expect(app.integrations.wsjtxStatuses.count == 2)
    }

    @Test func aBandChangeClearsTheDecodesAndHighlightGoesBack() async throws {
        let wsjtx = UdpSink()
        defer { wsjtx.close() }
        let app = try await Self.make()
        try await app.app.startCqWwCw()
        await eventually("listening") { app.integrations.wsjtxPort != nil }
        let port: Int = try #require(app.integrations.wsjtxPort)
        wsjtx.send(Self.status(id: "WSJT-X", dialHz: 14_074_000, dxCall: ""), toPort: port)
        await eventually("status") { app.integrations.wsjtxStatus != nil }
        wsjtx.send(WsjtxPackets.decode("CQ OK1ABC JO70"), toPort: port)
        await eventually("row") { app.integrations.wsjtxDecodes.rows.count == 1 }
        // HighlightCallsign (13) back to the instance.
        await eventually("highlight") {
            wsjtx.bytes.contains { packet in
                var input = WsjtxDataInput(packet)
                _ = try? input.readInt()
                _ = try? input.readInt()
                return (try? input.readInt()) == 13
            }
        }
        wsjtx.send(Self.status(id: "WSJT-X", dialHz: 7_074_000, dxCall: ""), toPort: port)
        await eventually("cleared") { app.integrations.wsjtxDecodes.rows.isEmpty }
    }

    @Test func jtdxTcpLogsAQso() async throws {
        let app = try await Self.make(tcp: true) { config in
            config.wsjtx.jtdxTcpEnabled = true
            config.wsjtx.jtdxTcpBind = "127.0.0.1:52001"
        }
        try await app.app.startCqWwCw()
        await eventually("tcp listening") { app.integrations.jtdxTcpPort != nil }
        let port: Int = try #require(app.integrations.jtdxTcpPort)
        try TcpClient.send(ReceiveIntegrationTests.ownAdif, toPort: port)
        await eventually("logged") { app.model.logbook.rows.count == 1 }
        #expect(app.model.logbook.rows.first?.call == "OK1ZZZ")
    }

    @Test func launchingStartsTheProgramAndOpensTheDecodeList() async throws {
        let launches = Launches()
        let app = try await Self.make(launches: launches) { config in
            config.wsjtx.programPath = "/Applications/wsjtx.app"
            config.wsjtx.programArgs = "--config-dir x"
            config.wsjtx.radio2Id = "Radio2"
        }
        app.integrations.launchWsjtx(radio2: false)
        await app.integrations.settle()
        await eventually("launched") { launches.all.count == 1 }
        #expect(launches.all.first?.0 == "/Applications/wsjtx.app")
        #expect(launches.all.first?.1 == ["--config-dir", "x"])
        await eventually("decode list") { app.model.windows.isOpen("wsjtxdecodes") }
        app.integrations.launchWsjtx(radio2: true)
        await eventually("second") { launches.all.count == 2 }
        #expect(launches.all.last?.1.last == "--rig-name=Radio2")
    }
}

/// A one-shot TCP client to loopback.
enum TcpClient {
    static func send(_ text: String, toPort port: Int) throws {
        let fd: Int32 = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected: Int32 = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }
        _ = text.withCString { write(fd, $0, strlen($0)) }
    }
}
