import Foundation
import Testing
@testable import MCLCore

/// The Java `clublog/ClubLogClientTest.uploadsFormAndClassifies` (POST to a local server `127.0.0.1`) and the logic
/// of the form body and status classification; body values measured on Java (a `HttpClient` stand-in, section
/// `clublog.FORM` of the maintainer-only generator), network behaviour by the probe
/// a maintainer-only probe (rows `CL.`).
@Suite struct ClubLogClientTests {

    /// The Java test takes `HttpClient.newHttpClient()` (no connect timeout, NEVER); the request timeout here is
    /// a generous guard (the successful path without wall-clock time bounds).
    private static func client(_ url: String) -> ClubLogClient {
        ClubLogClient(http: JavaHttpClient(connectTimeout: nil, redirect: .never), url: url, requestTimeout: 120)
    }

    @Test func uploadsFormAndClassifies() async throws {
        let server = try FakeHttpServer(response: .init(status: 200))
        defer { server.stop() }
        let c = Self.client("http://127.0.0.1:\(server.port)/realtime.php")
        let ok = try await onOwnThread { try c.upload(email: "a@b.cz", password: "pw", callsign: "OK1XOE", apiKey: "KEY",
                                                      adifRecord: "<CALL:4>W1AW <EOR>") }
        #expect(ok == .OK)
        let body = FakeHttpServer.formDecoded(server.body(0))
        #expect(body.contains("callsign=OK1XOE"), "\(body)")
        #expect(body.contains("adif=<CALL:4>W1AW <EOR>"), "\(body)")
        #expect(server.head(0).hasPrefix("POST /realtime.php HTTP/1.1\r\n"))
        server.respond(.init(status: 403))
        let rejected = try await onOwnThread { try c.upload(email: "a@b.cz", password: "bad", callsign: "OK1XOE",
                                                            apiKey: "KEY", adifRecord: "x") }
        #expect(rejected == .REJECTED)
        server.respond(.init(status: 500))
        let retry = try await onOwnThread { try c.upload(email: "a@b.cz", password: "pw", callsign: "OK1XOE",
                                                         apiKey: "KEY", adifRecord: "x") }
        #expect(retry == .RETRY)
        #expect(ClubLogClient.classify(503) == .RETRY)
    }

    /// `CL.status302` (NEVER: a 3xx is not followed → `RETRY`, one request), `CL.refused` and `CL.closeNoReply`
    /// (`IOException` → `RETRY`), `CL.badUrl` (Java `IllegalArgumentException` flies out).
    @Test func uploadNetworkOutcomesMatchJava() async throws {
        let server = try FakeHttpServer(response: .init(status: 302, headers: ["Location: /x"]))
        defer { server.stop() }
        let redirected = Self.client("http://127.0.0.1:\(server.port)/realtime.php")
        #expect(try await onOwnThread { try redirected.upload(email: "a", password: "b", callsign: "c", apiKey: "d",
                                                              adifRecord: "e") } == .RETRY)
        #expect(server.requests.count == 1)
        server.respond(.init(closeWithoutReply: true))
        #expect(try await onOwnThread { try redirected.upload(email: "a", password: "b", callsign: "c", apiKey: "d",
                                                              adifRecord: "e") } == .RETRY)
        let refused = Self.client("http://127.0.0.1:\(FreeLoopbackPort.take())/realtime.php")
        #expect(try await onOwnThread { try refused.upload(email: "a", password: "b", callsign: "c", apiKey: "d",
                                                           adifRecord: "e") } == .RETRY)
        let bad = Self.client("http://a b/")
        #expect(throws: JavaIllegalArgumentError(message: "Illegal character in authority at index 8: http://a b/")) {
            try bad.upload(email: "a", password: "b", callsign: "c", apiKey: "d", adifRecord: "e")
        }
    }

    @Test func formBodyKeepsJavaOrderAndEncoding() {
        let body = ClubLogClient.formBody(email: "a@b.cz", password: "pw", callsign: "OK1XOE", apiKey: "KEY",
                                          adifRecord: "<CALL:4>W1AW <EOR>")
        #expect(body == "email=a%40b.cz&password=pw&callsign=OK1XOE&adif=%3CCALL%3A4%3EW1AW+%3CEOR%3E&api=KEY")
    }

    @Test func formBodyNullIsEmpty() {
        let body = ClubLogClient.formBody(email: nil, password: "a b&c=d", callsign: "~", apiKey: nil, adifRecord: "\u{010D}")
        #expect(body == "email=&password=a+b%26c%3Dd&callsign=%7E&adif=%C4%8D&api=")
    }

    @Test func classifiesStatus() {
        #expect(ClubLogClient.classify(200) == .OK)
        #expect(ClubLogClient.classify(403) == .REJECTED)
        #expect(ClubLogClient.classify(400) == .REJECTED)
        #expect(ClubLogClient.classify(500) == .RETRY)
        #expect(ClubLogClient.classify(503) == .RETRY)
        #expect(ClubLogClient.classify(201) == .RETRY)
        #expect(ClubLogClient.classify(-1) == .RETRY)
        #expect(ClubLogClient().url == "https://clublog.org/realtime.php")
    }
}
