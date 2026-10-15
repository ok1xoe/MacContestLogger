import Foundation
import Testing
@testable import MCLCore

/// The published DX cluster list (`cluster-data/clusters.json`): reading, choosing, the copy on disk and the opt-in
/// download. The network tests talk only to `FakeHttpServer` on `127.0.0.1` with an ephemeral port.
@Suite struct ClusterDirectoryTests {

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    static func json(schema: Int = 1, updated: String = "2026-10-01", _ rows: [String]) -> Data {
        Data(("{\"schema\": \(schema), \"updated\": \"\(updated)\", \"clusters\": [" + rows.joined(separator: ",")
              + "]}").utf8)
    }

    static func row(_ name: String, _ host: String, _ port: Int, extra: String = "") -> String {
        "{\"name\": \"\(name)\", \"host\": \"\(host)\", \"port\": \(port)\(extra.isEmpty ? "" : ", " + extra)}"
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-clusterdir-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - the published file

    @Test func publishedFileIsTheBundledCopyAndValid() throws {
        let published = Self.repoRoot.appendingPathComponent("cluster-data/clusters.json")
        guard FileManager.default.fileExists(atPath: published.path) else { return }  // source tree not available
        let bundledCopy = Self.repoRoot.appendingPathComponent("Sources/MCLCore/Resources/clusters.json")
        let data = try Data(contentsOf: published)
        #expect(data == (try Data(contentsOf: bundledCopy)), "cluster-data/clusters.json differs from the bundled copy")
        let directory = try ClusterDirectory.parse(data)
        #expect(directory.schema == ClusterDirectory.supportedSchema)
        #expect(directory.updated.count == 10)
        // Every row parsed (none skipped) and every row names the public source it was checked against.
        let rows = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["clusters"] as? [Any]
        #expect(rows?.count == directory.clusters.count)
        for entry in directory.clusters {
            #expect(entry.source.hasPrefix("https://"), "\(entry.name) has no source")
            #expect(!entry.verified.isEmpty, "\(entry.name) has no verified date")
        }
    }

    @Test func bundledCopyIsFoundInTheResources() {
        #expect(ClusterDirectoryStore.bundled()?.clusters.isEmpty == false)
    }

    // MARK: - parsing

    @Test func parsesFieldsAndIgnoresUnknownKeys() throws {
        let data = Self.json([Self.row("Node", "dx.example.org", 7300, extra: """
            "callsign": "ok1abc", "country": " Czech Republic ", "dxcc": 503, "grid": "jo70", "software": "DXSpider",
            "login": "your callsign", "skimmer": true, "notes": "a\\tb", "rating": 4, "verified": "2026-10-15",
            "source": "https://example.org/", "future": {"x": 1}
            """)])
        let entry = try #require(try ClusterDirectory.parse(data).clusters.first)
        #expect(entry.name == "Node")
        #expect(entry.callsign == "OK1ABC")
        #expect(entry.country == "Czech Republic")
        #expect(entry.dxcc == 503)
        #expect(entry.grid == "JO70")
        #expect(entry.skimmer)
        #expect(entry.notes == "a b")
        #expect(entry.rating == 4)
        #expect(entry.verified == "2026-10-15")
        #expect(entry.id == "dx.example.org:7300")
    }

    @Test func skipsInvalidAndDuplicateEntries() throws {
        let data = Self.json([
            Self.row("Good", "a.example.org", 7300),
            Self.row("", "b.example.org", 7300),               // no name
            Self.row("Bad host", "evil host;rm", 7300),        // not a host name
            Self.row("Bad port", "c.example.org", 70_000),     // port out of range
            "{\"name\": \"Bool port\", \"host\": \"d.example.org\", \"port\": true}",
            Self.row("Dup", "A.EXAMPLE.ORG", 7300),            // same host:port as Good
            Self.row("Other port", "a.example.org", 7373, extra: "\"rating\": 9, \"verified\": \"yesterday\", "
                     + "\"source\": \"javascript:x\", \"skimmer\": 1"),
        ])
        let clusters = try ClusterDirectory.parse(data).clusters
        #expect(clusters.map(\.name) == ["Good", "Other port"])
        #expect(clusters[1].rating == nil)
        #expect(clusters[1].verified == "")
        #expect(clusters[1].source == "")
        #expect(clusters[1].skimmer == false)
    }

    @Test func refusesFilesItCannotUse() {
        #expect(throws: ClusterDirectory.Failure.newerSchema(2)) {
            try ClusterDirectory.parse(Self.json(schema: 2, [Self.row("A", "a.example.org", 7300)]))
        }
        #expect(throws: ClusterDirectory.Failure.notJSON) { try ClusterDirectory.parse(Data("<html>".utf8)) }
        #expect(throws: ClusterDirectory.Failure.notJSON) { try ClusterDirectory.parse(Data("{\"clusters\": []}".utf8)) }
        #expect(throws: ClusterDirectory.Failure.noClusters) {
            try ClusterDirectory.parse(Self.json([Self.row("", "", 0)]))
        }
        #expect(throws: ClusterDirectory.Failure.tooLarge) {
            try ClusterDirectory.parse(Data(repeating: 0x20, count: ClusterDirectory.maxBytes + 1))
        }
    }

    @Test func hostNames() {
        #expect(ClusterDirectory.isHostName("telnet.reversebeacon.net"))
        #expect(ClusterDirectory.isHostName("192.168.1.10"))
        #expect(!ClusterDirectory.isHostName("-bad.example.org"))
        #expect(!ClusterDirectory.isHostName("a..b"))
        #expect(!ClusterDirectory.isHostName("ex ample.org"))
        #expect(!ClusterDirectory.isHostName("exämple.org"))
    }

    // MARK: - choosing

    static let sample: [ClusterDirectory.Entry] = {
        var a = ClusterDirectory.Entry(name: "Alpha", host: "a.example.org", port: 7300)
        a.country = "Germany"
        a.rating = 3
        var b = ClusterDirectory.Entry(name: "Bravo", host: "b.example.org", port: 7300)
        b.country = "Česko"
        b.software = "DXSpider"
        var c = ClusterDirectory.Entry(name: "Charlie RBN", host: "c.example.org", port: 7000)
        c.skimmer = true
        c.rating = 5
        return [a, b, c]
    }()

    @Test func filtersByEveryWord() {
        #expect(ClusterDirectory.filter(Self.sample, query: "").count == 3)
        #expect(ClusterDirectory.filter(Self.sample, query: "cesko").map(\.name) == ["Bravo"])
        #expect(ClusterDirectory.filter(Self.sample, query: "dxspider bravo").map(\.name) == ["Bravo"])
        #expect(ClusterDirectory.filter(Self.sample, query: "dxspider alpha").isEmpty)
        #expect(ClusterDirectory.filter(Self.sample, query: "", skimmers: false).map(\.name) == ["Alpha", "Bravo"])
    }

    @Test func sortsByRatingCountryAndName() {
        #expect(ClusterDirectory.sorted(Self.sample, by: .rating).map(\.name) == ["Charlie RBN", "Alpha", "Bravo"])
        #expect(ClusterDirectory.sorted(Self.sample, by: .country).map(\.name) == ["Bravo", "Alpha", "Charlie RBN"])
        #expect(ClusterDirectory.sorted(Self.sample.reversed(), by: .name).map(\.name)
                == ["Alpha", "Bravo", "Charlie RBN"])
    }

    @MainActor @Test func chosenClusterBecomesAFavoriteOnce() {
        var draft = ConfigurerDraft(config: AppConfig(), bandSegments: [], digi: DigiFreqFile.Table(channels: []),
                                    defaultContestDataDir: "")
        draft.call = " ok1xyz "
        let entry = Self.sample[0]
        let first: Bool = draft.addDxFavorite(from: entry)
        let second: Bool = draft.addDxFavorite(from: entry)
        #expect(first)
        #expect(!second)
        #expect(draft.dxFavorites.count == 1)
        let favorite = draft.dxFavorites[0].toFavorite()
        #expect(favorite == DxClusterFavorite(name: "Alpha", host: "a.example.org", port: 7300, login: "OK1XYZ",
                                              password: ""))
    }

    // MARK: - the copy on disk

    @Test func storeUsesTheNewerCopy() throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClusterDirectoryStore(dataDir: dir)
        let bundled = try ClusterDirectory.parse(Self.json(updated: "2026-10-01", [Self.row("B", "b.example.org", 1)]))
        #expect(store.load(bundled: bundled)?.origin == .bundled)
        #expect(store.load(bundled: nil) == nil)

        try store.save(Self.json(updated: "2026-10-05", [Self.row("C", "c.example.org", 1)]))
        #expect(store.load(bundled: bundled)?.origin == .downloaded)
        #expect(store.load(bundled: bundled)?.directory.clusters.first?.name == "C")
        // A newer app version shipped a newer list than the old download.
        let newer = try ClusterDirectory.parse(Self.json(updated: "2026-11-01", [Self.row("N", "n.example.org", 1)]))
        #expect(store.load(bundled: newer)?.origin == .bundled)

        // A cached copy this version cannot read is ignored.
        try store.save(Self.json(schema: 2, updated: "2027-01-01", [Self.row("F", "f.example.org", 1)]))
        #expect(store.load(bundled: bundled)?.origin == .bundled)
    }

    // MARK: - download (fake server on 127.0.0.1)

    static func url(_ server: FakeHttpServer, _ path: String = "/cluster-data/clusters.json") -> URL {
        URL(string: "http://127.0.0.1:\(server.port)" + path)!
    }

    @Test func downloadsAndValidatesThroughTheBoundedFetcher() async throws {
        let body = String(decoding: Self.json([Self.row("Node", "dx.example.org", 7300)]), as: UTF8.self)
        let server = try FakeHttpServer(response: .init(status: 200, contentType: "application/json", body: body))
        defer { server.stop() }
        let updater = ClusterDirectoryUpdater(fetcher: BoundedDataFetcher(), url: Self.url(server))
        let result = try await updater.download()
        #expect(result.directory.clusters.map(\.host) == ["dx.example.org"])
        #expect(server.head(0).hasPrefix("GET /cluster-data/clusters.json HTTP/1.1"))
    }

    @Test func httpErrorsAndInvalidBodiesFail() async throws {
        let server = try FakeHttpServer(response: .init(status: 404))
        defer { server.stop() }
        let updater = ClusterDirectoryUpdater(fetcher: BoundedDataFetcher(), url: Self.url(server))
        await #expect(throws: ClusterDirectory.Failure.http(404)) { try await updater.download() }
        server.respond(.init(status: 200, contentType: "text/html", body: "<html>rate limited</html>"))
        await #expect(throws: ClusterDirectory.Failure.notJSON) { try await updater.download() }
    }

    @Test func oversizedBodyIsCutOff() async throws {
        let server = try FakeHttpServer(response: .init(status: 200, body: String(repeating: "x", count: 4_096)))
        defer { server.stop() }
        let updater = ClusterDirectoryUpdater(fetcher: BoundedDataFetcher(maxBytes: 1_024), url: Self.url(server))
        await #expect(throws: ClusterDirectory.Failure.tooLarge) { try await updater.download() }
    }

    @Test func redirectsAreFollowedOnlyOnTheSameHost() async throws {
        let body = String(decoding: Self.json([Self.row("Node", "dx.example.org", 7300)]), as: UTF8.self)
        let server = try FakeHttpServer()
        defer { server.stop() }
        let port = server.port
        server.respond(withHead: { head, _ in
            if head.hasPrefix("GET /moved ") {
                return .init(status: 302, headers: ["Location: http://127.0.0.1:\(port)/cluster-data/clusters.json"])
            }
            if head.hasPrefix("GET /away ") {
                // Another host (a name instead of the address): not followed, so nothing connects there.
                return .init(status: 302, headers: ["Location: http://elsewhere.invalid:\(port)/clusters.json"])
            }
            return .init(status: 200, contentType: "application/json", body: body)
        })
        let same = ClusterDirectoryUpdater(fetcher: BoundedDataFetcher(), url: Self.url(server, "/moved"))
        #expect(try await same.download().directory.clusters.count == 1)
        let away = ClusterDirectoryUpdater(fetcher: BoundedDataFetcher(), url: Self.url(server, "/away"))
        await #expect(throws: ClusterDirectory.Failure.http(302)) { try await away.download() }
    }
}
