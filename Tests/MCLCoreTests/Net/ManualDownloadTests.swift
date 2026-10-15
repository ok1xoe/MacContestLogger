import Foundation
@testable import MCLCore
import Testing

/// The PDF and HTML manual download (Help → „Stáhnout nejnovější PDF / HTML manuál…"): only GitHub's HTTPS hosts,
/// redirects only to allowed hosts, a size limit and a check of the format. The fetch runs against a fake HTTP server on 127.0.0.1 only.
@Suite struct ManualDownloadTests {

    static let pdf = "%PDF-1.7\nfake manual\n%%EOF\n"
    static let html = "<!DOCTYPE html>\n<html lang=\"en\"><body>fake manual</body></html>\n"

    @Test func onlyGitHubDownloadsAreAllowed() throws {
        #expect(ManualDownload.isAllowed(try #require(URL(string: ManualDownload.latestUrl))))
        #expect(ManualDownload.isAllowed(try #require(URL(string: "https://objects.githubusercontent.com/x"))))
        #expect(ManualDownload.isAllowed(try #require(URL(string: "https://release-assets.githubusercontent.com/x"))))
        #expect(!ManualDownload.isAllowed(try #require(URL(string: "http://github.com/ok1xoe/MacContestLogger"))))
        #expect(!ManualDownload.isAllowed(try #require(URL(string: "https://github.com.example.org/x"))))
        #expect(!ManualDownload.isAllowed(try #require(URL(string: "https://example.com/manual.pdf"))))
        #expect(ManualDownload.latestUrl.hasSuffix("/releases/latest/download/" + ManualDownload.assetName))
        #expect(ManualDownload.Format.pdf.latestUrl
                == "https://github.com/ok1xoe/MacContestLogger/releases/latest/download/MacContestLogger-manual.pdf")
        #expect(ManualDownload.Format.html.latestUrl
                == "https://github.com/ok1xoe/MacContestLogger/releases/latest/download/MacContestLogger-manual.html")
        #expect(ManualDownload.isAllowed(try #require(URL(string: ManualDownload.Format.html.latestUrl))))
    }

    @Test func answersAreChecked() {
        #expect(ManualDownload.evaluate(status: 200, body: Data(Self.pdf.utf8)) == .file(Data(Self.pdf.utf8)))
        #expect(ManualDownload.evaluate(status: 200, body: Data("<html>".utf8)) == .wrongFormat)
        #expect(ManualDownload.evaluate(status: 200, body: Data("%PD".utf8)) == .wrongFormat)
        let html = Data(Self.html.utf8)
        #expect(ManualDownload.evaluate(status: 200, body: html, format: .html) == .file(html))
        #expect(ManualDownload.evaluate(status: 200, body: Data(Self.pdf.utf8), format: .html) == .wrongFormat)
        #expect(ManualDownload.evaluate(status: 200, body: html, format: .pdf) == .wrongFormat)
        #expect(ManualDownload.evaluate(status: 404, body: Data(), format: .html) == .notPublished)
        #expect(ManualDownload.isHtml(Data(([0xEF, 0xBB, 0xBF] + Array(" \n<HTML lang=\"en\">".utf8)))))
        #expect(ManualDownload.isHtml(Data("<!doctype html><html></html>".utf8)))
        #expect(!ManualDownload.isHtml(Data("<?xml version=\"1.0\"?><svg/>".utf8)))
        #expect(!ManualDownload.isHtml(Data("{\"message\": \"Not Found\"}".utf8)))
        #expect(!ManualDownload.isHtml(Data()))
        #expect(ManualDownload.evaluate(status: 404, body: Data()) == .notPublished)
        #expect(ManualDownload.evaluate(status: 500, body: Data()) == .httpStatus(500))
    }

    static func loopback(_ ports: Int...) -> @Sendable (URL) -> Bool {
        { url in url.host == "127.0.0.1" && ports.contains(url.port ?? -1) }
    }

    /// Generous timeouts: under the load of the whole suite on a CI runner `URLSession` can lag by minutes.
    static func fetcher(_ allow: @escaping @Sendable (URL) -> Bool, maxBytes: Int = ManualDownload.maxBytes)
        -> ManualDownloader {
        ManualDownloader(allow: allow, maxBytes: maxBytes, requestTimeout: 600, timeout: 900)
    }

    @Test func downloadsAPdf() async throws {
        let server = try FakeHttpServer(response: .init(contentType: "application/pdf", body: Self.pdf))
        defer { server.stop() }
        let fetch = Self.fetcher(Self.loopback(server.port))
        let outcome = await fetch.fetch("http://127.0.0.1:\(server.port)/manual.pdf")
        #expect(outcome == .file(Data(Self.pdf.utf8)))
        #expect(server.head(0).hasPrefix("GET /manual.pdf HTTP/1.1\r\n"))
    }

    @Test func downloadsTheHtmlAndChecksItsFormat() async throws {
        let server = try FakeHttpServer(response: .init(contentType: "text/html", body: Self.html))
        defer { server.stop() }
        let fetch = Self.fetcher(Self.loopback(server.port))
        let url = "http://127.0.0.1:\(server.port)/manual.html"
        #expect(await fetch.fetch(url, format: .html) == .file(Data(Self.html.utf8)))
        #expect(server.head(0).hasPrefix("GET /manual.html HTTP/1.1\r\n"))
        #expect(server.head(0).lowercased().contains("accept: text/html"))
        // The HTML request takes no PDF, and the PDF request no HTML.
        #expect(await fetch.fetch(url, format: .pdf) == .wrongFormat)
        server.respond(.init(contentType: "application/octet-stream", body: Self.pdf))
        #expect(await fetch.fetch(url, format: .html) == .wrongFormat)
        server.respond(.init(contentType: "text/html", body: Self.html + String(repeating: "x", count: 200_000)))
        #expect(await Self.fetcher(Self.loopback(server.port), maxBytes: 1_000).fetch(url, format: .html) == .tooLarge)
        server.respond(.init(status: 404, body: "Not Found"))
        #expect(await fetch.fetch(url, format: .html) == .notPublished)
    }

    @Test func rejectsWhatIsNotTheManual() async throws {
        let server = try FakeHttpServer(response: .init(contentType: "text/html", body: "<html>not here</html>"))
        defer { server.stop() }
        let fetch = Self.fetcher(Self.loopback(server.port), maxBytes: 1_000)
        let url = "http://127.0.0.1:\(server.port)/manual.pdf"
        #expect(await fetch.fetch(url) == .wrongFormat)
        server.respond(.init(status: 404, body: "Not Found"))
        #expect(await fetch.fetch(url) == .notPublished)
        server.respond(.init(status: 500))
        #expect(await fetch.fetch(url) == .httpStatus(500))
        server.respond(.init(contentType: "application/pdf", body: Self.pdf + String(repeating: "x", count: 200_000)))
        #expect(await fetch.fetch(url) == .tooLarge)
        // A start address outside the allowed hosts is never requested.
        let before: Int = server.requests.count
        #expect(await ManualDownloader().fetch(url) == .redirectRefused(url))
        #expect(server.requests.count == before)
    }

    @Test func followsAllowedRedirectsOnly() async throws {
        let target = try FakeHttpServer(response: .init(contentType: "application/pdf", body: Self.pdf))
        defer { target.stop() }
        let start = try FakeHttpServer(response: .init(status: 302, body: "",
                                                       headers: ["Location: http://127.0.0.1:\(target.port)/asset.pdf"]))
        defer { start.stop() }
        let url = "http://127.0.0.1:\(start.port)/latest/download/manual.pdf"
        let allowed = await Self.fetcher(Self.loopback(start.port, target.port)).fetch(url)
        #expect(allowed == .file(Data(Self.pdf.utf8)))
        #expect(target.requests.count == 1)
        let refused = await Self.fetcher(Self.loopback(start.port)).fetch(url)
        #expect(refused == .redirectRefused("127.0.0.1"))
        #expect(target.requests.count == 1)
    }
}
