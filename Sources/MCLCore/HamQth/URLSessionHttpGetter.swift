import Foundation

/// Production callbook `HttpGetter` over `JavaHttpClient` (`URLSession`) — Java `HamQthClient.get` /
/// `QrzClient.get`: `HttpClient.newBuilder().connectTimeout(8 s)` (redirects NEVER, no cookies and cache),
/// `HttpRequest.timeout(10 s)`, `GET`. Every Java exception (`catch (Exception e)` — `IOException`, timeouts
/// and `IllegalArgumentException` from `URI.create`, e.g. a session id with a space) → `HttpGetFailure` with the Java class
/// and `getMessage()`.
///
/// `get` blocks the calling thread — call only from your own `Thread`, never from Swift's shared pool.
public struct URLSessionHttpGetter: HttpGetter {

    private let client: JavaHttpClient
    private let requestTimeout: TimeInterval

    /// Default timeouts = Java `HamQthClient`/`QrzClient` (connect 8 s, request 10 s).
    public init(connectTimeout: TimeInterval = HamQthClient.connectTimeout,
                requestTimeout: TimeInterval = HamQthClient.requestTimeout) {
        client = JavaHttpClient(connectTimeout: connectTimeout, redirect: .never)
        self.requestTimeout = requestTimeout
    }

    public func get(_ url: String) throws(HttpGetFailure) -> HttpGetResponse {
        do {
            let response = try client.send(method: "GET", url: url, requestTimeout: requestTimeout)
            return HttpGetResponse(status: response.status, body: response.body)
        } catch {
            throw HttpGetFailure(error.message, javaClass: error.javaClass)
        }
    }
}
