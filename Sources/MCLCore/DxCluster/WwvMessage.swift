/// WWV message from the DX cluster (Java record `dxcluster.WwvMessage`) — solar and geomagnetic indices
/// for the fourth line of the Info window. Line shape:
/// `WWV de VE7CC <18Z> :   SFI=142, A=8, K=3, No Storms -> No Storms`.
public struct WwvMessage: Equatable, Sendable {
    /// Who sent the message to the network (uppercase).
    public let spotter: String
    /// UTC hour the measurement refers to.
    public let hourUtc: Int
    /// Solar flux index.
    public let sfi: Int
    /// A index.
    public let aIndex: Int
    /// K index.
    public let kIndex: Int
    /// Verbal description of the conditions (the rest of the line after the last `K=n`).
    public let conditions: String

    public init(spotter: String, hourUtc: Int, sfi: Int, aIndex: Int, kIndex: Int, conditions: String) {
        self.spotter = spotter
        self.hourUtc = hourUtc
        self.sfi = sfi
        self.aIndex = aIndex
        self.kIndex = kIndex
        self.conditions = conditions
    }

    private static let linePattern: JavaRegex = DxClusterRegex.compile(
        "(?i)^WWV\\s+de\\s+([A-Za-z0-9/#\\-]+)\\s*<\\s*(\\d{1,2})\\s*Z?\\s*>\\s*:\\s*(.*)$")
    private static let sfiPattern: JavaRegex = DxClusterRegex.compile("(?i)SFI\\s*=\\s*(-?\\d+)")
    private static let aPattern: JavaRegex = DxClusterRegex.compile("(?i)\\bA\\s*=\\s*(-?\\d+)")
    private static let kPattern: JavaRegex = DxClusterRegex.compile("(?i)\\bK\\s*=\\s*(-?\\d+)")
    private static let conditionsPrefix: JavaRegex =
        DxClusterRegex.compile("(?i)^.*\\bK\\s*=\\s*-?\\d+\\s*,?\\s*")

    /// Recognizes a WWV line; `nil` for everything else — spots, WCY messages and WWV lines without indices.
    ///
    /// Edges (rows `WWV|`): tolerant of spaces and letter case, `conditions` is
    /// the rest after the **last** `K=n` (greedy `^.*`), but `kIndex` is the **first** `K`.
    ///
    /// - Throws: `JavaNumberFormatError` like Java (`Integer.valueOf`) when an index overflows `int`
    ///   (`SFI=99999999999`) — preserved (in Java the exception kills the telnet
    ///   read loop). Indices are read in the order SFI, A, K, all three even if one is already missing.
    public static func parse(_ line: String?) throws(JavaNumberFormatError) -> WwvMessage? {
        guard let line else { return nil }
        guard let m = linePattern.wholeMatch(JavaText.trim(line)) else { return nil }
        let body = m.group(3) ?? ""
        let sfi: Int? = try firstInt(sfiPattern, body)
        let a: Int? = try firstInt(aPattern, body)
        let k: Int? = try firstInt(kPattern, body)
        guard let sfi, let a, let k else { return nil }
        // The pattern starts with `^` (without MULTILINE) and the body has no line terminator, so Java
        // `replaceAll` replaces at most one match.
        let conditions = JavaText.trim(conditionsPrefix.replaceFirst(in: body, with: ""))
        let hour = Int(try JavaInteger.valueOf(m.group(2) ?? ""))
        return WwvMessage(spotter: (m.group(1) ?? "").uppercased(), hourUtc: hour,
                          sfi: sfi, aIndex: a, kIndex: k, conditions: conditions)
    }

    private static func firstInt(_ pattern: JavaRegex, _ text: String) throws(JavaNumberFormatError) -> Int? {
        guard let match = pattern.firstMatch(in: text) else { return nil }
        return Int(try JavaInteger.valueOf(match.group(1) ?? ""))
    }
}
