/// Sends data to UDP targets. Port of Java `broadcast/Broadcaster`: a failure must not propagate
/// (implementations only log), so the methods do not throw.
///
/// `Sendable`: one broadcaster is shared by the radio, score and contact threads (`BroadcastService`) and `WsjtxSender`;
/// implementations handle concurrency themselves (lock).
public protocol Broadcaster: AnyObject, Sendable {
    /// Sends text (N1MM XML) as UTF-8 bytes.
    func send(_ xml: String, _ targets: [Target])

    /// Sends raw bytes (binary protocols, e.g. WSJT-X).
    func send(_ data: [UInt8], _ targets: [Target])

    func close()
}
