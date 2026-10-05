import Foundation

/// Club Log Live Stream (Java `clublog.ClubLogClient`; N1MM / DXLog "Club Log real-time"): each
/// logged QSO is sent as one ADIF record to `realtime.php`. Needs an e-mail, an application password
/// (Club Log → Settings → App Passwords), the log callsign and an API key.
///
/// `upload`: POST, `Content-Type: application/x-www-form-urlencoded`, connect 10 s, request 20 s, redirects
/// NEVER (3xx → `RETRY`), `IOException` → `RETRY`, a bad URL → the Java `IllegalArgumentException` from `URI.create`
/// propagates (`JavaIllegalArgumentError`). Java's thread interruption (→ `RETRY`) does not exist in Swift. `upload` blocks — call
/// only from your own `Thread`, never from Swift's shared pool.
public struct ClubLogClient: Sendable {

    public static let defaultURL = "https://clublog.org/realtime.php"
    public static let contentType = "application/x-www-form-urlencoded"
    /// Java `HttpClient.connectTimeout` (s).
    public static let connectTimeout: TimeInterval = 10
    /// Java `HttpRequest.timeout` (s).
    public static let requestTimeout: TimeInterval = 20

    /// Result: success, or an error to retry / a permanent one (bad login, duplicate).
    public enum Outcome: String, Sendable {
        case OK, RETRY, REJECTED
    }

    public let url: String
    private let http: JavaHttpClient
    private let requestTimeout: TimeInterval

    /// Java `new ClubLogClient()`: `HttpClient.newBuilder().connectTimeout(10 s)` (NEVER), default URL.
    public init() {
        self.init(http: JavaHttpClient(connectTimeout: Self.connectTimeout, redirect: .never), url: Self.defaultURL)
    }

    /// Java package-private constructor `ClubLogClient(HttpClient, String)`; the request timeout is fixed in Java
    /// (20 s), settable here for tests.
    init(http: JavaHttpClient, url: String, requestTimeout: TimeInterval = ClubLogClient.requestTimeout) {
        self.http = http
        self.url = url
        self.requestTimeout = requestTimeout
    }

    /// Java `upload`: sends one ADIF record and classifies the response. Blocks.
    public func upload(email: String?, password: String?, callsign: String?, apiKey: String?,
                       adifRecord: String?) throws(JavaIllegalArgumentError) -> Outcome {
        let body = Self.formBody(email: email, password: password, callsign: callsign, apiKey: apiKey,
                                 adifRecord: adifRecord)
        let headers: [(String, String)] = [("Content-Type", Self.contentType)]
        do {
            let response = try http.send(method: "POST", url: url, headers: headers, body: Data(body.utf8),
                                         requestTimeout: requestTimeout)
            return Self.classify(response.status)
        } catch {
            switch error {
            case .illegalArgument(let illegal):
                throw illegal
            case .io:
                return .RETRY
            }
        }
    }

    /// POST body: fields in the order `email, password, callsign, adif, api` (a Java `LinkedHashMap`),
    /// `key=value` joined by `&`, value via `JavaUrlEncoder` (form encoding UTF-8), `nil` → `""`.
    public static func formBody(email: String?, password: String?, callsign: String?, apiKey: String?,
                                adifRecord: String?) -> String {
        let fields: [(String, String?)] = [
            ("email", email), ("password", password), ("callsign", callsign), ("adif", adifRecord),
            ("api", apiKey),
        ]
        var body = ""
        for (index, field) in fields.enumerated() {
            if index > 0 {
                body += "&"
            }
            body += field.0 + "="
            body += JavaUrlEncoder.encode(field.1 ?? "")
        }
        return body
    }

    /// 200 → `OK`; 400/403 = data / login error (do not retry) → `REJECTED`; others → `RETRY`.
    public static func classify(_ status: Int) -> Outcome {
        if status == 200 {
            return .OK
        }
        return status == 400 || status == 403 ? .REJECTED : .RETRY
    }
}
