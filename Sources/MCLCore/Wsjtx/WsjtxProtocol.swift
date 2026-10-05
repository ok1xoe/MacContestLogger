/// Constants of the WSJT-X UDP protocol (QDataStream, big-endian) — port of `wsjtx/WsjtxProtocol.java` (v1.1.1).
public enum WsjtxProtocol {

    /// `0xADBCCBDA` as a Java `int` (negative).
    public static let magic: Int32 = Int32(bitPattern: 0xADBC_CBDA)
    public static let schema: Int32 = 2
    public static let idOut: String = "MacContestLogger"

    // WSJT-X message types.
    public static let heartbeat: Int32 = 0
    public static let status: Int32 = 1
    public static let decode: Int32 = 2
    public static let clear: Int32 = 3
    public static let reply: Int32 = 4
    public static let qsoLogged: Int32 = 5
    public static let close: Int32 = 6
    public static let loggedAdif: Int32 = 12
}
