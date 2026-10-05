import Foundation

/// Synchronous HTTP(S) client over `URLSession` with the Java semantics of `java.net.http.HttpClient.send`
/// for callbooks (`URLSessionHttpGetter`), Club Log and the scoreboard. `JavaHttp1` remains only for
/// fldigi (http on localhost).
///
/// - **Address** is validated as `URI.create` + `HttpRequest.newBuilder` (`JavaHttpUri`): an error →
///   `JavaHttpError.illegalArgument` with the Java text (`Illegal character in query at index …`).
/// - **Redirects** `never` (Java default `Redirect.NEVER`: 3xx is returned as a response) or `normal`
///   (301/302/303/307/308, not from https to http, at most 4 redirects — the fifth 3xx response is returned, like
///   `jdk.httpclient.redirects.retrylimit` = 5; 301/302 from POST and 303 → GET without a body, 307/308 keeps POST).
/// - **No cookies and no cache** (`URLSessionConfiguration.ephemeral`, `httpCookieStorage = nil`, `urlCache = nil`);
///   the default Java `HttpClient` has neither a cookie handler nor a cache.
/// - **Request timeout** (`HttpRequest.timeout`) = a dedicated watchdog from start to the response headers (like Java
///   `ResponseTimerEvent`); on expiry the task is cancelled and `HttpTimeoutException: request timed out` is thrown, or if the
///   connection was not established, `HttpConnectTimeoutException: HTTP connect timed out` (by the task metrics, like Java
///   `connection().connected()`). `URLSession` has no separate **connect timeout** and does not report connection
///   progress (the connection state is known only from the metrics after the task ends), so `connectTimeout` is not enforced
///   separately: connecting is limited only by the request-timeout watchdog (callbooks 10 s instead of 8 s, Club Log and scoreboard
///   20 s instead of 10 s; the exception text is the Java one) — a divergence.
/// - **Blocks the calling thread** (semaphore/condition) — call only from your own `Thread`, never from the Swift shared pool
///   (`await` over a `Task` would block a pool thread); `URLSession` completion runs on the delegate queue (GCD).
public final class JavaHttpClient: Sendable {

    public enum Redirect: Sendable {
        case never
        case normal
    }

    /// Response: status code and raw body.
    public struct Response: Equatable, Sendable {
        public let status: Int
        public let body: Data
    }

    /// Java `HttpClient.connectTimeout` (s), `nil` = no limit. A configuration record only — see the type.
    public let connectTimeout: TimeInterval?
    public let redirect: Redirect
    private let session: URLSession

    /// - Parameter idleTimeout: `URLSession` inactivity (`timeoutIntervalForRequest`); Java does not limit inactivity
    ///   (body after the headers without a limit), here the `URLSession` default of 60 s.
    public init(connectTimeout: TimeInterval?, redirect: Redirect, idleTimeout: TimeInterval = 60) {
        self.connectTimeout = connectTimeout
        self.redirect = redirect
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = idleTimeout
        let queue = OperationQueue()
        queue.name = "JavaHttpClient.delegate"
        queue.maxConcurrentOperationCount = 1
        // Under load on the global GCD queues, task completion is delayed (measured in the full test suite) — a higher QoS
        // mitigates this; the timeout watchdog runs on the caller's thread and expires on time anyway (a deliberate divergence from Java v1.1.1).
        queue.qualityOfService = .userInitiated
        session = URLSession(configuration: configuration, delegate: nil, delegateQueue: queue)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    /// Java `HttpClient.send(request, …)`: returns status and body, or throws a Java exception. Blocks.
    ///
    /// - Parameters:
    ///   - url: the address literally (validated as `URI.create`).
    ///   - requestTimeout: Java `HttpRequest.timeout` (s), `nil` = no limit.
    public func send(method: String, url: String, headers: [(String, String)] = [], body: Data? = nil,
                     requestTimeout: TimeInterval?) throws(JavaHttpError) -> Response {
        // A blocking call from the main thread would freeze the UI up to the request timeout (only your own `Thread`).
        dispatchPrecondition(condition: .notOnQueue(.main))
        let uri: JavaHttpUri
        do {
            uri = try JavaHttpUri.parse(url)
        } catch {
            throw .illegalArgument(error)
        }
        guard let requestURL = uri.requestURL else {
            throw .io(JavaIOError("Neplatná URL: " + url))
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body
        let exchange = HttpExchange(redirect: redirect)
        let task = session.dataTask(with: request)
        task.delegate = exchange
        task.resume()
        if let requestTimeout {
            let deadline: DispatchTime = .now() + requestTimeout
            if !exchange.awaitHeaders(until: deadline) {
                task.cancel()
            }
        }
        let outcome = exchange.awaitCompletion()
        if let failure = outcome.failure {
            throw failure
        }
        if outcome.timedOut {
            if outcome.connected {
                throw .io(JavaIOError("request timed out", javaClass: "java.net.http.HttpTimeoutException"))
            }
            throw .io(JavaIOError("HTTP connect timed out", javaClass: "java.net.http.HttpConnectTimeoutException"))
        }
        if let error = outcome.error {
            throw .io(Self.javaError(error, connected: outcome.connected))
        }
        return Response(status: outcome.status, body: outcome.body)
    }

    /// `URLSession` error → Java exception. Measured cases (probe `HttpIoProbe`): refused connection →
    /// `ConnectException` with message `null`; expiry → the Java timeout texts. Others → `IOException`
    /// with the `URLError` description (the Java texts differ, they go only to the log / status — a divergence).
    static func javaError(_ error: any Error, connected: Bool) -> JavaIOError {
        guard let urlError = error as? URLError else {
            return JavaIOError(error.localizedDescription)
        }
        switch urlError.code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return JavaIOError(nil, javaClass: "java.net.ConnectException")
        case .timedOut:
            if connected {
                return JavaIOError("request timed out", javaClass: "java.net.http.HttpTimeoutException")
            }
            return JavaIOError("HTTP connect timed out", javaClass: "java.net.http.HttpConnectTimeoutException")
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired:
            return JavaIOError(urlError.localizedDescription, javaClass: "javax.net.ssl.SSLHandshakeException")
        default:
            return JavaIOError(urlError.localizedDescription)
        }
    }
}

/// `JavaHttpClient.send` error: Java `IllegalArgumentException` (bad address — for Club Log and the scoreboard
/// it propagates out) or `IOException` (network, timeout).
public enum JavaHttpError: Error, Equatable, Sendable {
    case illegalArgument(JavaIllegalArgumentError)
    case io(JavaIOError)

    /// Java exception class.
    public var javaClass: String {
        switch self {
        case .illegalArgument: return "java.lang.IllegalArgumentException"
        case .io(let error): return error.javaClass
        }
    }

    /// `getMessage()` literally (`nil` = Java `null`).
    public var message: String? {
        switch self {
        case .illegalArgument(let error): return error.message
        case .io(let error): return error.message
        }
    }
}

/// State of one exchange (the `URLSession` task delegate); the caller's thread waits on it.
///
/// Delegate methods with a completion block are in their `async` form: Swift imports them from the Objective-C protocol
/// automatically and they match the requirement regardless of whether the SDK marks the block `NS_SWIFT_SENDABLE` (macOS 15 SDK
/// and newer) — a variant with `completionHandler` and a different annotation would only "almost match" and silently never be called.
/// That they are called is guarded by tests: without `didReceive response` the status stays 0, without the redirect method NEVER would follow.
private final class HttpExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    struct Outcome {
        var status = 0
        var body = Data()
        var error: (any Error)?
        /// Java exception from redirect evaluation (`Invalid redirection`, bad `Location`) — overrides the others.
        var failure: JavaHttpError?
        var timedOut = false
        var connected = false
    }

    /// Java `jdk.httpclient.redirects.retrylimit`: a redirect is followed while `++n < 5`.
    private static let maxRedirects = 5
    private static let redirectCodes: Set<Int> = [301, 302, 303, 307, 308]
    /// Safeguard for waiting on metrics after the task ends (the order of metrics and completion is not contractual).
    private static let metricsGrace: TimeInterval = 2

    private let redirect: JavaHttpClient.Redirect
    private let condition = NSCondition()
    private var outcome = Outcome()
    private var gotHeaders = false
    private var done = false
    private var gotMetrics = false
    private var redirects = 0
    /// Redirect rejected by the Java policy (scheme, limit) — the 3xx is then returned as a response.
    private var declined = false

    init(redirect: JavaHttpClient.Redirect) {
        self.redirect = redirect
    }

    /// Waits for the headers (or the end) until `deadline` (monotonic clock like Java `nanoTime`); `false` = expired
    /// (`timedOut` is set).
    func awaitHeaders(until deadline: DispatchTime) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        while !gotHeaders && !done {
            let now = DispatchTime.now()
            if now >= deadline {
                break
            }
            let remaining = Double(deadline.uptimeNanoseconds - now.uptimeNanoseconds) / 1_000_000_000
            _ = condition.wait(until: Date(timeIntervalSinceNow: remaining))
        }
        if gotHeaders || done {
            return true
        }
        outcome.timedOut = true
        return false
    }

    /// Waits for the task to end; after the watchdog expires also for the metrics (connection state), at most `metricsGrace`.
    func awaitCompletion() -> Outcome {
        condition.lock()
        defer { condition.unlock() }
        while !done {
            condition.wait()
        }
        if outcome.timedOut && !gotMetrics {
            let deadline: DispatchTime = .now() + Self.metricsGrace
            while !gotMetrics && DispatchTime.now() < deadline {
                _ = condition.wait(until: Date(timeIntervalSinceNow: 0.05))
            }
        }
        return outcome
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        received(response as? HTTPURLResponse) ? .cancel : .allow
    }

    /// Final response headers; `true` = cancel (Java exception from the redirect).
    private func received(_ http: HTTPURLResponse?) -> Bool {
        let status = http?.statusCode ?? 0
        let failure = finalResponseFailure(http, status)
        condition.lock()
        outcome.status = status
        outcome.connected = true
        if outcome.failure == nil {
            outcome.failure = failure
        }
        let cancel = outcome.failure != nil
        gotHeaders = true
        condition.broadcast()
        condition.unlock()
        return cancel
    }

    /// Final 3xx response with NORMAL that the Java policy did not stop: Java would redirect it, or fail —
    /// without `Location` with `IOException: java.io.IOException: Invalid redirection`, with a bad `Location`
    /// `IllegalArgumentException` from `URI.create` (measured `SP.noLocation`, `SP.badLocation`).
    private func finalResponseFailure(_ response: HTTPURLResponse?, _ status: Int) -> JavaHttpError? {
        guard redirect == .normal, Self.redirectCodes.contains(status), let response else { return nil }
        condition.lock()
        let wasDeclined = declined
        condition.unlock()
        if wasDeclined {
            return nil
        }
        guard let location = response.value(forHTTPHeaderField: "Location") else {
            return .io(JavaIOError("java.io.IOException: Invalid redirection"))
        }
        do {
            try JavaHttpUri.checkReference(location)
        } catch {
            return .illegalArgument(error)
        }
        return nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        condition.lock()
        outcome.body.append(data)
        condition.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        follow(response, request, from: task.currentRequest?.url) ? request : nil
    }

    /// Java `RedirectFilter` with the `NORMAL` policy; `NEVER` follows nothing.
    private func follow(_ response: HTTPURLResponse, _ request: URLRequest, from url: URL?) -> Bool {
        guard redirect == .normal else { return false }
        guard Self.redirectCodes.contains(response.statusCode) else { return false }
        if let location = response.value(forHTTPHeaderField: "Location") {
            do {
                try JavaHttpUri.checkReference(location)
            } catch {
                condition.lock()
                outcome.failure = .illegalArgument(error)
                condition.unlock()
                return false
            }
        }
        let oldScheme = url?.scheme?.lowercased() ?? ""
        let newScheme = request.url?.scheme?.lowercased() ?? ""
        condition.lock()
        defer { condition.unlock() }
        // `canRedirect(redir) && ++numberOfRedirects < max_redirects` — the counter only for an allowed scheme.
        var allowed = newScheme == oldScheme || newScheme == "https"
        if allowed {
            redirects += 1
            allowed = redirects < Self.maxRedirects
        }
        if !allowed {
            declined = true
        }
        return allowed
    }

    /// State of the connection of the **last** transaction (Java `ResponseTimerEvent` asks about the connection of the current exchange).
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let last = metrics.transactionMetrics.last
        let connected = last.map { $0.isReusedConnection || $0.connectEndDate != nil } ?? false
        condition.lock()
        outcome.connected = outcome.connected || connected
        gotMetrics = true
        condition.broadcast()
        condition.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        condition.lock()
        outcome.error = error
        done = true
        condition.broadcast()
        condition.unlock()
    }
}
