import Foundation

/// Running-score XML for online scoreboards (N1MM / DXLog "Score reporting", format
/// `<dynamicresults>` used by contestonlinescore.com and the other online scoreboards). Port of Java
/// `scoreboard/ScoreXml`: header `<?xml version="1.0"?>`, indentation of 2/4 spaces, `\n` line endings;
/// `esc` **does not replace the apostrophe** (unlike `BroadcastXml.esc`).
public enum ScoreXml {

    /// Station and category data (keys `POWER`, `ASSISTED`, `TRANSMITTER`, `OPERATOR`, `BAND`,
    /// `MODE`, `OVERLAY`; missing → empty attribute).
    public struct Station: Equatable, Sendable {
        public var call: String?
        public var ops: String?
        public var club: String?
        public var cqZone: String?
        public var ituZone: String?
        public var grid: String?
        public var category: [String: String]?

        public init(call: String?, ops: String?, club: String?, cqZone: String?, ituZone: String?, grid: String?,
                    category: [String: String]?) {
            self.call = call
            self.ops = ops
            self.club = club
            self.cqZone = cqZone
            self.ituZone = ituZone
            self.grid = grid
            self.category = category
        }
    }

    public static func build(contestName: String?, station st: Station, score: ScoreState,
                             breakdown: ScoreBreakdown?, withBreakdown: Bool, version: String?, now: Date) -> String {
        var x = "<?xml version=\"1.0\"?>\n<dynamicresults>\n"
        tag(&x, "contest", contestName)
        tag(&x, "call", st.call)
        tag(&x, "ops", st.ops)
        x += classLine(st.category ?? [:])
        tag(&x, "club", st.club)
        tag(&x, "soft", "MacContestLogger")
        tag(&x, "version", version)
        x += "  <qth>"
        x += "<cqzone>" + esc(st.cqZone) + "</cqzone>"
        x += "<iaruzone>" + esc(st.ituZone) + "</iaruzone>"
        x += "<grid6>" + esc(st.grid) + "</grid6>"
        x += "</qth>\n"
        x += "  <breakdown>\n"
        x += line("qso", "total", "ALL", String(score.qsoCount))
        x += line("point", "total", "ALL", String(score.qsoPoints))
        x += line("mult", "total", "ALL", String(score.multTotal))
        if withBreakdown, let breakdown {
            for b in breakdown.bands(nil) {
                let band = JavaText.replace(JavaText.replace(b, "m", ""), "c", "")
                for m in breakdown.modes {
                    let cell = breakdown.cell(b, m)
                    if cell.qsos == 0 { continue }
                    x += line("qso", band, m, String(cell.qsos))
                    x += line("point", band, m, String(cell.points))
                    x += line("mult", band, m, String(cell.multTotal))
                }
            }
        }
        x += "  </breakdown>\n"
        tag(&x, "score", String(score.total))
        tag(&x, "timestamp", BroadcastXml.formatUtc(now))
        x += "</dynamicresults>\n"
        return x
    }

    private static let classKeys: [(attribute: String, key: String)] = [
        ("power", "POWER"), ("assisted", "ASSISTED"), ("transmitter", "TRANSMITTER"), ("ops", "OPERATOR"),
        ("bands", "BAND"), ("mode", "MODE"), ("overlay", "OVERLAY"),
    ]

    private static func classLine(_ category: [String: String]) -> String {
        var s = "  <class"
        for (attribute, key) in classKeys {
            let escaped: String = esc(category[key] ?? "")
            s += " \(attribute)=\"\(escaped)\""
        }
        return s + "/>\n"
    }

    /// Breakdown row; band and mode are (as in Java) not escaped.
    private static func line(_ name: String, _ band: String, _ mode: String, _ value: String) -> String {
        var s = "    <" + name + " band=\"" + band
        s += "\" mode=\"" + mode + "\">" + value
        return s + "</" + name + ">\n"
    }

    private static func tag(_ x: inout String, _ name: String, _ value: String?) {
        x += "  <" + name + ">" + esc(value)
        x += "</" + name + ">\n"
    }

    /// Java `ScoreXml.esc`: `& < > "` (not the apostrophe); `null` → `""`.
    static func esc(_ s: String?) -> String {
        guard let s else { return "" }
        var b = ""
        b.reserveCapacity(s.utf8.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": b += "&amp;"
            case "<": b += "&lt;"
            case ">": b += "&gt;"
            case "\"": b += "&quot;"
            default: b.unicodeScalars.append(scalar)
            }
        }
        return b
    }
}
