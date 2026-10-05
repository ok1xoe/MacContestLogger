import Foundation
import Testing
@testable import MCLCore

/// `JavaHttpClient` / `URLSessionHttpGetter` / `ScorePoster` against a local server (`FakeHttpServer`,
/// `http://127.0.0.1`). Expected values measured by the maintainer-only probe
/// (rows `SP.`, `CB.`; JDK 21). Blocking calls only via `onOwnThread`.
@Suite struct JavaHttpClientTests {

    private static func poster() -> ScorePoster {
        ScorePoster(http: JavaHttpClient(connectTimeout: ScorePoster.connectTimeout, redirect: .normal),
                    requestTimeout: 120)
    }

    private static func describe(_ error: JavaHttpError) -> String {
        error.javaClass + "|" + (error.message ?? "null")
    }

    /// Request line (`POST /post/ HTTP/1.1`) → method and path.
    private static func requestLine(_ head: String) -> String {
        let line = head.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        return line.replacingOccurrences(of: " HTTP/1.1", with: "")
    }

    /// `SP.redirect<code>`: NORMAL follows 301/302/303 (POST → GET without a body) and 307/308 (POST with a body),
    /// returns 300 and 304. Server: `/post/` answers with the code and `Location: /target`, `/target` with status 200.
    /// Divergence (a deliberate divergence from Java v1.1.1): a redirected GET without `Content-Type` (Java keeps it, `ct=true`).
    @Test(arguments: [
        (301, "status=200 POST /post/ body=22 ct=true GET /target body=0 ct=false"),
        (302, "status=200 POST /post/ body=22 ct=true GET /target body=0 ct=false"),
        (303, "status=200 POST /post/ body=22 ct=true GET /target body=0 ct=false"),
        (307, "status=200 POST /post/ body=22 ct=true POST /target body=22 ct=true"),
        (308, "status=200 POST /post/ body=22 ct=true POST /target body=22 ct=true"),
        (300, "status=300 POST /post/ body=22 ct=true"),
        (304, "status=304 POST /post/ body=22 ct=true"),
    ])
    func scorePosterRedirectsLikeJava(code: Int, expected: String) async throws {
        let server = try FakeHttpServer()
        defer { server.stop() }
        server.respond(withHead: { head, _ in
            head.hasPrefix("POST /post/ ") || head.hasPrefix("GET /post/ ")
                ? .init(status: code, headers: ["Location: /target"]) : .init(status: 200, body: "ok")
        })
        let poster = Self.poster()
        let url = "http://127.0.0.1:\(server.port)/post/"
        let status = try await onOwnThread { try poster.post(url, xml: "<x>1</x>") }
        var parts: [String] = ["status=\(status)"]
        for index in server.requests.indices {
            let contentType = server.head(index).lowercased().contains("\r\ncontent-type:")
            parts.append(Self.requestLine(server.head(index)) + " body=\(server.body(index).count) ct=\(contentType)")
        }
        #expect(parts.joined(separator: " ") == expected)
    }

    /// `SP.redirectLoop`: a 302 loop → 4 redirects, the fifth 302 response is returned (5 requests).
    @Test func scorePosterRedirectLimitMatchesJava() async throws {
        let server = try FakeHttpServer(response: .init(status: 302, headers: ["Location: /loop"]))
        defer { server.stop() }
        let poster = Self.poster()
        let url = "http://127.0.0.1:\(server.port)/post/"
        let status = try await onOwnThread { try poster.post(url, xml: "<x/>") }
        #expect(status == 302)
        #expect(server.requests.count == 5)
    }

    /// `SP.refused`, `SP.badUrl`, `SP.ftpUrl`; closing without a reply = `IOException` (the text differs, `SP.closeNoReply`).
    @Test func scorePosterErrorsMatchJava() async throws {
        let poster = Self.poster()
        let refusedURL = "http://127.0.0.1:\(FreeLoopbackPort.take())/post/"
        let refused: String = await onOwnThread { () -> String in
            do throws(JavaHttpError) {
                return "status \(try poster.post(refusedURL, xml: "<x/>"))"
            } catch {
                return Self.describe(error)
            }
        }
        #expect(refused == "java.net.ConnectException|null")
        #expect(throws: JavaHttpError.illegalArgument(.init(message: "Illegal character in authority at index 8: http://a b/"))) {
            try poster.post("http://a b/", xml: "<x/>")
        }
        #expect(throws: JavaHttpError.illegalArgument(.init(message: "invalid URI scheme ftp"))) {
            try poster.post("ftp://host/", xml: "<x/>")
        }
        let server = try FakeHttpServer(response: .init(closeWithoutReply: true))
        defer { server.stop() }
        let closedURL = "http://127.0.0.1:\(server.port)/post/"
        let closed: String = await onOwnThread { () -> String in
            do throws(JavaHttpError) {
                return "status \(try poster.post(closedURL, xml: "<x/>"))"
            } catch {
                return error.javaClass
            }
        }
        #expect(closed == "java.io.IOException")
    }

    /// `CB.302`: callbooks do not follow redirects — a 3xx even with a body is returned, one request.
    @Test func callbookGetterDoesNotFollowRedirects() async throws {
        let server = try FakeHttpServer(response: .init(status: 302, body: "moved", headers: ["Location: /elsewhere"]))
        defer { server.stop() }
        let getter = URLSessionHttpGetter(requestTimeout: 120)
        let url = "http://127.0.0.1:\(server.port)/xml.php?id=1"
        let response = try await onOwnThread { try getter.get(url) }
        #expect(response == HttpGetResponse(status: 302, body: Data("moved".utf8)))
        #expect(server.requests.count == 1)
        #expect(server.head(0).hasPrefix("GET /xml.php?id=1 HTTP/1.1\r\n"))
        #expect(!server.head(0).lowercased().contains("\r\ncookie:"))
    }

    /// Session id with a space (measured on Java v1.1.1): `URI.create` → `IllegalArgumentException` with the Java text,
    /// nothing goes out to the network. `CB.refused`: `ConnectException` with message `null`.
    /// Generous request timeout: under load of the whole suite the completion of `URLSession` (delegate queue on GCD)
    /// can lag past the production 10 s and the watchdog would override the refusal with a timeout (measured).
    @Test func callbookGetterFailuresMatchJava() async throws {
        let getter = URLSessionHttpGetter(requestTimeout: 120)
        let spaced = "https://www.hamqth.com/xml.php?id=abc def&callsign=W1AW&prg=MacContestLogger"
        #expect(throws: HttpGetFailure("Illegal character in query at index 37: " + spaced,
                                       javaClass: "java.lang.IllegalArgumentException")) {
            try getter.get(spaced)
        }
        let refusedURL = "http://127.0.0.1:\(FreeLoopbackPort.take())/xml.php"
        let refused: HttpGetFailure? = await onOwnThread { () -> HttpGetFailure? in
            do throws(HttpGetFailure) {
                _ = try getter.get(refusedURL)
                return nil
            } catch {
                return error
            }
        }
        #expect(refused == HttpGetFailure(nil, javaClass: "java.net.ConnectException"))
    }

    /// `CB.timeout1s`: the server accepts the connection and does not answer → after the request timeout `HttpTimeoutException: request timed
    /// out` (connection established). Timeout 5 s so the connection is established even under suite load; only a lower bound of the time.
    @Test func requestTimeoutMatchesJava() async throws {
        let server = try FakeHttpServer(response: .init(status: 200, body: "late", delayMs: 60_000))
        defer { server.stop() }
        let getter = URLSessionHttpGetter(requestTimeout: 5)
        let url = "http://127.0.0.1:\(server.port)/xml.php"
        let start = ContinuousClock.now
        let failure: HttpGetFailure? = await onOwnThread { () -> HttpGetFailure? in
            do throws(HttpGetFailure) {
                _ = try getter.get(url)
                return nil
            } catch {
                return error
            }
        }
        #expect(ContinuousClock.now - start >= .seconds(5))
        #expect(failure == HttpGetFailure("request timed out", javaClass: "java.net.http.HttpTimeoutException"))
    }

    /// `SP.noLocation`, `SP.badLocation`, `SP.ftpLocation`: 302 without `Location` → `IOException: java.io.IOException:
    /// Invalid redirection`; a bad `Location` → `IllegalArgumentException` from `URI.create`; another scheme is not followed
    /// (302 is returned). Always one request.
    @Test(arguments: [
        ([String](), "java.io.IOException|java.io.IOException: Invalid redirection requests=1"),
        (["Location: /a b"], "java.lang.IllegalArgumentException|Illegal character in path at index 2: /a b requests=1"),
        (["Location: ftp://host/x"], "status=302 requests=1"),
    ])
    func scorePosterBadRedirectsMatchJava(headers: [String], expected: String) async throws {
        let server = try FakeHttpServer()
        defer { server.stop() }
        server.respond(withHead: { head, _ in
            head.hasPrefix("POST /post/ ") ? .init(status: 302, headers: headers) : .init(status: 200, body: "ok")
        })
        let poster = Self.poster()
        let url = "http://127.0.0.1:\(server.port)/post/"
        let result: String = await onOwnThread { () -> String in
            do throws(JavaHttpError) {
                return "status=\(try poster.post(url, xml: "<x/>"))"
            } catch {
                return Self.describe(error)
            }
        }
        #expect(result + " requests=\(server.requests.count)" == expected)
    }

    /// Production configuration = the Java one (`HamQthClient`/`QrzClient`, `ClubLogClient`, `ScorePoster`).
    @Test func productionTimeoutsMatchJava() {
        #expect(HamQthClient.connectTimeout == 8 && HamQthClient.requestTimeout == 10)
        #expect(QrzClient.connectTimeout == 8 && QrzClient.requestTimeout == 10)
        #expect(ClubLogClient.connectTimeout == 10 && ClubLogClient.requestTimeout == 20)
        #expect(ScorePoster.connectTimeout == 10 && ScorePoster.requestTimeout == 20)
        #expect(ScorePoster.defaultURL == "https://contestonlinescore.com/post/")
    }
}
