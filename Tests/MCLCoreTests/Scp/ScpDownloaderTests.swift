import Foundation
import Testing
@testable import MCLCore

/// The Java `scp/ScpDownloaderTest` (2 tests, a Java `HttpServer` on 127.0.0.1) against `FakeHttpServer` — never
/// a real server. The download blocks, so it runs on its own thread (`onOwnThread`), not in the shared pool.
@Suite struct ScpDownloaderTests {

    /// A server like the Java `@BeforeEach`: `/MASTER.SCP` (1,500 callsigns), `/error.html` (HTML, 200),
    /// `/missing` (404); plus `/moved` (302 to `/MASTER.SCP`) and `/drop` (a connection without a reply).
    private static func server() throws -> FakeHttpServer {
        var scp = "# master.scp test\n"
        for i in 0..<1500 {
            scp += "OK\(i % 10)A\(i)\n"
        }
        let master = scp
        let server = try FakeHttpServer()
        server.respond(withHead: { head, _ in
            let path: String = head.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            switch path {
            case "/MASTER.SCP": return .init(status: 200, contentType: "text/plain", body: master)
            case "/error.html": return .init(status: 200, contentType: "text/html", body: "<html><body>Not here</body></html>")
            case "/moved": return .init(status: 302, body: "", headers: ["Location: /MASTER.SCP"])
            case "/drop": return .init(closeWithoutReply: true)
            default: return .init(status: 404, contentType: "text/plain", body: "no")
            }
        })
        return server
    }

    private static func temporaryDirectory() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scp-dl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private static func entries(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted()
    }

    private static func text(_ path: String) -> String? {
        FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Java `new ScpDownloader()`: connect timeout 10 s, `Redirect.NORMAL`, request timeout 60 s
    /// (a generous guard, the successful path without wall-clock bounds).
    private static func download(_ url: String, _ target: String) async throws -> ScpDownloader.Result {
        try await onOwnThread { try ScpDownloader().download(url, to: target) }
    }

    @Test func downloadsAndReplaces() async throws {
        let server = try Self.server()
        defer { server.stop() }
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let target = dir + "/MASTER.SCP"
        try Data("OLD\n".utf8).write(to: URL(fileURLWithPath: target))

        let result = try await Self.download("http://127.0.0.1:\(server.port)/MASTER.SCP", target)

        #expect(result.calls == 1500)
        #expect(result.file == target)
        #expect(ScpDatabase.load(target).size == 1500)
        #expect(Self.entries(dir) == ["MASTER.SCP"], "the temporary file is cleaned up")
    }

    @Test func badContentKeepsOldFile() async throws {
        let server = try Self.server()
        defer { server.stop() }
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let target = dir + "/MASTER.SCP"
        try Data("OLD\n".utf8).write(to: URL(fileURLWithPath: target))
        let base = "http://127.0.0.1:\(server.port)"

        await #expect(throws: JavaHttpError.io(JavaIOError(
            "Stažený soubor nevypadá jako master.scp (0 volaček, 1 jiných řádků) — ponechávám původní"))) {
            _ = try await Self.download(base + "/error.html", target)
        }
        await #expect(throws: JavaHttpError.io(JavaIOError("Server vrátil HTTP 404"))) {
            _ = try await Self.download(base + "/missing", target)
        }
        #expect(Self.text(target) == "OLD\n")
        #expect(Self.entries(dir) == ["MASTER.SCP"])
    }

    /// Beyond the Java tests: a redirect is followed (`Redirect.NORMAL`), an interrupted connection leaves the old
    /// file, missing directories are created, the target has 0600 after writing (`createTempFile` + `ATOMIC_MOVE`),
    /// a directory at the target location makes the move fail — and the temporary `master*.scp.part` stays nowhere.
    @Test func downloadEdgesMatchJava() async throws {
        let server = try Self.server()
        defer { server.stop() }
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let base = "http://127.0.0.1:\(server.port)"

        let nested = dir + "/a/b/MASTER.SCP"
        let moved = try await Self.download(base + "/moved", nested)
        #expect(moved == ScpDownloader.Result(file: nested, calls: 1500))
        let attributes = try FileManager.default.attributesOfItem(atPath: nested)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(Self.entries(dir + "/a/b") == ["MASTER.SCP"])

        let target = dir + "/MASTER.SCP"
        try Data("OLD\n".utf8).write(to: URL(fileURLWithPath: target))
        await #expect(throws: JavaHttpError.self) {
            _ = try await Self.download(base + "/drop", target)
        }
        #expect(Self.text(target) == "OLD\n")

        let blocked = dir + "/blocked"
        try FileManager.default.createDirectory(atPath: blocked + "/inside", withIntermediateDirectories: true)
        await #expect(throws: JavaHttpError.self) {
            _ = try await Self.download(base + "/MASTER.SCP", blocked)
        }
        #expect(Self.entries(dir) == ["MASTER.SCP", "a", "blocked"])
        #expect(Self.entries(blocked) == ["inside"])
        #expect(ScpDownloader.defaultURI == "https://www.supercheckpartial.com/MASTER.SCP")
    }
}
