/// Callsign data from the callbook (Java `hamqth.HamQthRecord`) — what is useful for multiplier prediction.
/// An empty field = the service did not return it; Java `null` in the constructor becomes `""`.
public struct HamQthRecord: Equatable, Sendable {

    public static let empty = HamQthRecord(grid: "", name: "", cqZone: "", ituZone: "")

    public let grid: String
    public let name: String
    public let cqZone: String
    public let ituZone: String

    public init(grid: String?, name: String?, cqZone: String?, ituZone: String?) {
        self.grid = grid ?? ""
        self.name = name ?? ""
        self.cqZone = cqZone ?? ""
        self.ituZone = ituZone ?? ""
    }

    /// Java `isEmpty()`: all four fields `isBlank()` (Unicode whitespace, not `trim`).
    public var isEmpty: Bool {
        JavaText.isBlank(grid) && JavaText.isBlank(name) && JavaText.isBlank(cqZone) && JavaText.isBlank(ituZone)
    }
}
