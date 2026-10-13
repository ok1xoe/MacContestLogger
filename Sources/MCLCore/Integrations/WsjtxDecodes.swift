import Foundation

/// The WSJT-X decode list (N1MM Decode List; `AppState.onWsjtxDecode` and `WsjtxDecodesWindow`, v1.1.1): decodes
/// enriched with the dupe / new-multiplier state of the active contest, newest first, at most 300. The decodes only
/// classify — they are not added to the bandmap.
public struct WsjtxDecodes: Sendable {

    /// `WSJTX_DECODES_MAX`.
    public static let maxRows = 300
    /// Shown while no WSJT-X status arrived (`tr` key).
    public static let waitingText = "Čekám na WSJT-X (Nastavení → WSJT-X → příjem)…"

    public struct Row: Equatable, Sendable {
        public let decode: WsjtxMessages.Decode
        public let from: UdpEndpoint
        public let parsed: Ft8Message
        /// Dial + audio offset in Hz, `0` while the dial frequency is unknown.
        public let freqHz: Int64
        public let dupe: Bool
        public let newMultCount: Int
        /// The band of `freqHz` (`nil` while the dial is unknown) and the mode (the decode's, else the status's).
        public var band: Band? {
            freqHz > 0 ? Band.from(frequencyHz: Int(freqHz)) : nil
        }
        public var modeName: String {
            WsjtxDecodes.modeName(decode.mode, statusMode: nil)
        }
    }

    /// The decode list's sort order (Swift-only: N1MM's sortable columns).
    public enum Sort: String, CaseIterable, Sendable {
        /// Newest first (the order they arrive in).
        case time
        /// The strongest first.
        case snr
        /// The lowest audio offset first.
        case frequency
        /// By the caller's call.
        case call
    }

    /// WSJT-X's one-character mode of a decode (`~` FT8, `+` FT4, `:` Q65 …) as a name; otherwise the status mode.
    public static func modeName(_ decodeMode: String?, statusMode: String?) -> String {
        switch decodeMode ?? "" {
        case "~": "FT8"
        case "+": "FT4"
        case ":": "Q65"
        case "#": "JT65"
        case "@": "JT9"
        case "`": "FST4"
        default: statusMode ?? (decodeMode ?? "")
        }
    }

    /// The colours a caller gets in WSJT-X's Band Activity (N1MM uses the bandmap's): background for a multiplier
    /// (red one, green several), text colour for a new QSO (blue) and a dupe (grey).
    public static func highlight(dupe: Bool, newMultCount: Int)
        -> (background: WsjtxMessages.Rgb?, foreground: WsjtxMessages.Rgb?) {
        switch SpotColorClassifier.classify(dupe: dupe, newMultCount: newMultCount) {
        case .dupe: (nil, WsjtxMessages.Rgb(0x9E9E9E))
        case .good: (nil, WsjtxMessages.Rgb(0x1E88E5))
        case .oneMult: (WsjtxMessages.Rgb(0xE53935), WsjtxMessages.Rgb(0xFFFFFF))
        case .multiMult: (WsjtxMessages.Rgb(0x43A047), WsjtxMessages.Rgb(0xFFFFFF))
        }
    }

    /// Newest first.
    public private(set) var rows: [Row] = []

    public init() {}

    /// A list over existing rows (newest first), cut to the cap.
    public init(rows: [Row]) {
        self.rows = Array(rows.prefix(Self.maxRows))
    }

    /// `onWsjtxDecode`. The frequency is the dial plus the audio offset only with a known dial; the state comes from the
    /// contest analyzer (`nil` outside a contest = neutral) and is dupe also when the call was worked on that band
    /// (`isDupe`, which does not depend on the contest). Both only for a callsign and a frequency.
    public mutating func add(_ decode: WsjtxMessages.Decode, from: UdpEndpoint, status: WsjtxMessages.Status?,
                             analyzer: SpotAnalyzer?, isDupe: (String, Band?) -> Bool) {
        let parsed: Ft8Message = Ft8Message.parse(decode.message)
        let dial: Int64 = status?.dialFrequencyHz ?? 0
        let freq: Int64 = dial > 0 ? dial + Int64(decode.deltaFrequency) : 0
        let caller: String = parsed.caller
        var dupe = false
        var mults = 0
        if !KotlinText.isBlank(caller) && freq > 0 {
            let spot = DxSpot(spotter: "WSJT-X", freqHz: Int(freq), dxCall: caller, comment: status?.mode ?? "FT8")
            let state: SpotStatus = analyzer?.spotStatus(spot) ?? .neutral
            dupe = state.dupe || isDupe(caller, Band.from(frequencyHz: Int(freq)))
            mults = state.newMultCount
        }
        rows.insert(Row(decode: decode, from: from, parsed: parsed, freqHz: freq, dupe: dupe, newMultCount: mults), at: 0)
        if rows.count > Self.maxRows {
            rows.removeLast(rows.count - Self.maxRows)
        }
    }

    /// WSJT-X "Clear" message.
    public mutating func clear() {
        rows.removeAll()
    }

    /// The window filters (`Jen CQ`, `Skrýt dupe`, `Jen násobiče`).
    public func filtered(onlyCq: Bool, hideDupe: Bool, onlyMult: Bool) -> [Row] {
        rows.filter { row in
            (!onlyCq || row.parsed.cq) && (!hideDupe || !row.dupe) && (!onlyMult || row.newMultCount > 0)
        }
    }

    /// The filters with a text filter (any part of the message, case-insensitive; `73` finds the 73s, N1MM) and a
    /// sort order (stable: equal rows keep newest first).
    public func filtered(onlyCq: Bool, hideDupe: Bool, onlyMult: Bool, text: String, sort: Sort) -> [Row] {
        let needle: String = KotlinText.trim(text).uppercased()
        var out: [Row] = filtered(onlyCq: onlyCq, hideDupe: hideDupe, onlyMult: onlyMult).filter { row in
            needle.isEmpty || (row.decode.message ?? "").uppercased().contains(needle)
        }
        switch sort {
        case .time:
            break
        case .snr:
            out = out.enumerated().sorted { ($0.element.decode.snr, -$0.offset) > ($1.element.decode.snr, -$1.offset) }
                .map(\.element)
        case .frequency:
            out = out.enumerated().sorted {
                ($0.element.decode.deltaFrequency, $0.offset) < ($1.element.decode.deltaFrequency, $1.offset)
            }.map(\.element)
        case .call:
            out = out.enumerated().sorted { ($0.element.parsed.caller, $0.offset) < ($1.element.parsed.caller, $1.offset) }
                .map(\.element)
        }
        return out
    }

    // MARK: - texts

    /// The cells of a row: time `HHMMSS`, SNR `%+3ld`, audio offset, message, label.
    public struct RowText: Equatable, Sendable {
        public let time: String
        public let snr: String
        public let deltaFrequency: String
        public let message: String
        public let label: String
    }

    public static func rowText(_ row: Row) -> RowText {
        let d: WsjtxMessages.Decode = row.decode
        let t: Int = Int(d.timeMs) / 1000
        let time: String = String(format: "%02ld%02ld%02ld", t / 3600, t / 60 % 60, t % 60)
        let label: String
        if row.dupe {
            label = "dupe"
        } else if row.newMultCount > 1 {
            label = String(row.newMultCount) + "× mult"
        } else if row.newMultCount == 1 {
            label = "mult"
        } else {
            label = ""
        }
        return RowText(time: time, snr: String(format: "%+3ld", Int(d.snr)), deltaFrequency: String(d.deltaFrequency),
                       message: d.message ?? "", label: label)
    }

    /// The line above the list: `mode  14074.000 kHz` (Locale US) plus `  · vysílá` while transmitting; the waiting text
    /// before the first status.
    public static func statusText(status: WsjtxMessages.Status?) -> EntryStatus {
        guard let status else { return .tr(waitingText) }
        let kHz: Double = Double(status.dialFrequencyHz) / 1000.0
        let mode: String = status.mode ?? ""
        let formatted: String? = Translator.format("%s  %.3f kHz", [.string(mode), .double(kHz)])
        let head: String = formatted ?? mode
        let text: EntryStatus = .verbatim(head)
        return status.transmitting ? text.appending(.tr("  · vysílá")) : text
    }
}
