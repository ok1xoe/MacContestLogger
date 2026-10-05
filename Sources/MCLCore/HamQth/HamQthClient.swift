import Foundation
import os

/// HamQTH XML API client (Java `hamqth.HamQthClient`) — grid, name and CQ/ITU zone from a callsign.
///
/// Holds the login session (valid ~1 h; Java `volatile` field → lock). The network is behind `HttpGetter`.
/// The course of `lookup` as in Java:
/// 1. without credentials, with a `nil` or `isBlank` callsign → `empty` without a network and without a log;
/// 2. callsign `trim()`; log "Dohledávám údaje pro <CALLSIGN>";
/// 3. attempt: session (stored id, otherwise login `?u=<enc>&p=<enc>`, the id is stored **only** if the
///    response contains it), then `?id=<id>&callsign=<enc>&prg=MacContestLogger`; `<error>` in the response
///    (incl. "Session does not exist"), status ≠ 200 or a network error = no result;
/// 4. no result → log "Bez výsledku, obnovuji session a zkouším znovu", the session is dropped
///    and the attempt is repeated **once** (so also a new login);
/// 5. log of the result.
///
/// The session id is put into the URL **unencoded** (as it came from the server); callsign and credentials via
/// `JavaUrlEncoder`. Every GET is logged (password masked), the response also with status ≠ 200.
public final class HamQthClient: CallbookClient {

    static let base = "https://www.hamqth.com/xml.php"
    static let program = "MacContestLogger"
    /// Java `HttpClient.connectTimeout` (s) — for the `HttpGetter` implementation.
    public static let connectTimeout: TimeInterval = 8
    /// Java `HttpRequest.timeout` (s) — for the `HttpGetter` implementation.
    public static let requestTimeout: TimeInterval = 10

    private static let sessionIdPattern: JavaRegex = CallbookXml.tag("session_id")
    private static let errorPattern: JavaRegex = CallbookXml.tag("error")
    private static let gridPattern: JavaRegex = CallbookXml.tag("grid")
    private static let nickPattern: JavaRegex = CallbookXml.tag("nick")
    private static let adrNamePattern: JavaRegex = CallbookXml.tag("adr_name")
    private static let cqPattern: JavaRegex = CallbookXml.tag("cq")
    private static let ituPattern: JavaRegex = CallbookXml.tag("itu")

    private let username: String
    private let password: String
    private let http: any HttpGetter
    private let log: HamQthLog?
    private let sessionId = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// - Parameters:
    ///   - username: `nil` → `""`, otherwise `trim()`
    ///   - password: `nil` → `""` (not trimmed)
    public init(username: String?, password: String?, log: HamQthLog? = nil, http: any HttpGetter) {
        self.username = username.map { JavaText.trim($0) } ?? ""
        self.password = password ?? ""
        self.log = log
        self.http = http
    }

    public var configured: Bool {
        !username.isEmpty && !password.isEmpty
    }

    /// Grid of a callsign (Java `lookupGrid`): `nil` if the grid is `isBlank`.
    public func lookupGrid(_ call: String?) throws -> String? {
        let record = try lookup(call)
        return JavaText.isBlank(record.grid) ? nil : record.grid
    }

    public func lookup(_ call: String?) throws -> HamQthRecord {
        guard configured, let call, !JavaText.isBlank(call) else {
            return .empty
        }
        let c = JavaText.trim(call)
        let upper = c.uppercased()
        try log?.info("Dohledávám údaje pro " + upper)
        var found = try lookupOnce(c)
        if found == nil {
            try log?.info("Bez výsledku, obnovuji session a zkouším znovu")
            sessionId.withLock { $0 = nil }
            found = try lookupOnce(c)
        }
        let record = found ?? .empty
        if let log {
            if record.isEmpty {
                try log.info("Údaje pro " + upper + " nenalezeny")
            } else {
                var text = upper + ": grid=" + record.grid
                text += " cq=" + record.cqZone
                text += " itu=" + record.ituZone
                text += " jméno=" + record.name
                try log.info(text)
            }
        }
        return record
    }

    private func lookupOnce(_ call: String) throws -> HamQthRecord? {
        guard let session = try session() else { return nil }
        var url = HamQthClient.base + "?id=" + session
        url += "&callsign=" + JavaUrlEncoder.encode(call)
        url += "&prg=" + HamQthClient.program
        guard let body = try get(url) else { return nil }
        if HamQthClient.parseError(body) != nil {
            return nil // incl. "Session does not exist" → the caller renews
        }
        return HamQthClient.parseRecord(body)
    }

    private func session() throws -> String? {
        if let stored = sessionId.withLock({ $0 }) {
            return stored
        }
        var url = HamQthClient.base + "?u=" + JavaUrlEncoder.encode(username)
        url += "&p=" + JavaUrlEncoder.encode(password)
        guard let body = try get(url) else { return nil }
        guard let id = HamQthClient.parseSessionId(body) else { return nil }
        sessionId.withLock { $0 = id }
        return id
    }

    /// Java `get(url)`: request log, a 200 response → body, otherwise `nil`; an error → log and `nil`.
    private func get(_ url: String) throws -> String? {
        try log?.request(url)
        let response: HttpGetResponse
        do {
            response = try http.get(url)
        } catch {
            try log?.info("Chyba requestu: " + (error.message ?? "null"))
            return nil // silent fallback (offline, timeout…)
        }
        let body = JavaUtf8.decode(response.body)
        try log?.response(response.status, body)
        return response.status == 200 ? body : nil
    }

    // MARK: - parsers (Java package-private static methods)

    /// Name: `<nick>`, otherwise `<adr_name>`, otherwise `""`.
    static func parseRecord(_ xml: String?) -> HamQthRecord {
        let name = CallbookXml.firstGroup(nickPattern, xml) ?? CallbookXml.firstGroup(adrNamePattern, xml)
        return HamQthRecord(grid: CallbookXml.firstGroup(gridPattern, xml), name: name,
                            cqZone: CallbookXml.firstGroup(cqPattern, xml),
                            ituZone: CallbookXml.firstGroup(ituPattern, xml))
    }

    static func parseSessionId(_ xml: String?) -> String? {
        CallbookXml.firstGroup(sessionIdPattern, xml)
    }

    static func parseError(_ xml: String?) -> String? {
        CallbookXml.firstGroup(errorPattern, xml)
    }

    static func parseGrid(_ xml: String?) -> String? {
        CallbookXml.firstGroup(gridPattern, xml)
    }
}
