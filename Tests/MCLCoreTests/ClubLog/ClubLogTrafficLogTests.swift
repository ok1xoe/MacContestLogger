import Foundation
import Testing
@testable import MCLCore

/// `clublog.log`: what is sent to Club Log is logged, the secrets never are.
@Suite struct ClubLogTrafficLogTests {

    private static let password = "S3cretPw!x"
    private static let apiKey = "APIKEY0123456789"

    private static func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("clublog-log-\(UUID().uuidString)").appendingPathComponent("clublog.log")
    }

    private static func lines(_ file: URL) -> [String] {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    private func upload(_ server: FakeHttpServer, _ log: ClubLogTrafficLog) async throws -> ClubLogClient.Outcome {
        let client = ClubLogClient(http: JavaHttpClient(connectTimeout: nil, redirect: .never),
                                   url: "http://127.0.0.1:\(server.port)/realtime.php", requestTimeout: 120,
                                   trafficLog: log)
        return try await onOwnThread {
            try client.upload(email: "tomas@example.com", password: Self.password, callsign: "OK1XOE",
                              apiKey: Self.apiKey, adifRecord: "<CALL:4>W1AW <EOR>")
        }
    }

    @Test func uploadOkRejectedAndRetryAreLoggedWithMaskedSecrets() async throws {
        let file = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let log = ClubLogTrafficLog(file: file)
        let server = try FakeHttpServer(response: .init(status: 200))
        defer { server.stop() }
        #expect(try await upload(server, log) == .OK)
        server.respond(.init(status: 403, body: "Login failed \(Self.password) \(Self.apiKey)\nsecond"))
        #expect(try await upload(server, log) == .REJECTED)
        server.respond(.init(status: 500))
        #expect(try await upload(server, log) == .RETRY)
        log.note(ClubLogQueuePolicy.logNote(.OK, queued: 2))
        log.note(ClubLogQueuePolicy.logNote(.REJECTED, queued: 0))
        log.note(ClubLogQueuePolicy.logNote(.RETRY, queued: 0))

        let text = try String(contentsOf: file, encoding: .utf8)
        let lines = Self.lines(file)
        #expect(lines.contains { $0.contains("\u{2192} POST http://127.0.0.1:\(server.port)/realtime.php") })
        #expect(lines.contains { $0.contains("email=t***@example.com password=*** api=*** callsign=OK1XOE") })
        #expect(lines.contains { $0.hasSuffix("\u{2192} adif=<CALL:4>W1AW <EOR>") })
        #expect(lines.contains { $0.contains("\u{2190} HTTP 200") })
        #expect(lines.contains { $0.contains("\u{2190} HTTP 403 Login failed *** ***") })
        #expect(!text.contains("second"))
        #expect(lines.contains { $0.contains("\u{2190} HTTP 500") })
        #expect(lines.contains { $0.hasSuffix("\u{00B7} sent (queued 2)") })
        #expect(lines.contains { $0.hasSuffix("\u{00B7} dropped (rejected)") })
        #expect(lines.contains { $0.hasSuffix("\u{00B7} retry in 60 s (queued 1)") })
        // Local time stamp HH:mm:ss.SSS.
        #expect(lines.allSatisfy { $0.range(of: #"^\d\d:\d\d:\d\d\.\d{3}  "#, options: .regularExpression) != nil })
        #expect(!text.contains(Self.password))
        #expect(!text.contains(Self.apiKey))
        #expect(!text.contains("tomas@"))
    }

    @Test func networkErrorIsLoggedWithoutSecrets() async throws {
        let file = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let log = ClubLogTrafficLog(file: file)
        let server = try FakeHttpServer(response: .init(closeWithoutReply: true))
        defer { server.stop() }
        #expect(try await upload(server, log) == .RETRY)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\u{00B7} error: "))
        #expect(!text.contains(Self.password) && !text.contains(Self.apiKey))
    }

    @Test func ctyDownloadIsLoggedWithMaskedKey() throws {
        let file = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let log = ClubLogTrafficLog(file: file)
        let url = try #require(ClubLogCtyCache.url(apiKey: Self.apiKey))
        log.ctyRequest(url: url)
        log.ctyResponse(status: 200, bytes: 12345)
        log.failure("timed out for \(Self.apiKey)", secrets: [Self.apiKey])
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\u{2192} GET https://cdn.clublog.org/cty.php?api=***\n"))
        #expect(text.contains("\u{2190} HTTP 200, 12345 bytes"))
        #expect(!text.contains(Self.apiKey))
    }

    @Test func noFileWhenUnused() {
        let file = Self.tempFile()
        _ = ClubLogTrafficLog(file: file)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        // Without a file nothing is written and nothing fails.
        ClubLogTrafficLog().note("x")
    }
}
