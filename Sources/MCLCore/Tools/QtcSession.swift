import Foundation

/// The QTC window logic (WAE, Kotlin `QtcWindow.kt` and `AppState.saveQtcGroup`, `AS:592-640`): the next series number,
/// multi-line parsing of received lines, the limit check and the status texts. Pure: the caller stores the records.
public enum QtcSession {

    /// The result of parsing the lines typed into the "received QTC" field.
    public struct Parsed: Equatable, Sendable {
        /// The non-blank input lines in order with their parse result (`nil` = unreadable).
        public let entries: [(text: String, line: QtcPlanner.Line?)]
        /// The readable lines in order.
        public let lines: [QtcPlanner.Line]
        /// The texts of the unreadable lines.
        public let bad: [String]

        /// Kotlin `enabled = bad.isEmpty() && parsed.isNotEmpty()`.
        public var canSave: Bool {
            bad.isEmpty && !entries.isEmpty
        }

        /// `Nečitelné řádky: a | b`, or `nil` when every line is readable.
        public func badText(_ translator: Translator) -> String? {
            bad.isEmpty ? nil : translator.translate("Nečitelné řádky: %s", [.string(bad.joined(separator: " | "))])
        }

        public static func == (lhs: Parsed, rhs: Parsed) -> Bool {
            lhs.lines == rhs.lines && lhs.bad == rhs.bad && lhs.entries.map(\.text) == rhs.entries.map(\.text)
        }
    }

    /// Number of the next series I send: the count of distinct series numbers among **sent** QTCs plus one.
    public static func nextGroup(qtcs: [QtcRecord]) -> Int {
        var seen: Set<Int> = []
        for q in qtcs where q.sent {
            seen.insert(q.groupNr)
        }
        return seen.count + 1
    }

    /// Kotlin `String.lines()`: splits on `\r\n`, `\n` and `\r`.
    static func lines(of text: String) -> [String] {
        var out: [String] = []
        var current: [UInt16] = []
        let units: [UInt16] = Array(text.utf16)
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == 0x0D || unit == 0x0A {
                out.append(JavaChar.string(current))
                current = []
                if unit == 0x0D, index + 1 < units.count, units[index + 1] == 0x0A {
                    index += 1
                }
            } else {
                current.append(unit)
            }
            index += 1
        }
        out.append(JavaChar.string(current))
        return out
    }

    /// Parses the typed lines: blank lines are skipped, each other one through `QtcPlanner.parseLine`.
    public static func parseLines(_ text: String) -> Parsed {
        var entries: [(text: String, line: QtcPlanner.Line?)] = []
        for raw in lines(of: text) where !KotlinText.isBlank(raw) {
            entries.append((raw, QtcPlanner.parseLine(raw)))
        }
        let good: [QtcPlanner.Line] = entries.compactMap(\.line)
        let bad: [String] = entries.filter { $0.line == nil }.map(\.text)
        return Parsed(entries: entries, lines: good, bad: bad)
    }

    /// Partner callsign as stored: Kotlin `trim().uppercase()`.
    public static func normalizedPartner(_ partner: String) -> String {
        JavaText.toUpperCase(KotlinText.trim(partner))
    }

    /// Checks a series before saving; `nil` = fine, otherwise the status line text. The checks run in Kotlin order:
    /// the contest has QTC at all, a partner and lines are given, the per-station limit is not exceeded.
    public static func validate(partner: String, lines: [QtcPlanner.Line], qtcs: [QtcRecord],
                                config: ContestDefinition.Qtc?, translate: Translator) -> String? {
        guard let config else { return translate.translate("QTC: aktivní závod QTC nemá") }
        let normalized: String = normalizedPartner(partner)
        if KotlinText.isBlank(normalized) || lines.isEmpty {
            return translate.translate("QTC: chybí stanice nebo řádky")
        }
        let limit: Int = config.maxPerStationOrDefault
        let remaining: Int = QtcPlanner.remainingFor(normalized, qtcs, limit)
        if lines.count > remaining {
            return translate.translate("QTC: se stanicí %s zbývá už jen %s QTC (limit %s)",
                                       [.string(normalized), .int(remaining), .int(limit)])
        }
        return nil
    }

    /// The records of a saved series (one per line), `partner` normalised; the mode is the rig mode name, `CW` without a rig.
    public static func records(sent: Bool, partner: String, groupNr: Int, lines: [QtcPlanner.Line],
                               contestId: String?, now: Date, freqHz: Int64, rigMode: String?) -> [QtcRecord] {
        let normalized: String = normalizedPartner(partner)
        return lines.map { line in
            QtcRecord(id: nil, contestId: contestId, sent: sent, partnerCall: normalized, groupNr: groupNr,
                      groupSize: lines.count, qsoTime: line.time, qsoCall: line.call, qsoSerial: line.serial,
                      at: now, freqHz: freqHz, mode: rigMode ?? "CW")
        }
    }

    /// Status text after saving; `total` is the number of QTCs **after** the reload (including the new ones).
    public static func savedText(sent: Bool, groupNr: Int, count: Int, partner: String, total: Int,
                                 translate: Translator) -> String {
        let args: [Translator.Arg] = [.int(groupNr), .int(count), .string(normalizedPartner(partner)), .int(total)]
        return translate.translate(sent ? "QTC odesláno: %s/%s se stanicí %s (celkem %s)"
                                        : "QTC přijato: %s/%s se stanicí %s (celkem %s)", args)
    }

    /// `zbývá <n> z <max> QTC · celkem <total> QTC` above the series (partner trimmed, not upper-cased).
    public static func remainingText(partner: String, qtcs: [QtcRecord], config: ContestDefinition.Qtc,
                                     translate: Translator) -> String {
        let limit: Int = config.maxPerStationOrDefault
        let remaining: Int = QtcPlanner.remainingFor(KotlinText.trim(partner), qtcs, limit)
        return translate.translate("zbývá %s z %s QTC · celkem %s QTC", [.int(remaining), .int(limit), .int(qtcs.count)])
    }

    /// `Série <n>/<count>:` above the lines to send.
    public static func seriesTitle(groupNr: Int, count: Int, translate: Translator) -> String {
        translate.translate("Série %s/%s:", [.int(groupNr), .int(count)])
    }

    /// The text sent by "Odvysílat CW": the series header and the lines joined by single spaces.
    public static func cwSendText(groupNr: Int, lines: [QtcPlanner.Line]) -> String {
        QtcPlanner.cwText(groupNr, lines).joined(separator: " ")
    }

    /// Series number typed for received QTCs (`3/10` → 3), 1 when it does not parse.
    public static func receivedGroupNr(_ text: String) -> Int {
        QtcPlanner.parseGroup(text)?.groupNr ?? 1
    }

    /// A row of the list of exchanged QTCs: `→`/`←`, partner padded to 10, `n/size`, time, callsign padded to 10, number.
    public static func rowText(_ q: QtcRecord) -> String {
        let arrow: String = q.sent ? "→" : "←"
        let partner: String = ToolsFormat.padEnd(q.partnerCall, 10)
        let call: String = ToolsFormat.padEnd(q.qsoCall, 10)
        return "\(arrow) \(partner) \(q.groupNr)/\(q.groupSize)  \(q.qsoTime) \(call) \(q.qsoSerial)"
    }
}
