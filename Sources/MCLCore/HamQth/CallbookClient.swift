import Foundation

/// Source of callsign data (HamQTH, QRZ.com…) for looking up grid/zones/name from a spot — Java
/// `hamqth.CallbookClient`.
///
/// `lookup` blocks the calling thread for the duration of the HTTP (`HttpGetter` is synchronous) — call **outside**
/// the cooperative pool (own thread, like the Java call from IO). The Java contract "never throws"
/// holds except for one Java defect: a log with negative capacity throws `NoSuchElementException` already at
/// the first write (`HamQthLog`), here `JavaNoSuchElementError`.
public protocol CallbookClient: Sendable {
    /// Are the login credentials filled in?
    var configured: Bool { get }
    /// Callsign data, or `HamQthRecord.empty`.
    func lookup(_ call: String?) throws -> HamQthRecord
}

/// HTTP GET response: status code and the **raw** body (decoded by the client like Java
/// `BodyHandlers.ofString(UTF_8)` = `new String(bytes, UTF_8)` with bad bytes replaced).
public struct HttpGetResponse: Equatable, Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Any exception that Java `get` catches (`catch (Exception e)`): a network `IOException`,
/// `HttpTimeoutException`, but also `IllegalArgumentException` from `URI.create` for a URL with a disallowed character
/// (e.g. a session id with a space from the server). `message` = `getMessage()` literally, `nil` = Java `null`
/// (goes to the log as "null").
public struct HttpGetFailure: Error, Equatable, Sendable {
    public let javaClass: String
    public let message: String?

    public init(_ message: String?, javaClass: String = "java.io.IOException") {
        self.javaClass = javaClass
        self.message = message
    }
}

/// Callbook network layer (Java `HttpClient.send(GET)`) behind a protocol so that the client logic can be
/// tested with a replacement without a network. The production implementation `URLSessionHttpGetter` is responsible for the Java behaviour:
/// `URI.create` (a disallowed character → `HttpGetFailure` with the Java text), redirects NEVER (3xx is returned
/// as a response), connect timeout 8 s and request timeout 10 s (`connectTimeout`/`requestTimeout`
/// of the clients; the connect timeout only via the request timeout), no cookies and cache.
/// The call blocks — never from the cooperative pool.
public protocol HttpGetter: Sendable {
    func get(_ url: String) throws(HttpGetFailure) -> HttpGetResponse
}
