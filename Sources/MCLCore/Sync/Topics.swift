/// MQTT topic constants of the cluster sync (Java `sync.Topics`).
public enum Topics {

    public static let cmdInsert = "qso/cmd/insert"
    public static let cmdUpdate = "qso/cmd/update"
    public static let cmdDelete = "qso/cmd/delete"

    /// Shared DX spots between stations (no authority, not retained).
    public static let spots = "spot/new"

    /// Prefix of the station status (retained); the concrete topic is `station/status/<stationId>`.
    public static let statusPrefix = "station/status/"

    /// Messages between stations (chat, pass, call stacking) — QoS 1, not retained.
    public static let messages = "station/msg"

    /// Serial number requests (serial number server).
    public static let serialRequest = "serial/request"

    /// Prefix of serial server replies; the concrete topic is `serial/reply/<stationId>`.
    public static let serialReplyPrefix = "serial/reply/"

    /// Subscription to the states of all stations.
    public static let statusWildcard = "station/status/+"

    /// Prefix of the canonical state; the concrete topic is `qso/state/<uuid>`.
    public static let statePrefix = "qso/state/"

    /// Subscription to all states (retained replay = bootstrap).
    public static let stateWildcard = "qso/state/#"

    /// Canonical state topic of the given contact (Java `STATE_PREFIX + uuid`: `null` → `"qso/state/null"`).
    public static func state(_ uuid: String?) -> String {
        statePrefix + (uuid ?? "null")
    }

    /// Reply topic of the serial server for a station.
    public static func serialReply(_ stationId: String?) -> String {
        serialReplyPrefix + (stationId ?? "null")
    }

    /// Status topic of the given station.
    public static func status(_ stationId: String?) -> String {
        statusPrefix + (stationId ?? "null")
    }

    /// `uuid` from the topic `qso/state/<uuid>` (otherwise `nil`). Java `startsWith` by UTF-16 units.
    public static func uuidFromStateTopic(_ topic: String?) -> String? {
        guard let topic else { return nil }
        let units = Array(topic.utf16)
        let prefix = Array(statePrefix.utf16)
        guard units.count >= prefix.count, Array(units[0..<prefix.count]) == prefix else { return nil }
        return String(decoding: units[prefix.count...], as: UTF16.self)
    }
}
