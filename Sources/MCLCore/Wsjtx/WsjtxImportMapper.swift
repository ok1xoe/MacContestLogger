/// Conversion of a received WSJT-X "Logged ADIF" to a `Qso` (basic fields via `AdifReader`) + a raw ADIF
/// field map for best-effort exchange mapping — port of `wsjtx/WsjtxImportMapper.java` (v1.1.1).
public enum WsjtxImportMapper {

    public struct Imported: Equatable, Sendable {
        public let qso: Qso
        public let adifFields: [String: String]

        public init(qso: Qso, adifFields: [String: String]) {
            self.qso = qso
            self.adifFields = adifFields
        }
    }

    /// Returns the first record with a filled-in callsign, or `nil`.
    ///
    /// **Java flaw carried over literally**: the QSO is always `qsos.get(0)`, but the map is from the `i`-th
    /// record. `AdifReader.read` takes the same records as this loop, so the pairs do not diverge;
    /// if `read` returned nothing, it throws like Java `IndexOutOfBoundsException` (`ArrayList.get`).
    /// ADIF parsing errors pass through as `JavaIndexOutOfBoundsError` (`AdifReader`).
    /// Java `ArrayList.get(0)` on an empty list (measured on JDK 21). Unreachable through `map` — `read` keeps
    /// exactly the records this loop accepts — but kept like Java.
    static let emptyQsoList = JavaIndexOutOfBoundsError(message: "Index 0 out of bounds for length 0",
                                                        javaClass: "java.lang.IndexOutOfBoundsException")

    public static func map(_ adif: String) throws(JavaIndexOutOfBoundsError) -> Imported? {
        let reader = AdifReader()
        let qsos: [Qso] = try reader.read(adif)
        let records: [[String: String]] = try reader.readRecords(adif)
        for record in records {
            if let call = record["call"], !JavaText.isBlank(call) {
                guard let first = qsos.first else {
                    throw emptyQsoList
                }
                return Imported(qso: first, adifFields: record)
            }
        }
        return nil
    }
}
