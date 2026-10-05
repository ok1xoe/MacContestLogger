/// Network transport error of cluster sync (Java `cluster.SyncTransportException`, e.g. connecting/publishing
/// to the MQTT broker): `message` verbatim, `cause` = Java `getCause().toString()` (or `nil`).
public struct SyncTransportError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    public let cause: String?

    public init(_ message: String, cause: String? = nil) {
        self.message = message
        self.cause = cause
    }

    public var description: String { message }
}
