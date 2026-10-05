import Foundation
import Testing
@testable import MCLCore

/// `digital/FldigiClientTest` (2, same names; `clientTalksToFldigi` over `FakeHttpServer` on 127.0.0.1).
/// The conversation against the Java probe is `FldigiClientMeasuredTests`.
@Suite(.ioSafetyNet) struct FldigiClientTests {

    static func response(_ value: String) -> String {
        "<?xml version=\"1.0\"?><methodResponse><params><param><value>" + value
            + "</value></param></params></methodResponse>"
    }

    @Test func xmlRpcEncodingAndParsing() throws {
        let req = XmlRpc.call("text.add_tx", .string("CQ <TEST> & 5NN"), .int(5), .bool(true))
        #expect(req.contains("<methodName>text.add_tx</methodName>"))
        #expect(req.contains("<string>CQ &lt;TEST&gt; &amp; 5NN</string>"))
        #expect(req.contains("<int>5</int>") && req.contains("<boolean>1</boolean>"))

        #expect(try XmlRpc.parseResponse(Self.response("<string>RX</string>")) == .string("RX"))
        #expect(try XmlRpc.parseResponse(Self.response("RTTY")) == .string("RTTY"))
        #expect(try XmlRpc.parseResponse(Self.response("<i4>42</i4>")) == .int(42))
        let base64 = Data("OK1XOE".utf8).base64EncodedString()
        #expect(try XmlRpc.parseResponse(Self.response("<base64>" + base64 + "</base64>")) == .bytes(Array("OK1XOE".utf8)))
        #expect(throws: XmlRpc.Failure.self) {
            try XmlRpc.parseResponse(
                "<methodResponse><fault><value><struct><member><name>faultString</name><value><string>bad</string>"
                    + "</value></member></struct></value></fault></methodResponse>")
        }
    }

    /// A Java `HttpServer` answers by the request body; the client is called from its own thread (blocking HTTP).
    @Test func clientTalksToFldigi() async throws {
        let server = try FakeHttpServer()
        defer { server.stop() }
        server.respond { bytes in
            let body = String(decoding: bytes, as: UTF8.self)
            let out: String
            if body.contains("main.get_trx_state") {
                out = Self.response("<string>TX</string>")
            } else if body.contains("text.get_rx_length") {
                out = Self.response("<int>12</int>")
            } else if body.contains("text.get_rx") {
                out = Self.response("<base64>" + Data("CQ DL1ABC".utf8).base64EncodedString() + "</base64>")
            } else if body.contains("modem.get_name") {
                out = Self.response("<string>RTTY</string>")
            } else {
                out = Self.response("<string></string>")
            }
            return FakeHttpServer.Response(body: out)
        }
        let port = server.port
        // A generous timeout: success must not depend on wall-clock time (the Java 2 s / 3 s are verified by the timeout tests).
        let c = try FldigiClient(host: "127.0.0.1", port: port, connectTimeoutMs: 30_000, requestTimeoutMs: 30_000)
        let answers: [String] = try await onOwnThread {
            [try c.modemName(), try c.trxState(), String(try c.rxLength()), try c.rxText(start: 0, length: 12)]
        }
        #expect(answers == ["RTTY", "TX", "12", "CQ DL1ABC"])
        let before = server.requests.count
        try await onOwnThread { try c.transmit("CQ TEST OK1XOE") }
        let calls: [String] = (before..<server.requests.count).map { String(decoding: server.body($0), as: UTF8.self) }
        #expect(calls.count == 3)
        #expect(calls.count == 3 && calls[0].contains("text.clear_tx"))
        #expect(calls.count == 3 && calls[1].contains("CQ TEST OK1XOE^r"))
        #expect(calls.count == 3 && calls[2].contains("main.tx"))
    }
}
