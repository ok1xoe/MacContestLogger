import Foundation
import os

/// QRZ.com XML API client (Java `hamqth.QrzClient`, analogous to `HamQthClient`) — grid, zones and name.
///
/// Differences from HamQTH (as in Java):
/// - URL parameters separated by `;` (`?username=…;password=…;agent=MacContestLogger`, `?s=<key>;callsign=…`);
/// - `<Error>` in the query response: if it contains (case-insensitive, Java
///   `toLowerCase().contains`) "session" → no result and **once** again with a new session, otherwise
///   (`Not found: …`) `empty` **without** retry;
/// - nothing extra is printed on retry; the log reports "QRZ: …", the result without a name;
/// - in the request log `;password=` is masked (`(?i)(;password=)[^;&]*`) and then also by the `HamQthLog` mask
///   (`[?&]p=`, as Java — `request` always masks).
public final class QrzClient: CallbookClient {

    static let base = "https://xmldata.qrz.com/xml/current/"
    static let agent = "MacContestLogger"
    /// Java `HttpClient.connectTimeout` (s) — for the `HttpGetter` implementation.
    public static let connectTimeout: TimeInterval = 8
    /// Java `HttpRequest.timeout` (s) — for the `HttpGetter` implementation.
    public static let requestTimeout: TimeInterval = 10

    private static let keyPattern: JavaRegex = CallbookXml.tag("Key")
    private static let errorPattern: JavaRegex = CallbookXml.tag("Error")
    private static let gridPattern: JavaRegex = CallbookXml.tag("grid")
    private static let cqPattern: JavaRegex = CallbookXml.tag("cqzone")
    private static let ituPattern: JavaRegex = CallbookXml.tag("ituzone")
    private static let fnamePattern: JavaRegex = CallbookXml.tag("fname")
    private static let passwordParam: JavaRegex = CallbookXml.compile("(?i)(;password=)[^;&]*")

    private let username: String
    private let password: String
    private let http: any HttpGetter
    private let log: HamQthLog?
    private let sessionKey = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// - Parameters:
    ///   - username: `nil` → `""`, otherwise `trim()`
    ///   - password: `nil` → `""` (not trimmed)
    public init(username: String?, password: String?, log: HamQthLog?, http: any HttpGetter) {
        self.username = username.map { JavaText.trim($0) } ?? ""
        self.password = password ?? ""
        self.log = log
        self.http = http
    }

    public var configured: Bool {
        !username.isEmpty && !password.isEmpty
    }

    public func lookup(_ call: String?) throws -> HamQthRecord {
        guard configured, let call, !JavaText.isBlank(call) else {
            return .empty
        }
        let c = JavaText.trim(call)
        let upper = c.uppercased()
        try log?.info("QRZ: dohledávám údaje pro " + upper)
        var found = try lookupOnce(c)
        if found == nil {
            sessionKey.withLock { $0 = nil }
            found = try lookupOnce(c)
        }
        let record = found ?? .empty
        if let log {
            if record.isEmpty {
                try log.info("QRZ: údaje pro " + upper + " nenalezeny")
            } else {
                var text = "QRZ " + upper
                text += ": grid=" + record.grid
                text += " cq=" + record.cqZone
                text += " itu=" + record.ituZone
                try log.info(text)
            }
        }
        return record
    }

    private func lookupOnce(_ call: String) throws -> HamQthRecord? {
        guard let key = try session() else { return nil }
        var url = QrzClient.base + "?s=" + key
        url += ";callsign=" + JavaUrlEncoder.encode(call)
        guard let body = try get(url) else { return nil }
        if let error = QrzClient.parseError(body) {
            // "Session Timeout" → renew; "Not found" → empty (but a valid session).
            let lower: [UInt16] = Array(JavaText.toLowerCase(error).utf16)
            return JavaText.indexOf(lower, Array("session".utf16)) >= 0 ? nil : .empty
        }
        return QrzClient.parseRecord(body)
    }

    private func session() throws -> String? {
        if let stored = sessionKey.withLock({ $0 }) {
            return stored
        }
        var url = QrzClient.base + "?username=" + JavaUrlEncoder.encode(username)
        url += ";password=" + JavaUrlEncoder.encode(password)
        url += ";agent=" + QrzClient.agent
        guard let body = try get(url) else { return nil }
        guard let key = QrzClient.parseKey(body) else { return nil }
        sessionKey.withLock { $0 = key }
        return key
    }

    private func get(_ url: String) throws -> String? {
        try log?.request(CallbookXml.maskGroup1(QrzClient.passwordParam, url))
        let response: HttpGetResponse
        do {
            response = try http.get(url)
        } catch {
            try log?.info("QRZ: chyba requestu: " + (error.message ?? "null"))
            return nil
        }
        let body = JavaUtf8.decode(response.body)
        try log?.response(response.status, body)
        return response.status == 200 ? body : nil
    }

    // MARK: - parsers (Java package-private static methods)

    static func parseKey(_ xml: String?) -> String? {
        CallbookXml.firstGroup(keyPattern, xml)
    }

    static func parseError(_ xml: String?) -> String? {
        CallbookXml.firstGroup(errorPattern, xml)
    }

    /// Name = `<fname>` (first name), the surname `<name>` is not read.
    static func parseRecord(_ xml: String?) -> HamQthRecord {
        HamQthRecord(grid: CallbookXml.firstGroup(gridPattern, xml),
                     name: CallbookXml.firstGroup(fnamePattern, xml),
                     cqZone: CallbookXml.firstGroup(cqPattern, xml),
                     ituZone: CallbookXml.firstGroup(ituPattern, xml))
    }
}
