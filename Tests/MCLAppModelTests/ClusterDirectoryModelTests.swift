import Foundation
import MCLAppModel
import MCLCore
import Testing

/// Settings → DX Cluster → „Vybrat ze seznamu": the list read from disk, the opt-in update (a scripted fetcher —
/// nothing reaches the network) and its failures.
@MainActor @Suite struct ClusterDirectoryModelTests {

    final class ScriptedFetcher: DataFetcher, @unchecked Sendable {
        private let lock = NSLock()
        private var reply: Result<(Int, Data), any Error>
        private(set) var urls: [URL] = []

        init(_ reply: Result<(Int, Data), any Error>) {
            self.reply = reply
        }

        func set(_ reply: Result<(Int, Data), any Error>) {
            lock.withLock { self.reply = reply }
        }

        var requested: [URL] { lock.withLock { urls } }

        func fetch(_ url: URL) async throws -> (status: Int, data: Data) {
            let reply = lock.withLock {
                urls.append(url)
                return self.reply
            }
            let (status, data) = try reply.get()
            return (status, data)
        }
    }

    nonisolated static func json(schema: Int = 1, updated: String, _ names: [String]) -> Data {
        let rows: [String] = names.enumerated().map { index, name in
            "{\"name\": \"\(name)\", \"host\": \"n\(index).example.org\", \"port\": 7300}"
        }
        return Data(("{\"schema\": \(schema), \"updated\": \"\(updated)\", \"clusters\": [" + rows.joined(separator: ",")
                     + "]}").utf8)
    }

    nonisolated static let bundled: @Sendable () -> ClusterDirectory? = {
        try? ClusterDirectory.parse(json(updated: "2026-10-01", ["Shipped"]))
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-clusterdir-model-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func loadsTheShippedListWithoutTouchingTheNetwork() async throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fetcher = ScriptedFetcher(.success((200, Self.json(updated: "2026-10-09", ["New"]))))
        let model = ClusterDirectoryModel(dataDir: dir, fetcher: fetcher, bundled: Self.bundled)
        await model.load()
        #expect(model.directory?.clusters.map(\.name) == ["Shipped"])
        #expect(model.origin == .bundled)
        #expect(model.statusLine == ContestMessage("Seznam dodaný s programem, aktualizován %s", .string("2026-10-01")))
        #expect(fetcher.requested.isEmpty)
    }

    @Test func updateStoresTheDownloadedCopy() async throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fetcher = ScriptedFetcher(.success((200, Self.json(updated: "2026-10-09", ["New", "Other"]))))
        let model = ClusterDirectoryModel(dataDir: dir, fetcher: fetcher, bundled: Self.bundled)
        await model.load()
        await model.update()
        #expect(fetcher.requested == [ClusterDirectory.defaultURL])
        #expect(model.directory?.clusters.map(\.name) == ["New", "Other"])
        #expect(model.origin == .downloaded)
        #expect(model.result == ContestMessage("Seznam clusterů aktualizován: %s clusterů (%s)", .int(2),
                                               .string("2026-10-09")))
        #expect(!model.updating)

        // A fresh model (the next start) reads the stored copy.
        let again = ClusterDirectoryModel(dataDir: dir, fetcher: nil, bundled: Self.bundled)
        await again.load()
        #expect(again.origin == .downloaded)
        #expect(again.directory?.clusters.count == 2)
    }

    @Test func failedUpdateKeepsTheListAndWritesNothing() async throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fetcher = ScriptedFetcher(.success((200, Self.json(schema: 2, updated: "2027-01-01", ["Future"]))))
        let model = ClusterDirectoryModel(dataDir: dir, fetcher: fetcher, bundled: Self.bundled)
        await model.load()
        await model.update()
        #expect(model.directory?.clusters.map(\.name) == ["Shipped"])
        #expect(model.result == ContestMessage(
            "Aktualizace seznamu clusterů selhala: %s (zůstává dosavadní seznam)",
            parts: [.message(ContestMessage("seznam je v novějším formátu, aktualizujte program"))]))
        let cache = ClusterDirectoryStore(dataDir: dir).cacheFile
        #expect(!FileManager.default.fileExists(atPath: cache.path))

        fetcher.set(.success((503, Data())))
        await model.update()
        #expect(model.result == ContestMessage(
            "Aktualizace seznamu clusterů selhala: %s (zůstává dosavadní seznam)",
            parts: [.message(ContestMessage.verbatim("HTTP 503"))]))
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func withoutNetworkTheUpdateOnlyReportsIt() async throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = ClusterDirectoryModel(dataDir: dir, fetcher: nil, bundled: Self.bundled)
        await model.update()
        #expect(model.result == ContestMessage("Síť je vypnutá (MCL_INERT_NETWORK)"))
        #expect(!FileManager.default.fileExists(atPath: ClusterDirectoryStore(dataDir: dir).cacheFile.path))
    }

    @Test func inertNetworkPortsHaveNoListFetcher() {
        #expect(NetworkPorts.inert.clusterList == nil)
        #expect(NetworkPorts.production(environment: ["MCL_INERT_NETWORK": "1"]).clusterList == nil)
    }
}
