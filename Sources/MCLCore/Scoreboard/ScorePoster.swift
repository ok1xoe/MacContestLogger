import Foundation

/// Sending the XML score to a scoreboard (Java `scoreboard.ScorePoster`): HTTP POST of the form `xml=<document>`
/// (as contestonlinescore.com accepts it); the URL is configurable.
///
/// Java client: `connectTimeout(10 s)`, `followRedirects(NORMAL)`, `HttpRequest.timeout(20 s)`,
/// `Content-Type: application/x-www-form-urlencoded`, the body is discarded (only the status is returned). Errors as in Java:
/// a bad URL → `JavaHttpError.illegalArgument` (the Java `IllegalArgumentException` from `URI.create` propagates out —
/// the caller catches it with `runCatching`), network → `JavaHttpError.io`. Java's thread interruption
/// (`IOException("Odeslání skóre přerušeno")`) does not exist in Swift — the thread cannot be interrupted, the request completes or times out.
///
/// `post` blocks — call it only from your own `Thread`, never from Swift's shared pool.
public struct ScorePoster: Sendable {

    public static let defaultURL = "https://contestonlinescore.com/post/"
    /// Java `HttpClient.connectTimeout` (s).
    public static let connectTimeout: TimeInterval = 10
    /// Java `HttpRequest.timeout` (s).
    public static let requestTimeout: TimeInterval = 20

    private let http: JavaHttpClient
    private let requestTimeout: TimeInterval

    /// Java `new ScorePoster()`.
    public init() {
        self.init(http: JavaHttpClient(connectTimeout: Self.connectTimeout, redirect: .normal),
                  requestTimeout: Self.requestTimeout)
    }

    /// Java package-private constructor `ScorePoster(HttpClient)` (tests); the request timeout is fixed in Java,
    /// settable here for tests.
    init(http: JavaHttpClient, requestTimeout: TimeInterval = ScorePoster.requestTimeout) {
        self.http = http
        self.requestTimeout = requestTimeout
    }

    /// - Returns: HTTP status.
    public func post(_ url: String, xml: String) throws(JavaHttpError) -> Int {
        let body = "xml=" + JavaUrlEncoder.encode(xml)
        let headers: [(String, String)] = [("Content-Type", "application/x-www-form-urlencoded")]
        return try http.send(method: "POST", url: url, headers: headers, body: Data(body.utf8),
                             requestTimeout: requestTimeout).status
    }
}
