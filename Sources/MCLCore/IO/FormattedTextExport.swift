import Foundation

/// N1MM's generic text output with a contest's own layout (UDC `CabrilloString` / the generic file export): one line per
/// QSO built from a template of the definition (`export.text`). Placeholders `{name}` or `{name:width}` — a positive
/// width pads on the right (left-aligned), a negative one on the left (right-aligned); values are cut to the width.
///
/// Names: `date` (yyyy-mm-dd), `time` (hhmm), `call`, `band`, `freq` (kHz), `mode`, `rsts`, `rstr`, `nrs`, `nrr`
/// (serials), `sent`, `rcvd` (the whole exchanges), `op`, `points`, `note`, `mycall` and the id of any received field.
public enum FormattedTextExport {

    /// The template used when the definition has none.
    public static let defaultTemplate = "{date:10} {time:4} {freq:-7} {mode:5} {call:13} {rsts:3} {sent:14} {rstr:3} {rcvd}"

    public static func text(_ qsos: [Qso], template: String?, myCall: String,
                            received: (Qso) -> JavaLinkedMap<String>) -> String {
        let layout: String = template.map { KotlinText.trim($0) }.flatMap { $0.isEmpty ? nil : $0 } ?? defaultTemplate
        let ordered: [Qso] = qsos.enumerated().sorted { a, b in
            let ta: Date = a.element.timestampUtc ?? .distantPast
            let tb: Date = b.element.timestampUtc ?? .distantPast
            return ta != tb ? ta < tb : a.offset < b.offset
        }.map(\.element)
        var out = ""
        for qso in ordered where !qso.deleted {
            out += line(qso, layout: layout, myCall: myCall, received: received(qso)) + "\n"
        }
        return out
    }

    static func line(_ qso: Qso, layout: String, myCall: String, received: JavaLinkedMap<String>) -> String {
        var out = ""
        var rest = Substring(layout)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                out += rest[open...]
                return out.trimmingTrailingSpaces()
            }
            let spec = rest[rest.index(after: open)..<close]
            let parts = spec.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0]).lowercased()
            let width: Int? = parts.count > 1 ? Int(parts[1]) : nil
            out += pad(value(name, qso, myCall: myCall, received: received), width)
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        return out.trimmingTrailingSpaces()
    }

    private static func value(_ name: String, _ qso: Qso, myCall: String, received: JavaLinkedMap<String>) -> String {
        switch name {
        case "date":
            return qso.timestampUtc.map { stamp($0, "yyyy-MM-dd") } ?? ""
        case "time":
            return qso.timestampUtc.map { stamp($0, "HHmm") } ?? ""
        case "call": return qso.call
        case "band": return qso.band?.adif ?? ""
        case "freq": return qso.freqHz > 0 ? String(qso.freqHz / 1000) : ""
        case "mode": return qso.mode?.rawValue ?? ""
        case "rsts": return qso.rstSent
        case "rstr": return qso.rstRcvd
        case "nrs": return qso.serialSent.map(String.init) ?? ""
        case "nrr": return qso.serialRcvd.map(String.init) ?? ""
        case "sent": return KotlinText.trim(qso.exchangeSent)
        case "rcvd": return KotlinText.trim(qso.exchangeRcvd)
        case "op": return qso.operator
        case "points": return String(qso.points)
        case "note": return qso.comment
        case "mycall": return myCall
        default:
            for (key, fieldValue) in received.entries where (key ?? "").lowercased() == name {
                return KotlinText.trim(fieldValue ?? "")
            }
            return ""
        }
    }

    private static func pad(_ text: String, _ width: Int?) -> String {
        guard let width, width != 0 else { return text }
        let size: Int = abs(width)
        let cut: String = String(text.prefix(size))
        let fill = String(repeating: " ", count: size - cut.count)
        return width > 0 ? cut + fill : fill + cut
    }

    private static func stamp(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

private extension String {
    func trimmingTrailingSpaces() -> String {
        var copy = self
        while copy.last == " " {
            copy.removeLast()
        }
        return copy
    }
}
