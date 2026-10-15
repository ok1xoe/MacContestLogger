import Foundation

/// N1MM „Download latest PDF manual": the PDF user guide attached to the project's newest published GitHub release
/// (built from `docs/` by `mcl-manual` in the release workflow). Only on the user's click; the address is fixed to
/// the project's releases, redirects are followed only to GitHub's own download hosts, the size is limited and the
/// bytes must be a PDF before anything is saved.
public enum ManualDownload {

    /// The release asset's file name (the same in every release, so `latest/download/` finds it).
    public static let assetName = "MacContestLogger-manual.pdf"
    /// The newest published release's copy (drafts and pre-releases are left out by GitHub).
    public static let latestUrl = "https://github.com/ok1xoe/MacContestLogger/releases/latest/download/" + assetName
    /// Where to look when the download is not possible (the online guide).
    public static let docsUrl = "https://github.com/ok1xoe/MacContestLogger/tree/main/docs"
    /// A larger answer is not the manual (it is about 4 MB).
    public static let maxBytes = 64 * 1_024 * 1_024
    /// Generous: the file is a few megabytes and the user waits for it on purpose.
    public static let timeoutSeconds: TimeInterval = 120

    /// What the download ended with.
    public enum Outcome: Equatable, Sendable {
        case pdf(Data)
        /// The release has no manual yet (HTTP 404).
        case notPublished
        /// Another HTTP status.
        case httpStatus(Int)
        /// Larger than `maxBytes`.
        case tooLarge
        /// The bytes are not a PDF.
        case notPdf
        /// A redirect to a host outside GitHub's downloads.
        case redirectRefused(String)
        /// A network error (its text).
        case failed(String)
    }

    /// Whether a download may go to (or be redirected to) `url`: HTTPS on GitHub or its release-asset hosts.
    public static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host == "objects.githubusercontent.com"
            || host == "release-assets.githubusercontent.com" || host.hasSuffix(".githubusercontent.com")
    }

    /// A PDF starts with `%PDF-`.
    public static func isPdf(_ data: Data) -> Bool {
        data.count >= 5 && data.prefix(5).elementsEqual("%PDF-".utf8)
    }

    /// The outcome of a finished answer.
    public static func evaluate(status: Int, body: Data) -> Outcome {
        switch status {
        case 200:
            guard body.count <= maxBytes else { return .tooLarge }
            return isPdf(body) ? .pdf(body) : .notPdf
        case 404:
            return .notPublished
        default:
            return .httpStatus(status)
        }
    }
}

/// Fetches the manual; replaceable in tests (the app model gets it from its network ports).
public typealias ManualFetcher = @Sendable (_ url: String) async -> ManualDownload.Outcome

/// The production fetch over `URLSession`: no cookies or cache, redirects only where `allow` says, the body read in
/// pieces and abandoned as soon as it passes `maxBytes`.
public struct ManualDownloader: Sendable {

    let allow: @Sendable (URL) -> Bool
    let maxBytes: Int
    let timeout: TimeInterval

    public init(allow: @escaping @Sendable (URL) -> Bool = ManualDownload.isAllowed,
                maxBytes: Int = ManualDownload.maxBytes, timeout: TimeInterval = ManualDownload.timeoutSeconds) {
        self.allow = allow
        self.maxBytes = maxBytes
        self.timeout = timeout
    }

    /// Checks every redirect against the allow list and remembers a refused one.
    final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let allow: @Sendable (URL) -> Bool
        private let lock = NSLock()
        private var refusedValue: String?

        init(allow: @escaping @Sendable (URL) -> Bool) {
            self.allow = allow
        }

        var refused: String? {
            lock.withLock { refusedValue }
        }

        // The completion-handler form (not `async`): the answer never waits for a free thread of the shared pool.
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            guard let url = request.url, allow(url) else {
                lock.withLock { refusedValue = request.url?.host ?? request.url?.absoluteString ?? "?" }
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }

    public func fetch(_ address: String) async -> ManualDownload.Outcome {
        guard let url = URL(string: address), allow(url) else { return .redirectRefused(address) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = timeout
        let guardian = RedirectGuard(allow: allow)
        let session = URLSession(configuration: configuration, delegate: guardian, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("MacContestLogger", forHTTPHeaderField: "User-Agent")
        request.setValue("application/pdf, application/octet-stream", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed("no HTTP response") }
            if let refused = guardian.refused {
                return .redirectRefused(refused)
            }
            guard http.statusCode == 200 else {
                return ManualDownload.evaluate(status: http.statusCode, body: Data())
            }
            if http.expectedContentLength > Int64(maxBytes) {
                return .tooLarge
            }
            var body = Data()
            var chunk: [UInt8] = []
            chunk.reserveCapacity(65_536)
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count == 65_536 {
                    body.append(contentsOf: chunk)
                    chunk.removeAll(keepingCapacity: true)
                    if body.count > maxBytes {
                        return .tooLarge
                    }
                }
            }
            body.append(contentsOf: chunk)
            guard body.count <= maxBytes else { return .tooLarge }
            return ManualDownload.isPdf(body) ? .pdf(body) : .notPdf
        } catch {
            if let refused = guardian.refused {
                return .redirectRefused(refused)
            }
            return .failed(error.localizedDescription)
        }
    }
}
