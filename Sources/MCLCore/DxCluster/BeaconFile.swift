/// Beacon file for the `BEACONS` command (N1MM+) — Java `dxcluster.BeaconFile`. Beacons stay
/// in the bandmap much longer than ordinary spots, as a reminder to listen for them from time to time.
///
/// ```
/// # Hours to stay in bandmap (mostly > 24 or > 48)
/// 60
/// # call beacon;frequency;locator;comment
/// OZ7IGY/B;144471,1;JO55WM;
/// GB3VHF/B;144430.4;JO01DH;QRG with a .
/// ```
public enum BeaconFile {

    /// Spotter under which the beacons are shown.
    public static let spotter = "BEACONS"

    /// - `hours`: how long they stay in the bandmap
    /// - `beacons`: beacons as spots
    /// - `skipped`: lines that could not be read (to be reported)
    public struct Beacons: Equatable, Sendable {
        public let hours: Int
        public let beacons: [DxSpot]
        public let skipped: [String]

        public init(hours: Int, beacons: [DxSpot], skipped: [String]) {
            self.hours = hours
            self.beacons = beacons
            self.skipped = skipped
        }
    }

    private static let lineBreak: JavaRegex = DxClusterRegex.compile("\\r?\\n")

    /// Java edge cases (`misc-probe.txt` rows `BEACON*`): lines via `split("\\r?\\n")`,
    /// Java `strip()` (Unicode), `#` = comment; the first non-comment line is the hours (`Integer.parseInt`), otherwise
    /// **48 and the same line is processed as a beacon** (`99999999999` → skipped). Fields `split(";", -1)`;
    /// frequency `new BigDecimal(f[1].trim().replace(',', '.')).movePointRight(3).longValueExact()` —
    /// exact (`JavaBigDecimal`): accepts `1e3`, `-5`, `+5`, `.5`, `5.`, fractional Hz (`144471.0001`) and anything outside
    /// `long` is skipped. Callsign `trim()` + `toUpperCase(ROOT)`; `hours = max(hours, 0)`.
    public static func parse(_ content: String?) -> Beacons {
        var hours = -1
        var beacons: [DxSpot] = []
        var skipped: [String] = []
        guard let content else {
            return Beacons(hours: 0, beacons: beacons, skipped: skipped)
        }
        for raw in lineBreak.split(content, limit: 0) {
            let line = JavaText.strip(raw)
            if line.isEmpty || DxClusterRegex.startsWith(line, "#") {
                continue
            }
            if hours < 0 {
                if let parsed = JavaInteger.parseInt(line) {
                    hours = Int(parsed)
                    continue
                }
                hours = 48 // the hours line is missing — a sensible default
            }
            let fields = splitAll(line)
            if fields.count < 2 || JavaText.isBlank(fields[0]) {
                skipped.append(line)
                continue
            }
            let number = JavaText.replace(JavaText.trim(fields[1]), ",", ".")
            guard let hz = JavaBigDecimal(number)?.movePointRight(3)?.longValueExact() else {
                skipped.append(line)
                continue
            }
            let locator = fields.count > 2 ? JavaText.trim(fields[2]) : ""
            let comment = fields.count > 3 ? JavaText.trim(fields[3]) : ""
            let text = JavaText.trim(locator + " " + comment)
            let call = JavaText.trim(fields[0]).uppercased()
            beacons.append(DxSpot(spotter: spotter, freqHz: Int(hz), dxCall: call, comment: text))
        }
        return Beacons(hours: max(hours, 0), beacons: beacons, skipped: skipped)
    }

    /// Java `line.split(";", -1)`: by UTF-16 units, trailing empty parts **are kept**.
    private static func splitAll(_ line: String) -> [String] {
        var parts: [String] = []
        var current: [UInt16] = []
        for unit in line.utf16 {
            if unit == 0x3B {
                parts.append(String(decoding: current, as: UTF16.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(unit)
            }
        }
        parts.append(String(decoding: current, as: UTF16.self))
        return parts
    }
}
