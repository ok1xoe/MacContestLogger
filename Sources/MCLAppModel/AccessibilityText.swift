import Foundation
import MCLCore

/// The spoken texts of the controls and drawn islands that have no text of their own (VoiceOver labels, values and
/// summaries). Pure functions of plain values and a `Translator`, so they are tested without a window; the views only
/// pass what they already have. Every Czech literal here is a translation key (the shipped `lang_en.json` /
/// `lang_de.json` carry them; `scripts/a11y-audit.py` checks that).
public enum AccessibilityText {

    // MARK: - the TRX LED

    public enum RigLedState: Equatable, Sendable {
        case connected
        case disconnected
        case connecting
    }

    /// The LED state from the rig's snapshot flags.
    public static func rigLedState(connected: Bool, connecting: Bool) -> RigLedState {
        if connected {
            return .connected
        }
        return connecting ? .connecting : .disconnected
    }

    public static func rigLedValue(_ state: RigLedState, translator: Translator) -> String {
        switch state {
        case .connected:
            return translator.translate("Připojeno")
        case .disconnected:
            return translator.translate("Odpojeno")
        case .connecting:
            return translator.translate("Připojuji…")
        }
    }

    // MARK: - the score bar

    /// „QSO 12, body 34, násobiče 5, skóre 170".
    public static func scoreBarValue(qso: String, points: String, mult: String, total: String,
                                     translator: Translator) -> String {
        let parts: [String] = [
            "QSO " + qso,
            translator.translate("Body") + " " + points,
            translator.translate("násobiče") + " " + mult,
            translator.translate("Skóre") + " " + total,
        ]
        return parts.joined(separator: ", ")
    }

    // MARK: - the band map

    /// One spot of the band map: „OK1ABC, 14025.3 kHz, duplicitní".
    public static func bandmapSpot(call: String, freqHz: Int, color: SpotColorClassifier.SpotColorKey,
                                   translator: Translator) -> String {
        let khz: String = EntryFormat.oneDecimal(Double(freqHz) / 1000.0)
        var parts: [String] = [call, khz + " kHz"]
        switch color {
        case .dupe:
            parts.append(translator.translate("duplicitní"))
        case .good:
            break
        case .oneMult:
            parts.append(translator.translate("nový násobič"))
        case .multiMult:
            parts.append(translator.translate("více nových násobičů"))
        }
        return parts.joined(separator: ", ")
    }

    /// The value of the whole band map: the band, the tuned frequency, the number of spots.
    public static func bandmapValue(band: String, tunedHz: Int64, spots: Int, translator: Translator) -> String {
        let khz: String = EntryFormat.oneDecimal(Double(tunedHz) / 1000.0)
        let count: String = translator.translate("spotů: %d", [.int(spots)])
        return [band, khz + " kHz", count].joined(separator: ", ")
    }

    // MARK: - the world map

    /// „Čtverce: 12" / „Zemí: 31" — what the map shows.
    public static func worldMapValue(dxccMode: Bool, fields: Int, dots: Int, translator: Translator) -> String {
        if dxccMode {
            return translator.translate("zemí: %d", [.int(dots)])
        }
        return translator.translate("čtverců: %d", [.int(fields)])
    }

    // MARK: - the charts

    /// The hour chart: the title (with the maximum) and the covered range, or „žádná data".
    public static func hourChartValue(_ chart: HourlyChart, translator: Translator) -> String {
        guard let first = chart.hours.first, let last = chart.hours.last, !chart.values.isEmpty else {
            return chart.title + ", " + translator.translate("žádná data")
        }
        let total: Int = chart.values.reduce(0, +)
        let range: String = translator.translate(
            "hodin: %d, od %s do %s, celkem QSO: %d",
            [.int(chart.values.count), .string(first), .string(last), .int(total)])
        return chart.title + ", " + range
    }

    /// The goal status as a word (the bars and the trend colour it, the colour alone says nothing to VoiceOver).
    public static func goalStatus(_ status: GoalStatus, translator: Translator) -> String? {
        switch status {
        case .none:
            return nil
        case .met:
            return translator.translate("cíl splněn")
        case .close:
            return translator.translate("blízko cíle")
        case .missed:
            return translator.translate("pod cílem")
        }
    }

    /// „Hodnota: 5, cíl splněn".
    private static func valueWithStatus(_ value: Int, _ status: GoalStatus, translator: Translator) -> String {
        guard let word = goalStatus(status, translator: translator) else { return String(value) }
        return String(value) + " (" + word + ")"
    }

    /// The near-term rate bars: „posledních 10: 5, …", each with its goal status when there is a goal.
    public static func rateBarsValue(_ rates: NearTermRates, translator: Translator) -> String {
        let items: [String] = rates.bars.map { bar in
            bar.label + ": " + valueWithStatus(bar.value, bar.status, translator: translator)
        }
        return ([rates.title] + items).joined(separator: ", ")
    }

    /// The trend line: the title, the number of points and the last value with its clock.
    public static func trendValue(_ trend: TrendView, translator: Translator) -> String {
        guard let last = trend.points.last else {
            return trend.title + ", " + translator.translate("žádná data")
        }
        let count: String = translator.translate("bodů: %d", [.int(trend.points.count)])
        let latest: String = translator.translate(
            "poslední %s: %s", [.string(last.clock), .string(valueWithStatus(last.value, last.status,
                                                                             translator: translator))])
        return [trend.title, count, latest].joined(separator: ", ")
    }

    // MARK: - the rotator compass

    /// „Rotátor 123°, cíl 45°".
    public static func compassValue(azimuth: Double?, target: Int?, translator: Translator) -> String {
        var parts: [String] = []
        if let azimuth {
            parts.append(translator.translate("rotátor %d°", [.int(Int(azimuth.rounded()))]))
        } else {
            parts.append(translator.translate("rotátor neznámý"))
        }
        if let target {
            parts.append(translator.translate("cíl %d°", [.int(target)]))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - marks that are glyphs only

    /// The ⚠ cell of the log table: the warning text, or empty.
    public static func logWarning(_ warning: String?, translator: Translator) -> String {
        guard let warning else { return "" }
        return translator.translate("Varování") + ": " + warning
    }

    /// The X-QSO cell of the log table: `·` stands for none.
    public static func logXQso(_ text: String, translator: Translator) -> String {
        text.isEmpty ? translator.translate("bez X-QSO") : translator.translate("X-QSO") + " " + text
    }

    /// The ✓ of the available-multipliers table.
    public static func multMark(_ isMult: Bool, translator: Translator) -> String {
        isMult ? translator.translate("násobič") : ""
    }

    /// A timer cell of the Info window: the colour (green / amber / red) as a word.
    public static func timerState(_ state: TimerState, translator: Translator) -> String? {
        switch state {
        case .none:
            return nil
        case .ok:
            return translator.translate("v pořádku")
        case .warn:
            return translator.translate("pozor")
        case .over:
            return translator.translate("po termínu")
        }
    }

    /// The info strip's text with its 📝 glyph spoken: „📝 Poznámka" becomes „Poznámka k pásmu: Poznámka".
    public static func infoStrip(_ text: String, translator: Translator) -> String {
        text.replacingOccurrences(of: "📝", with: translator.translate("Poznámka k pásmu") + ":")
    }

    /// A points cell of the log table: a duplicate is red only, so it is said.
    public static func logPoints(_ text: String, dupe: Bool, translator: Translator) -> String {
        dupe ? text + ", " + translator.translate("duplicitní") : text
    }

    /// A column header of the log table; the sort arrow (▲ / ▼) becomes words.
    public static func logHeader(title: String, sorted: Bool?, translator: Translator) -> String {
        guard let sorted else { return title }
        let order: String = sorted ? translator.translate("řazeno vzestupně") : translator.translate("řazeno sestupně")
        return title + ", " + order
    }

    /// A call of the dupesheet that contains the typed text is only highlighted.
    public static func dupesheetCall(_ text: String, hit: Bool, translator: Translator) -> String {
        hit ? text + ", " + translator.translate("shoduje se s psaným") : text
    }
}
