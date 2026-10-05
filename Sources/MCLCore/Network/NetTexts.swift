import Foundation

/// Texts of the network windows and the network status lines of v1.1.1 (`ui/NetworkStatusWindow.kt`,
/// `ui/PartnerWindow.kt`, `ui/ChatWindow.kt`, `ui/AppState.kt`). Keys are the Czech originals; the app translates them
/// with `tr`.
public enum NetTexts {

    // MARK: - status keys

    static let stackFromKey = "Zásobník od %s: %s (Ctrl+Alt+K vloží)"
    static let passFromKey = "Pass od %s: %s na %s kHz (v bandmapě)"
    static let passSentKey = "Pass: %s předáno stanici %s"
    static let stackSentKey = "Partner: %s → zásobník %s"
    static let stackEmptyKey = "Zásobník volaček je prázdný"
    static let chatNotConnectedKey = "Chat: síťový deník není připojený"
    static let passNeedCallKey = "Pass: napiš volačku, kterou chceš předat"
    static let passNotConnectedKey = "Pass: síťový deník není připojený"
    static let passChooseKey = "Pass %s: vyber stanici v okně Stav sítě"
    static let partnerNotConnectedKey = "Partner: síťový deník není připojený"
    static let passNoteKey = "u mě %.1f"

    /// A Java string concatenation / `String.valueOf` of a possibly missing text.
    static func text(_ value: String?) -> String {
        value ?? "null"
    }

    // MARK: - Network status window

    public static let windowTitle = "Stav sítě"
    public static let notConnected = "Síťový deník není připojený (Nastavení → Cluster; připojí se po aktivaci závodu)."
    public static let noOtherStation = "Žádná další stanice se zatím neohlásila."
    public static let passButton = "Předat"
    public static let connectedKey = "připojeno"
    public static let passHintEmpty = "Pass: napiš volačku do zadávacího okna, pak „Předat“ u cílové stanice (nebo Ctrl+Alt+P)."
    public static let passHintCallKey = "Pass: %s — klikni na „Předat“ u cílové stanice."

    /// A column header: `translate` is false for the headers Kotlin writes without `tr` (`Stanice`, `kHz`, `QSO`,
    /// `Stav`).
    public struct Header: Sendable, Equatable {
        public let text: String
        public let translate: Bool
    }

    /// The columns of the station table, in order (`HEADERS`).
    public static let headers: [Header] = [
        Header(text: "Stanice", translate: false), Header(text: "Operátor", translate: true),
        Header(text: "Pásmo", translate: true), Header(text: "Mód", translate: true),
        Header(text: "kHz", translate: false), Header(text: "Režim", translate: true),
        Header(text: "QSO", translate: false), Header(text: "Stav", translate: false),
    ]

    /// `"Tato stanice: <id> · připojeno|odpojeno"` (the label is not translated, `odpojeno` neither).
    public static func thisStation(stationId: String, connected: Bool, translator: Translator) -> String {
        let state: String = connected ? translator.translate(connectedKey) : "odpojeno"
        return "Tato stanice: " + stationId + " · " + state
    }

    /// The pass hint above the table: the call to pass (the pending one, else the typed one) or the empty hint.
    public static func passHint(pending: String, typedCall: String, translator: Translator) -> String {
        let call: String = NetMessages.defaultPassCall(pending: pending, typedCall: typedCall)
        if KotlinText.isBlank(call) {
            return translator.translate(passHintEmpty)
        }
        return translator.translate(passHintCallKey, [.string(call)])
    }

    /// The state cell of a peer: `offline` (it reported itself offline), `neaktivní N s` (silent for N seconds),
    /// `vysílá`, `online`.
    public static func peerState(_ peer: StationNetwork.Peer, translator: Translator) -> String {
        if !peer.status.online {
            return "offline"
        }
        if !peer.online {
            return translator.translate("neaktivní %s s", [.int(Int(Self.wholeSeconds(peer.age)))])
        }
        if peer.status.transmitting {
            return translator.translate("vysílá")
        }
        return "online"
    }

    /// Java `Duration.getSeconds()`: whole seconds rounded towards negative infinity.
    static func wholeSeconds(_ duration: Duration) -> Int64 {
        let parts = duration.components
        return parts.attoseconds < 0 ? parts.seconds - 1 : parts.seconds
    }

    /// The cells of a peer row (the eight columns of `headers`).
    public static func peerCells(_ peer: StationNetwork.Peer, translator: Translator) -> [String] {
        let s: StationNetwork.Peer = peer
        let status: StationStatusWire = s.status
        let freq: String = status.freqHz > 0 ? JavaFormat.format("%.1f", .double(Double(status.freqHz) / 1000)) : ""
        let count: String = s.online ? String(status.qsoCount) : ""
        return [status.stationId ?? "null", status.operator ?? "", status.band ?? "", status.mode ?? "", freq,
                status.runMode ?? "", count, peerState(s, translator: translator)]
    }

    // MARK: - Partner window

    public static let partnerTitle = "Partner"
    public static let partnerNotConnected = "Síťový deník není připojený."
    public static let partnerRunnerLabel = "Runner (komu posílat):"
    public static let partnerNoOnline = "žádná online stanice"
    public static let partnerPlaceholder = "Volačka do zásobníku (Enter)"
    public static let partnerButton = "Do zásobníku"
    public static let partnerHint = "Runner vidí zásobník v zadávacím okně a Ctrl+Alt+K vloží další volačku do pole."

    /// The selected runner's line: `%s  %s %s  %.1f kHz  · píše: %s` (US decimals), the entry call or `—`.
    public static func partnerLine(_ status: StationStatusWire, translator: Translator) -> String {
        let entry: String = KotlinText.isBlank(status.entryCall ?? "") ? "—" : (status.entryCall ?? "")
        let args: [Translator.Arg] = [.string(status.stationId), .string(status.band), .string(status.mode),
                                      .double(Double(status.freqHz) / 1000), .string(entry)]
        return translator.translate("%s  %s %s  %.1f kHz  · píše: %s", args)
    }

    // MARK: - Chat window

    public static let chatTitle = "Chat"
    public static let chatEveryone = "Všem"
    public static let chatMe = "já"
    public static let chatNotConnectedPlaceholder = "Síťový deník není připojený"
    public static let chatPlaceholder = "Zpráva (Enter odešle)"
    /// The send button label (Kotlin: not translated).
    public static let chatSend = "Odeslat"

    /// A chat row: `time  who[ → to]: text`, `who` is `já` for an own line.
    public static func chatRow(_ line: ChatLine, translator: Translator) -> String {
        let target: String = KotlinText.isBlank(line.to) ? "" : " → " + line.to
        let who: String = line.own ? translator.translate(chatMe) : line.from
        return line.time + "  " + who + target + ": " + line.text
    }

    // MARK: - clearing the logbook

    public static let wipeNoteKey = "\n\nJsi připojený ke clusteru — QSO zmizí i na ostatních stanicích."

    /// The extra paragraph of the wipe-logbook confirmation: only while the cluster is connected.
    public static func wipeNote(connected: Bool) -> EntryStatus {
        connected ? .tr(wipeNoteKey) : .verbatim("")
    }
}
