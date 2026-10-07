import Foundation

/// The filters of the `log.query` and `log.count` requests (protocol 1), applied to the QSOs of one contest scope.
/// All filters are optional and combine with AND.
public struct PluginLogQuery: Equatable, Sendable {

    /// Which QSOs are searched.
    public enum Scope: String, Equatable, Sendable {
        /// The active contest's QSOs (without a contest: the free-logging QSOs).
        case active
        /// The free-logging QSOs (no contest).
        case none
        /// Every QSO of the database.
        case all
    }

    /// The largest page.
    public static let maxLimit = 10_000
    public static let defaultLimit = 500

    public var scope: Scope = .active
    /// ADIF band (`20m`).
    public var band: String?
    /// The mode (`CW`, `SSB`, …), compared without case.
    public var mode: String?
    /// The call starts with this (without case).
    public var callPrefix: String?
    /// The call contains this (without case).
    public var callContains: String?
    public var since: Date?
    public var until: Date?
    public var limit: Int = PluginLogQuery.defaultLimit
    public var offset: Int = 0
    /// Newest first.
    public var descending = false

    public init() {}

    public struct Invalid: Error, Equatable, Sendable {
        public let message: String
    }

    /// Reads the request's `params`: `contest` (`active`, `none`, `all`), `band`, `mode`, `call` (a prefix),
    /// `callContains`, `since`/`until` (ISO 8601, UTC), `limit`, `offset`, `order` (`asc`, `desc`).
    public static func parse(_ params: [String: PluginJSON]) throws(Invalid) -> PluginLogQuery {
        var query = PluginLogQuery()
        if let scope = params["contest"]?.stringValue {
            guard let parsed = Scope(rawValue: scope) else {
                throw Invalid(message: "contest must be active, none or all")
            }
            query.scope = parsed
        }
        query.band = params["band"]?.stringValue
        query.mode = params["mode"]?.stringValue
        query.callPrefix = params["call"]?.stringValue
        query.callContains = params["callContains"]?.stringValue
        query.since = try date(params["since"], "since")
        query.until = try date(params["until"], "until")
        if let limit = params["limit"] {
            guard let value = limit.intValue, value >= 0 else { throw Invalid(message: "limit must be a number ≥ 0") }
            query.limit = Int(min(value, Int64(maxLimit)))
        }
        if let offset = params["offset"] {
            guard let value = offset.intValue, value >= 0 else { throw Invalid(message: "offset must be a number ≥ 0") }
            query.offset = Int(min(value, Int64(Int32.max)))
        }
        if let order = params["order"]?.stringValue {
            guard order == "asc" || order == "desc" else { throw Invalid(message: "order must be asc or desc") }
            query.descending = order == "desc"
        }
        return query
    }

    private static func date(_ value: PluginJSON?, _ field: String) throws(Invalid) -> Date? {
        guard let value, value != .null else { return nil }
        guard let text = value.stringValue, let date = parseDate(text) else {
            throw Invalid(message: "\(field) must be an ISO 8601 time (2026-10-07T12:00:00Z)")
        }
        return date
    }

    static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    public func matches(_ qso: Qso) -> Bool {
        if let band, qso.band?.adif.lowercased() != band.lowercased() {
            return false
        }
        if let mode, qso.mode?.rawValue.uppercased() != mode.uppercased() {
            return false
        }
        let call: String = qso.call.uppercased()
        if let callPrefix, !call.hasPrefix(callPrefix.uppercased()) {
            return false
        }
        if let callContains, !callContains.isEmpty, !call.contains(callContains.uppercased()) {
            return false
        }
        if since != nil || until != nil {
            guard let time = qso.timestampUtc else { return false }
            if let since, time < since { return false }
            if let until, time > until { return false }
        }
        return true
    }

    /// The matching QSOs (oldest first unless `descending`), the page of `offset`/`limit`, and how many matched.
    public func apply(_ qsos: [Qso]) -> (page: [Qso], total: Int) {
        var matching: [Qso] = qsos.filter(matches)
        if descending {
            matching.reverse()
        }
        let start: Int = min(offset, matching.count)
        let end: Int = min(start + limit, matching.count)
        return (Array(matching[start..<end]), matching.count)
    }
}
