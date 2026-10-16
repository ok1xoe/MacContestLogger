import Foundation

/// N1MM „Download latest PDF manual": the user guide attached to the project's newest published GitHub release
/// (built from `docs/` by `mcl-manual` in the release workflow) as a PDF or as one self-contained HTML file. Only on
/// the user's click; the address is fixed to the project's releases, redirects are followed only to GitHub's own
/// download hosts, the size is limited and the bytes must be of the requested format before anything is saved.
/// The guide exists in English and Czech; the application's language picks one (Czech for Czech, English otherwise),
/// and a release without the Czech files (older ones) gives the English guide.
public enum ManualDownload {

    /// The guide's languages.
    public enum Language: String, Sendable, Equatable, CaseIterable {
        case en
        case cs

        /// The guide for the application's language code: Czech for `cs`, English for any other.
        public static func forApp(_ code: String) -> Language {
            code.lowercased() == "cs" ? .cs : .en
        }
    }

    /// The manual's two formats.
    public enum Format: String, Sendable, Equatable, CaseIterable {
        case pdf
        case html

        /// The release asset's file name (the same in every release, so `latest/download/` finds it): the English
        /// guide keeps the original name (`MacContestLogger-manual.pdf`), the Czech one is `MacContestLogger-manual-cs.pdf`.
        public func assetName(_ language: Language) -> String {
            "MacContestLogger-manual" + (language == .en ? "" : "-" + language.rawValue) + "." + rawValue
        }

        /// The English guide's asset name.
        public var assetName: String {
            assetName(.en)
        }

        /// The newest published release's copy (drafts and pre-releases are left out by GitHub).
        public func latestUrl(_ language: Language) -> String {
            "https://github.com/ok1xoe/MacContestLogger/releases/latest/download/" + assetName(language)
        }

        /// The newest published release's English copy.
        public var latestUrl: String {
            latestUrl(.en)
        }

        /// The request's `Accept` header.
        var accept: String {
            switch self {
            case .pdf: return "application/pdf, application/octet-stream"
            case .html: return "text/html, application/octet-stream"
            }
        }

        /// Whether the bytes are a file of this format.
        public func matches(_ data: Data) -> Bool {
            switch self {
            case .pdf: return ManualDownload.isPdf(data)
            case .html: return ManualDownload.isHtml(data)
            }
        }
    }

    /// The PDF's release asset name.
    public static let assetName: String = Format.pdf.assetName
    /// The newest published release's PDF.
    public static let latestUrl: String = Format.pdf.latestUrl
    /// Where to look when the download is not possible (the online guide).
    public static let docsUrl = "https://github.com/ok1xoe/MacContestLogger/tree/main/docs"
    /// A larger answer is not the manual (the PDF is about 4 MB, the HTML with its embedded images about 6 MB).
    public static let maxBytes = 64 * 1_024 * 1_024
    /// Generous: the file is a few megabytes and the user waits for it on purpose.
    public static let timeoutSeconds: TimeInterval = 120

    /// What the download ended with.
    public enum Outcome: Equatable, Sendable {
        /// The manual in the requested format.
        case file(Data)
        /// The release has no manual yet (HTTP 404).
        case notPublished
        /// Another HTTP status.
        case httpStatus(Int)
        /// Larger than `maxBytes`.
        case tooLarge
        /// The bytes are not of the requested format.
        case wrongFormat
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

    /// An HTML document starts (after an optional byte order mark and white space) with `<!DOCTYPE html` or `<html`,
    /// in any case.
    public static func isHtml(_ data: Data) -> Bool {
        var bytes: Data.SubSequence = data.prefix(1_024)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = bytes.dropFirst(3)
        }
        bytes = bytes.drop { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
        let head: String = String(decoding: bytes.prefix(14), as: UTF8.self).lowercased()
        return head.hasPrefix("<!doctype html") || head.hasPrefix("<html")
    }

    /// The outcome of a finished answer.
    public static func evaluate(status: Int, body: Data, format: Format = .pdf) -> Outcome {
        switch status {
        case 200:
            guard body.count <= maxBytes else { return .tooLarge }
            return format.matches(body) ? .file(body) : .wrongFormat
        case 404:
            return .notPublished
        default:
            return .httpStatus(status)
        }
    }
}

/// Fetches the manual in a format; replaceable in tests (the app model gets it from its network ports).
public typealias ManualFetcher = @Sendable (_ url: String, _ format: ManualDownload.Format) async -> ManualDownload.Outcome

/// The production fetch over `URLSession`: no cookies or cache, redirects only where `allow` says, the body
/// collected by the session's delegate on a queue of its own (never the shared pool) and abandoned as soon as it
/// passes `maxBytes`.
public struct ManualDownloader: Sendable {

    let allow: @Sendable (URL) -> Bool
    let maxBytes: Int
    let requestTimeout: TimeInterval
    let timeout: TimeInterval

    public init(allow: @escaping @Sendable (URL) -> Bool = ManualDownload.isAllowed,
                maxBytes: Int = ManualDownload.maxBytes, requestTimeout: TimeInterval = 30,
                timeout: TimeInterval = ManualDownload.timeoutSeconds) {
        self.allow = allow
        self.maxBytes = maxBytes
        self.requestTimeout = requestTimeout
        self.timeout = timeout
    }

    /// The session's delegate: checks every redirect against the allow list, collects the body within the limit and
    /// reports the outcome once.
    final class Transfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let allow: @Sendable (URL) -> Bool
        let maxBytes: Int
        let format: ManualDownload.Format
        private let lock = NSLock()
        private var refused: String?
        private var status = 0
        private var body = Data()
        private var tooLarge = false
        private var finish: (@Sendable (ManualDownload.Outcome) -> Void)?

        init(allow: @escaping @Sendable (URL) -> Bool, maxBytes: Int, format: ManualDownload.Format,
             finish: @escaping @Sendable (ManualDownload.Outcome) -> Void) {
            self.allow = allow
            self.maxBytes = maxBytes
            self.format = format
            self.finish = finish
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            guard let url = request.url, allow(url) else {
                lock.withLock { refused = request.url?.host ?? request.url?.absoluteString ?? "?" }
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            let code: Int = (response as? HTTPURLResponse)?.statusCode ?? 0
            let large: Bool = response.expectedContentLength > Int64(maxBytes)
            lock.withLock {
                status = code
                tooLarge = large
            }
            // Only a 200 within the limit is read; anything else ends here with its status.
            completionHandler(code == 200 && !large ? .allow : .cancel)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            let over: Bool = lock.withLock {
                body.append(data)
                if body.count > maxBytes {
                    tooLarge = true
                    body = Data()
                    return true
                }
                return false
            }
            if over {
                dataTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let outcome: ManualDownload.Outcome = lock.withLock {
                if let refused {
                    return .redirectRefused(refused)
                }
                if tooLarge {
                    return .tooLarge
                }
                if status != 0 && status != 200 {
                    return ManualDownload.evaluate(status: status, body: Data(), format: format)
                }
                if let error {
                    return .failed(error.localizedDescription)
                }
                return ManualDownload.evaluate(status: status, body: body, format: format)
            }
            let done: (@Sendable (ManualDownload.Outcome) -> Void)? = lock.withLock {
                defer { finish = nil }
                return finish
            }
            done?(outcome)
            session.finishTasksAndInvalidate()
        }
    }

    public func fetch(_ address: String, format: ManualDownload.Format = .pdf) async -> ManualDownload.Outcome {
        guard let url = URL(string: address), allow(url) else { return .redirectRefused(address) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = timeout
        var request = URLRequest(url: url)
        request.setValue("MacContestLogger", forHTTPHeaderField: "User-Agent")
        request.setValue(format.accept, forHTTPHeaderField: "Accept")
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "mcl.manual-download"
        let allow = self.allow
        let maxBytes = self.maxBytes
        return await withCheckedContinuation { (continuation: CheckedContinuation<ManualDownload.Outcome, Never>) in
            let transfer = Transfer(allow: allow, maxBytes: maxBytes, format: format) { outcome in
                continuation.resume(returning: outcome)
            }
            let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: queue)
            session.dataTask(with: request).resume()
        }
    }
}
