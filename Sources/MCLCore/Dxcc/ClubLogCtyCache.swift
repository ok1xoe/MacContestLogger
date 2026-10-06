import Foundation

/// The local copy of Club Log's `cty.xml` in `<dataDir>/clublog/`:
/// - `cty.xml` — the raw file as downloaded (after gunzip);
/// - `cty.json` — the parsed compact form (`ClubLogCtyData`), what the app loads at start-up;
/// - `cty-state.json` — the time of the last successful download and of the last attempt.
///
/// **The traffic promise to Club Log:** at most one request for `cty.xml` per 24 hours — the start-up check asks only
/// when neither a download nor an attempt happened in the last 24 hours, a manual update only when no download
/// succeeded in the last 24 hours. Every DXCC lookup is local; nothing is ever asked per QSO.
///
/// Blocking file I/O — call off the main thread.
public struct ClubLogCtyCache: Sendable {

    /// The minimum spacing of requests (24 h).
    public static let interval: TimeInterval = 24 * 60 * 60
    /// The download address without the key.
    public static let endpoint = "https://cdn.clublog.org/cty.php"

    public struct State: Codable, Equatable, Sendable {
        public var downloadedAt: Date?
        public var lastAttemptAt: Date?
        /// `<clublog date="…">` of the cached file.
        public var fileDate: String?

        public init(downloadedAt: Date? = nil, lastAttemptAt: Date? = nil, fileDate: String? = nil) {
            self.downloadedAt = downloadedAt
            self.lastAttemptAt = lastAttemptAt
            self.fileDate = fileDate
        }
    }

    public enum Trigger: Sendable {
        /// The check at start-up.
        case startup
        /// „Aktualizovat DXCC z Club Logu" (menu or Settings).
        case manual
    }

    /// Why a request was not made or why it failed.
    public enum Failure: Error, Equatable, Sendable {
        /// No API key in Settings → Score Reporting → Club Log.
        case noKey
        /// A request is not allowed yet (the 24 h spacing); `next` = when it is.
        case notDue(next: Date)
        /// HTTP 403 — Club Log refused the key.
        case forbidden
        /// Another HTTP status.
        case http(Int)
        /// No connection, a timeout… (the text without the key).
        case transport(String)
        /// The body is not a valid gzip stream.
        case gzip
        /// The XML could not be read.
        case parse(String)
        /// The cache could not be written.
        case write(String)
    }

    /// The result of a successful download.
    public struct Summary: Equatable, Sendable {
        public let entities: Int
        public let exceptions: Int
        public let prefixes: Int
        public let fileDate: String?
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `<dataDir>/clublog` (the data directory honours `MCL_DATA_DIR`).
    public init(dataDir: URL) {
        self.init(directory: dataDir.appendingPathComponent("clublog"))
    }

    public var xmlFile: URL { directory.appendingPathComponent("cty.xml") }
    public var compactFile: URL { directory.appendingPathComponent("cty.json") }
    public var stateFile: URL { directory.appendingPathComponent("cty-state.json") }

    /// The download address with the key (form-encoded). Never shown or logged.
    public static func url(apiKey: String) -> URL? {
        URL(string: endpoint + "?api=" + JavaUrlEncoder.encode(apiKey))
    }

    // MARK: - state

    public func readState() -> State {
        guard let data = try? Data(contentsOf: stateFile),
              let state = try? Self.decoder.decode(State.self, from: data) else {
            return State()
        }
        return state
    }

    private func writeState(_ state: State) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(state).write(to: stateFile, options: .atomic)
    }

    /// `nil` = a request is allowed now; otherwise when it is.
    public static func nextAllowed(_ trigger: Trigger, state: State, now: Date) -> Date? {
        var last: Date? = state.downloadedAt
        if trigger == .startup, let attempt = state.lastAttemptAt, attempt > (last ?? .distantPast) {
            last = attempt
        }
        guard let last else { return nil }
        let next = last.addingTimeInterval(interval)
        // A clock set back (the last time in the future) does not block for longer than one interval.
        return next > now && last <= now ? next : nil
    }

    // MARK: - loading

    /// The cached data: the compact form, else the raw `cty.xml` parsed again; `nil` without a usable copy.
    public func load() -> ClubLogCtyData? {
        if let data = try? Data(contentsOf: compactFile),
           let parsed = try? Self.decoder.decode(ClubLogCtyData.self, from: data), !parsed.entities.isEmpty {
            return parsed
        }
        guard let xml = try? Data(contentsOf: xmlFile) else { return nil }
        return try? ClubLogCtyParser.parse(xml)
    }

    // MARK: - the update in its phases (the caller runs the file phases off the main thread)

    /// Phase 1: may a request be made? Records the attempt when it may (so a crash or a hang still counts).
    /// - Returns: the address to fetch.
    public func begin(_ trigger: Trigger, apiKey: String, now: Date) throws(Failure) -> URL {
        let key = JavaText.trim(apiKey)
        guard !key.isEmpty, let url = Self.url(apiKey: key) else {
            throw .noKey
        }
        var state = readState()
        if let next = Self.nextAllowed(trigger, state: state, now: now) {
            throw .notDue(next: next)
        }
        state.lastAttemptAt = now
        do {
            try writeState(state)
        } catch {
            throw .write(ErrorText.message(error))
        }
        return url
    }

    /// Phase 2: the response. A good one replaces the cache (raw file, compact form, download time); anything else
    /// leaves the cached copy as it is.
    public func accept(status: Int, body: Data, now: Date) throws(Failure) -> (ClubLogCtyData, Summary) {
        guard status == 200 else {
            throw status == 403 ? .forbidden : .http(status)
        }
        let xml: Data
        if Gzip.isGzip(body) {
            do {
                xml = try Gzip.decompress(body)
            } catch {
                throw .gzip
            }
        } else {
            xml = body
        }
        let data: ClubLogCtyData
        do {
            data = try ClubLogCtyParser.parse(xml)
        } catch {
            throw .parse(error.reason)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try xml.write(to: xmlFile, options: .atomic)
            try Self.encoder.encode(data).write(to: compactFile, options: .atomic)
            var state = readState()
            state.downloadedAt = now
            state.fileDate = data.fileDate
            try writeState(state)
        } catch {
            throw .write(ErrorText.message(error))
        }
        return (data, Summary(entities: data.entities.count, exceptions: data.exceptions.count,
                              prefixes: data.prefixes.count, fileDate: data.fileDate))
    }

    /// The text of a transport error without the key (a `URLError` may carry the address).
    public static func transportText(_ error: any Error, apiKey: String) -> String {
        let text: String = (error as? URLError).map { $0.localizedDescription } ?? ErrorText.message(error)
        let key = JavaText.trim(apiKey)
        guard !key.isEmpty else { return text }
        return text.replacingOccurrences(of: key, with: "***")
            .replacingOccurrences(of: JavaUrlEncoder.encode(key), with: "***")
    }

    /// The whole update over a fetcher, the file phases inline (tests, command-line tools). The app runs the phases
    /// itself with the file work off the main thread.
    public func update(_ trigger: Trigger, apiKey: String, fetcher: any DataFetcher,
                       now: Date) async -> Result<(ClubLogCtyData, Summary), Failure> {
        let url: URL
        do {
            url = try begin(trigger, apiKey: apiKey, now: now)
        } catch {
            return .failure(error)
        }
        let response: (status: Int, data: Data)
        do {
            response = try await fetcher.fetch(url)
        } catch {
            return .failure(.transport(Self.transportText(error, apiKey: apiKey)))
        }
        do {
            return .success(try accept(status: response.status, body: response.data, now: now))
        } catch {
            return .failure(error)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
