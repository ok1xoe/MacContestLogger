import Foundation

/// The list of public DX cluster nodes the project keeps itself (N1MM's live cluster list comes from N1MM's own
/// reporting server; there is no public source to read). It is published as `cluster-data/clusters.json` in the
/// repository, a copy ships inside the app, and Settings → DX Cluster can download the current one on request.
///
/// The file is JSON: `schema` (this version reads `supportedSchema` and older), `updated` (`yyyy-MM-dd`) and
/// `clusters`, each with `name`, `host`, `port` and the optional `callsign`, `country`, `dxcc`, `grid`, `location`,
/// `software`, `login`, `skimmer`, `notes`, `rating` (0–5), `verified` (`yyyy-MM-dd`) and `source`. Unknown keys are
/// ignored, so newer files with the same schema stay readable; an entry that is not valid (no name, a host that is
/// not a host name, a port outside 1–65535) is skipped, and a file without a single valid entry is refused.
public struct ClusterDirectory: Equatable, Sendable {

    /// The newest schema this version understands; a file with a higher one is ignored (kept for newer apps).
    public static let supportedSchema = 1
    /// The largest file accepted (the download stops beyond it).
    public static let maxBytes = 256 * 1024
    /// The most entries read from one file.
    public static let maxEntries = 2_000
    /// Where the list is published (the only address the update ever contacts).
    public static let defaultURL = URL(
        string: "https://raw.githubusercontent.com/ok1xoe/MacContestLogger/main/cluster-data/clusters.json")!
    /// The bundled copy in the core's resources (`clusters.json`).
    public static let resourceName = "clusters"

    public struct Entry: Equatable, Sendable, Identifiable {
        public var name: String
        public var callsign: String = ""
        public var host: String
        public var port: Int
        public var country: String = ""
        public var dxcc: Int?
        public var grid: String = ""
        public var location: String = ""
        public var software: String = ""
        /// What to log in with (a hint, usually „your callsign").
        public var login: String = ""
        /// A skimmer / RBN feed rather than a node with human spots.
        public var skimmer: Bool = false
        public var notes: String = ""
        /// 0–5, higher is better; `nil` = not rated.
        public var rating: Int?
        /// The date the entry was last checked against its source (`yyyy-MM-dd`).
        public var verified: String = ""
        public var source: String = ""

        public init(name: String, host: String, port: Int) {
            self.name = name
            self.host = host
            self.port = port
        }

        /// `host:port` in lower case — the key duplicates are recognised by.
        public var id: String { host.lowercased() + ":" + String(port) }

        /// A favorite for Settings → DX Cluster with the given login (the station's callsign).
        public func favorite(login: String) -> DxClusterFavorite {
            DxClusterFavorite(name: name, host: host, port: port, login: login, password: "")
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        case tooLarge
        case notJSON
        case newerSchema(Int)
        case noClusters
        case http(Int)
        case transport(String)
        case write(String)
    }

    public enum SortOrder: String, CaseIterable, Sendable {
        case rating, country, name
    }

    public var schema: Int
    public var updated: String
    public var clusters: [Entry]

    public init(schema: Int = ClusterDirectory.supportedSchema, updated: String, clusters: [Entry]) {
        self.schema = schema
        self.updated = updated
        self.clusters = clusters
    }

    // MARK: - reading

    public static func parse(_ data: Data) throws(Failure) -> ClusterDirectory {
        guard data.count <= maxBytes else { throw .tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data), let root = object as? [String: Any],
              let schema = integer(root["schema"]), schema >= 1 else {
            throw .notJSON
        }
        guard schema <= supportedSchema else { throw .newerSchema(schema) }
        guard let rows = root["clusters"] as? [Any] else { throw .notJSON }
        var seen: Set<String> = []
        var clusters: [Entry] = []
        for row in rows.prefix(maxEntries) {
            guard let fields = row as? [String: Any], let entry = entry(fields), seen.insert(entry.id).inserted else {
                continue
            }
            clusters.append(entry)
        }
        guard !clusters.isEmpty else { throw .noClusters }
        return ClusterDirectory(schema: schema, updated: date(root["updated"]), clusters: clusters)
    }

    private static func entry(_ fields: [String: Any]) -> Entry? {
        let name: String = text(fields["name"], limit: 80)
        let host: String = text(fields["host"], limit: 253)
        guard !name.isEmpty, isHostName(host), let port = integer(fields["port"]), (1...65_535).contains(port) else {
            return nil
        }
        var entry = Entry(name: name, host: host, port: port)
        entry.callsign = text(fields["callsign"], limit: 20).uppercased()
        entry.country = text(fields["country"], limit: 80)
        entry.dxcc = integer(fields["dxcc"]).flatMap { (1...999).contains($0) ? $0 : nil }
        entry.grid = text(fields["grid"], limit: 10).uppercased()
        entry.location = text(fields["location"], limit: 80)
        entry.software = text(fields["software"], limit: 40)
        entry.login = text(fields["login"], limit: 80)
        entry.skimmer = (fields["skimmer"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue }
            ?? false
        entry.notes = text(fields["notes"], limit: 300)
        entry.rating = integer(fields["rating"]).flatMap { (0...5).contains($0) ? $0 : nil }
        entry.verified = date(fields["verified"])
        let source: String = text(fields["source"], limit: 300)
        entry.source = source.hasPrefix("https://") || source.hasPrefix("http://") ? source : ""
        return entry
    }

    /// A JSON integer (not a boolean, not a fraction).
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double: Double = number.doubleValue
        guard double.rounded() == double, abs(double) < 1e9 else { return nil }
        return Int(double)
    }

    /// A string trimmed, control characters replaced by spaces, cut to `limit` characters; anything else = `""`.
    private static func text(_ value: Any?, limit: Int) -> String {
        guard let string = value as? String else { return "" }
        let cleaned = String(String.UnicodeScalarView(string.unicodeScalars.map {
            $0.properties.generalCategory == .control ? " " : $0
        }))
        return String(cleaned.trimmingCharacters(in: .whitespaces).prefix(limit))
    }

    /// `yyyy-MM-dd`, otherwise `""`.
    private static func date(_ value: Any?) -> String {
        let string: String = text(value, limit: 10)
        let digits = string.unicodeScalars.enumerated().allSatisfy { index, scalar in
            index == 4 || index == 7 ? scalar == "-" : ("0"..."9").contains(scalar)
        }
        return string.count == 10 && digits ? string : ""
    }

    /// A DNS name or an IPv4 address: letters, digits, `-` and `.`, no empty label, no leading or trailing `-`.
    static func isHostName(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard !label.isEmpty, label.utf8.count <= 63, label.first != "-", label.last != "-" else { return false }
            return label.unicodeScalars.allSatisfy { $0.isASCII && ($0 == "-" || $0.properties.isAlphabetic
                || ("0"..."9").contains($0)) }
        }
    }

    // MARK: - choosing

    /// The entries every word of `query` occurs in (name, callsign, host, country, location, grid, software, notes;
    /// case and diacritics ignored); `skimmers == false` leaves the skimmer feeds out.
    public static func filter(_ entries: [Entry], query: String, skimmers: Bool = true) -> [Entry] {
        let words: [String] = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return entries.filter { entry in
            guard skimmers || !entry.skimmer else { return false }
            let haystack: String = [entry.name, entry.callsign, entry.host, entry.country, entry.location, entry.grid,
                                    entry.software, entry.notes].joined(separator: " ")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// Rating: best first, unrated last; country: alphabetical, without a country last; ties by name, then host:port.
    public static func sorted(_ entries: [Entry], by order: SortOrder) -> [Entry] {
        func byName(_ a: Entry, _ b: Entry) -> Bool {
            let result = a.name.localizedStandardCompare(b.name)
            return result == .orderedSame ? a.id < b.id : result == .orderedAscending
        }
        return entries.sorted { a, b in
            switch order {
            case .rating:
                if a.rating != b.rating { return (a.rating ?? -1) > (b.rating ?? -1) }
            case .country:
                if a.country.isEmpty != b.country.isEmpty { return !a.country.isEmpty }
                let result = a.country.localizedStandardCompare(b.country)
                if result != .orderedSame { return result == .orderedAscending }
            case .name:
                break
            }
            return byName(a, b)
        }
    }
}

/// The list on disk: the downloaded copy in the data directory (`cluster-data/clusters.json`) and the copy shipped
/// with the app. The newer of the two (by `updated`) is used; an unreadable copy or one with a newer schema is
/// ignored.
public struct ClusterDirectoryStore: Sendable {

    public enum Origin: Equatable, Sendable {
        case bundled, downloaded
    }

    public let cacheFile: URL

    public init(dataDir: URL) {
        cacheFile = dataDir.appendingPathComponent("cluster-data", isDirectory: true)
            .appendingPathComponent("clusters.json")
    }

    /// The copy shipped in the core's resources.
    @Sendable public static func bundled() -> ClusterDirectory? {
        guard let url = CoreResources.bundle?.url(forResource: ClusterDirectory.resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? ClusterDirectory.parse(data)
    }

    /// The downloaded copy, when there is a readable one.
    public func cached() -> ClusterDirectory? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return try? ClusterDirectory.parse(data)
    }

    /// The list to show: the downloaded copy unless the bundled one is newer.
    public func load(bundled: ClusterDirectory?) -> (directory: ClusterDirectory, origin: Origin)? {
        switch (cached(), bundled) {
        case let (cached?, bundled?):
            return bundled.updated > cached.updated ? (bundled, .bundled) : (cached, .downloaded)
        case let (cached?, nil):
            return (cached, .downloaded)
        case let (nil, bundled?):
            return (bundled, .bundled)
        case (nil, nil):
            return nil
        }
    }

    /// Replaces the downloaded copy (atomically) with bytes that `ClusterDirectory.parse` accepted.
    public func save(_ data: Data) throws(ClusterDirectory.Failure) {
        do {
            try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: cacheFile, options: .atomic)
        } catch {
            throw .write(error.localizedDescription)
        }
    }
}

/// The opt-in download of the published list: one GET of `url`, only HTTP 200, the body checked by
/// `ClusterDirectory.parse` before anything is written.
public struct ClusterDirectoryUpdater: Sendable {
    private let fetcher: any DataFetcher
    public let url: URL

    public init(fetcher: any DataFetcher, url: URL = ClusterDirectory.defaultURL) {
        self.fetcher = fetcher
        self.url = url
    }

    /// The downloaded bytes and what they hold; nothing is stored.
    public func download() async throws(ClusterDirectory.Failure) -> (data: Data, directory: ClusterDirectory) {
        let response: (status: Int, data: Data)
        do {
            response = try await fetcher.fetch(url)
        } catch let failure as ClusterDirectory.Failure {
            throw failure
        } catch {
            throw .transport(error.localizedDescription)
        }
        guard response.status == 200 else { throw .http(response.status) }
        return (response.data, try ClusterDirectory.parse(response.data))
    }
}

/// A `DataFetcher` for small published files: an ephemeral session (no cookies, no cache), the timeouts of
/// `URLSessionDataFetcher`, redirects followed only within the same scheme, host and port, and the body read only up
/// to `maxBytes` (beyond it the transfer is cancelled with `ClusterDirectory.Failure.tooLarge`).
///
/// The transfer is driven by delegate callbacks on the session's own queue, not by Swift concurrency: a busy
/// concurrency pool can delay the caller, but never stalls the transfer until it times out.
public struct BoundedDataFetcher: DataFetcher {
    public let maxBytes: Int

    public init(maxBytes: Int = ClusterDirectory.maxBytes) {
        self.maxBytes = maxBytes
    }

    public func fetch(_ url: URL) async throws -> (status: Int, data: Data) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let collector = Collector(maxBytes: maxBytes)
        let session = URLSession(configuration: configuration, delegate: collector, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(status: Int, data: Data), any Error>) in
                collector.begin(continuation)
                session.dataTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    /// Collects the body on the session's delegate queue and resumes the caller exactly once.
    private final class Collector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private let maxBytes: Int
        private var body = Data()
        private var status: Int = 0
        private var continuation: CheckedContinuation<(status: Int, data: Data), any Error>?

        init(maxBytes: Int) {
            self.maxBytes = maxBytes
        }

        func begin(_ continuation: CheckedContinuation<(status: Int, data: Data), any Error>) {
            lock.withLock { self.continuation = continuation }
        }

        private func finish(_ result: Result<(status: Int, data: Data), any Error>) {
            let waiting = lock.withLock {
                defer { continuation = nil }
                return continuation
            }
            waiting?.resume(with: result)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            if response.expectedContentLength > Int64(maxBytes) {
                finish(.failure(ClusterDirectory.Failure.tooLarge))
                completionHandler(.cancel)
                return
            }
            lock.withLock { status = (response as? HTTPURLResponse)?.statusCode ?? 0 }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            let tooLarge: Bool = lock.withLock {
                body.append(data)
                return body.count > maxBytes
            }
            if tooLarge {
                finish(.failure(ClusterDirectory.Failure.tooLarge))
                dataTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            let from = task.originalRequest?.url
            let to = request.url
            let same: Bool = from?.scheme?.lowercased() == to?.scheme?.lowercased()
                && from?.host?.lowercased() == to?.host?.lowercased() && from?.port == to?.port
            completionHandler(same ? request : nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            if let error {
                finish(.failure(error))
            } else {
                let result = lock.withLock { (status: status, data: body) }
                finish(.success(result))
            }
        }
    }
}
