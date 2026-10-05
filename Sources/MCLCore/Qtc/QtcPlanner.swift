import Foundation

/// QTC planner (WAE) — port of `qtc/QtcPlanner.java` (Java v1.1.1): which QSO can be reported to which station,
/// how many QTCs I may still exchange with it, parsing of received lines and text for CW and Cabrillo. `cabrilloLine`
/// serves the Cabrillo export.
///
/// Measured by the maintainer-only probe: `\d`/`\s` are ASCII (Arabic digits,
/// NBSP, U+2028 do not pass), `trim` + `toUpperCase(ROOT)` beyond ASCII (`ß` → `SS`, `ı` → `I`, `ﬀ` → `FF`),
/// `equalsIgnoreCase` by UTF-16 units (`ß` = `ẞ`, `İ` = `i` = `ı`, but `straße` ≠ `STRASSE`).
public enum QtcPlanner {

    /// Received / written QTC: time, callsign, number (Java `record Line`).
    public struct Line: Equatable, Sendable, CustomStringConvertible {
        public var time: String
        public var call: String
        public var serial: Int

        public init(time: String, call: String, serial: Int) {
            self.time = time
            self.call = call
            self.serial = serial
        }

        /// Java `Record.toString()`: `Line[time=1202, call=G3ABC, serial=3]`.
        public var description: String {
            "Line[time=\(time), call=\(call), serial=\(serial)]"
        }
    }

    /// `^(\d{3,4})\s+([A-Z0-9/]{3,15})\s+(\d{1,5})$` (Java `LINE`, whole input via `matches`).
    private static let linePattern: JavaRegex = compile("^(\\d{3,4})\\s+([A-Z0-9/]{3,15})\\s+(\\d{1,5})$")
    /// `^(\d{1,3})\s*/\s*(\d{1,2})$` from `parseGroup`.
    private static let groupPattern: JavaRegex = compile("^(\\d{1,3})\\s*/\\s*(\\d{1,2})$")
    /// `\s+` from `serial` (`String.split`).
    private static let whitespace: JavaRegex = compile("\\s+")
    /// `\d{1,5}` from `serial` (`String.matches`).
    private static let serialToken: JavaRegex = compile("\\d{1,5}")

    private static func compile(_ pattern: String) -> JavaRegex {
        do {
            return try JavaRegex(pattern)
        } catch {
            preconditionFailure("pevný vzor QTC musí jít zkompilovat: \(error)")
        }
    }

    /// How many QTCs I may still exchange with `partner`: `max(0, maxPerStation − number of QTCs with it)`, partner
    /// via `equalsIgnoreCase` (sent and received QTCs; a `nil` partner matches nothing).
    public static func remainingFor(_ partner: String?, _ qtcs: [QtcRecord], _ maxPerStation: Int) -> Int {
        var used = 0
        for q in qtcs where JavaChar.equalsIgnoreCase(q.partnerCall, partner) {
            used += 1
        }
        return Swift.max(0, maxPerStation - used)
    }

    /// QSOs to send to station `partner`: chronologically (stable), only not yet reported (key
    /// `CALLSIGN|number` from **sent** QTCs to anyone), not deleted, not X-QSO, not without time, not a QSO with the same
    /// station, at most `min(groupSize, remainingFor)` (negative → none).
    public static func candidates(_ qsos: [Qso], _ partner: String?, _ qtcs: [QtcRecord],
                                  _ maxPerStation: Int, _ groupSize: Int) -> [Qso] {
        let limit: Int = Swift.min(groupSize, remainingFor(partner, qtcs, maxPerStation))
        var reported: Set<String> = []
        for q in qtcs where q.sent {
            reported.insert(key(q.qsoCall, q.qsoSerial))
        }
        var picked: [(index: Int, at: Date, qso: Qso)] = []
        for (index, q) in qsos.enumerated() {
            guard !q.deleted, !q.xqso, let at = q.timestampUtc else { continue }
            if JavaChar.equalsIgnoreCase(q.call, partner) { continue }
            if reported.contains(key(q.call, serial(q))) { continue }
            picked.append((index, at, q))
        }
        picked.sort { a, b in a.at != b.at ? a.at < b.at : a.index < b.index }
        return picked.prefix(Swift.max(0, limit)).map(\.qso)
    }

    private static func key(_ call: String, _ serial: Int) -> String {
        JavaText.toUpperCase(call) + "|" + String(serial)
    }

    /// The serial number the station gave me: `serialRcvd`, otherwise the last exchange token of the form `\d{1,5}`
    /// (ASCII, after `trim()` and `split("\\s+")`), otherwise 0.
    public static func serial(_ q: Qso) -> Int {
        if let serial = q.serialRcvd {
            return serial
        }
        let tokens: [String] = JavaText.split(JavaText.trim(q.exchangeRcvd), regex: whitespace, limit: 0)
        for token in tokens.reversed() where serialToken.matches(token) {
            return Int(token) ?? 0
        }
        return 0
    }

    /// QSO → QTC line (`HHmm` in UTC, callsign `toUpperCase(ROOT)`, number via `serial`). A QSO without time →
    /// `nil` (Java throws `NullPointerException` here; the caller — the candidates — never passes a QSO without time).
    public static func toLine(_ q: Qso) -> Line? {
        guard let at = q.timestampUtc, let stamp = CabrilloExporter.utc(at) else { return nil }
        return Line(time: stamp.time, call: JavaText.toUpperCase(q.call), serial: serial(q))
    }

    /// Parsing a written line "1234 DL1ABC 56" (after `trim()` and `toUpperCase(ROOT)`); a three-digit time is
    /// padded with a zero on the left. `nil` text = empty.
    public static func parseLine(_ text: String?) -> Line? {
        let input: String = JavaText.toUpperCase(JavaText.trim(text ?? ""))
        guard let m = linePattern.wholeMatch(input),
              let rawTime = m.group(1), let call = m.group(2), let rawSerial = m.group(3),
              let serial = Int(rawSerial) else {
            return nil
        }
        let time: String = rawTime.utf16.count == 3 ? "0" + rawTime : rawTime
        return Line(time: time, call: call, serial: serial)
    }

    /// Parsing a series "3/10" (after `trim()`, without case conversion) → series number and count.
    public static func parseGroup(_ text: String?) -> (groupNr: Int, count: Int)? {
        guard let m = groupPattern.wholeMatch(JavaText.trim(text ?? "")),
              let first = m.group(1).flatMap({ Int($0) }),
              let second = m.group(2).flatMap({ Int($0) }) else {
            return nil
        }
        return (first, second)
    }

    /// Text for the CW key: "QTC 3/10" and lines "1234 DL1ABC 56".
    public static func cwText(_ groupNr: Int, _ lines: [Line]) -> [String] {
        var out: [String] = ["QTC \(groupNr)/\(lines.count)"]
        for l in lines {
            out.append("\(l.time) \(l.call) \(l.serial)")
        }
        return out
    }

    /// Cabrillo line (WAE): `QTC: freq mo date time sender series/count recipient time callsign number`.
    ///
    /// Java `String.format(Locale.ROOT, "QTC: %5d %s %s %s %-13s %3d/%-2d %-13s %s %-13s %4d", …)`:
    /// frequency `freqHz / 1000` **as an integer** (truncation toward zero, unlike the QSO line),
    /// mode `SSB|USB|LSB|AM|FM` → `PH`, `RTTY` → `RY`, otherwise (also `nil`) `CW`; sender and recipient
    /// upper-cased, `qsoCall` unchanged; `%-13s` truncates nothing (width in UTF-16 units).
    public static func cabrilloLine(_ q: QtcRecord, _ myCall: String) -> String {
        let sender = q.sent ? myCall : q.partnerCall
        let receiver = q.sent ? q.partnerCall : myCall
        let mode: String
        if let raw = q.mode {
            let upper = raw.uppercased()
            if ["SSB", "USB", "LSB", "AM", "FM"].contains(where: { JavaText.equals($0, upper) }) {
                mode = "PH"
            } else if JavaText.equals("RTTY", upper) {
                mode = "RY"
            } else {
                mode = "CW"
            }
        } else {
            mode = "CW"
        }
        let stamp = CabrilloExporter.utc(q.at)
        let args: [JavaFormat.Arg] = [
            .int(Int(q.freqHz / 1000)), .string(mode), .string(stamp?.date ?? ""), .string(stamp?.time ?? ""),
            .string(sender.uppercased()), .int(q.groupNr), .int(q.groupSize), .string(receiver.uppercased()),
            .string(q.qsoTime), .string(q.qsoCall), .int(q.qsoSerial),
        ]
        return JavaFormat.format("QTC: %5d %s %s %s %-13s %3d/%-2d %-13s %s %-13s %4d", arguments: args)
    }
}
