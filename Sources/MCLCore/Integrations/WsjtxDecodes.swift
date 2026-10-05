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
