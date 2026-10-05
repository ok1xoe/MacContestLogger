/// Context for deriving default values of the sent exchange. Port of Java
/// `exchange/ExchangeContext.java` (`record`).
///
/// - `mode`: current mode (RST default 599/59); `nil` → `599`
/// - `nextSerial`: the next serial number to send (Java `int`)
/// - `station`: "my station" values for `FROM_STATION` fields, id → value. A Java `Map`
///   (`HashMap`/`Map.of()`): keys by UTF-16, a `nil` key and a `nil` value are possible.
///   Java `station == null` (an NPE for `FROM_STATION`) is not allowed by the type — a deliberate
///   divergence from Java v1.1.1.
/// - `roverQth`: my current county (`ROVER_QTH` field; rover / county line), otherwise `""`
public struct ExchangeContext: Sendable {
    public let mode: Mode?
    public let nextSerial: Int32
    public let station: JavaLinkedMap<String>
    public let roverQth: String?

    /// Java canonical constructor; without `roverQth` it is the Java three-parameter one (`""`).
    public init(mode: Mode?, nextSerial: Int32, station: JavaLinkedMap<String>, roverQth: String? = "") {
        self.mode = mode
        self.nextSerial = nextSerial
        self.station = station
        self.roverQth = roverQth
    }

    /// Java `ExchangeContext.of(mode, nextSerial)` — an empty station (`Map.of()`).
    public static func of(_ mode: Mode?, _ nextSerial: Int32) -> ExchangeContext {
        ExchangeContext(mode: mode, nextSerial: nextSerial, station: JavaLinkedMap())
    }
}
