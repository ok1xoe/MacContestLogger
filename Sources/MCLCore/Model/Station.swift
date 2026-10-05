/// Data about the own station. Used in the ADIF/Cabrillo header and for pre-filling
/// the sent exchange.
public struct Station: Codable, Equatable, Sendable {
    /// Station callsign (e.g. OK1XOE).
    public var call: String
    /// Operator callsign; in multi-op it may differ from `call`.
    public var `operator`: String
    /// Maidenhead locator (e.g. JO70).
    public var gridSquare: String
    /// Operator name.
    public var name: String

    public init(call: String = "", operator op: String = "", gridSquare: String = "", name: String = "") {
        self.call = call
        self.operator = op
        self.gridSquare = gridSquare
        self.name = name
    }

    public static let empty = Station()
}
