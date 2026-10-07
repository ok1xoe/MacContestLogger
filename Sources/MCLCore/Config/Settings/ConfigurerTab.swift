/// Tabs of the Settings window (Configurer) — `ui/configurer/ConfigurerTab.kt:10-36`. `key` is the stable
/// identifier used by `menu.json` (`tab.<key>`); the case order is the default order of the tab strip.
///
/// Kotlin freezes `tr(…)` for four titles (`KEYS`, `WINKEY`, `CONTEST`, `BANDPLAN`) at enum initialisation; the
/// others are literals outside `tr`. Swift keeps the Czech text as `titleKey` and says with `isTitleTranslated`
/// whether a view translates it when rendering.
public enum ConfigurerTab: CaseIterable, Sendable, Hashable {
    case hardware
    case functionKeys
    case keys
    case digitalModes
    case other
    case winkey
    case modeControl
    case antennas
    case scoreReporting
    case broadcast
    case wsjt
    case audio
    case station
    case contest
    case cluster
    case dxCluster
    case onlineCallbooks
    case bandplan
    case digiFreq
    case map
    /// The window plugins' grants (Swift only).
    case plugins

    /// Kebab identifier from `menu.json` (`online_logs` keeps its underscore, as in Kotlin).
    public var key: String {
        switch self {
        case .hardware: return "hardware"
        case .functionKeys: return "function-keys"
        case .keys: return "keys"
        case .digitalModes: return "digital-modes"
        case .other: return "other"
        case .winkey: return "winkey"
        case .modeControl: return "mode-control"
        case .antennas: return "antennas"
        case .scoreReporting: return "score-reporting"
        case .broadcast: return "broadcast"
        case .wsjt: return "wsjt"
        case .audio: return "audio"
        case .station: return "station"
        case .contest: return "contest"
        case .cluster: return "cluster"
        case .dxCluster: return "dxcluster"
        case .onlineCallbooks: return "online_logs"
        case .bandplan: return "bandplan"
        case .digiFreq: return "digifreq"
        case .map: return "map"
        case .plugins: return "plugins"
        }
    }

    /// Kotlin `title`: the Czech translation key (for the four `tr` titles) or the literal.
    public var titleKey: String {
        switch self {
        case .hardware: return "Hardware"
        case .functionKeys: return "Function Keys"
        case .keys: return "Klávesy"
        case .digitalModes: return "Digital Modes"
        case .other: return "Other"
        case .winkey: return "CW klíč"
        case .modeControl: return "Mode Control"
        case .antennas: return "Antennas"
        case .scoreReporting: return "Score Reporting"
        case .broadcast: return "Broadcast Data"
        case .wsjt: return "WSJT/JTDX"
        case .audio: return "Audio"
        case .station: return "Stanice"
        case .contest: return "Závod"
        case .cluster: return "Cluster"
        case .dxCluster: return "DX Cluster"
        case .onlineCallbooks: return "Online callbooks"
        case .bandplan: return "Bandplán"
        case .digiFreq: return "Digi frekvence"
        case .map: return "Mapa"
        case .plugins: return "Pluginy"
        }
    }

    /// Whether Kotlin wraps the title in `tr` (`KEYS`, `WINKEY`, `CONTEST`, `BANDPLAN`).
    public var isTitleTranslated: Bool {
        switch self {
        case .keys, .winkey, .contest, .bandplan, .plugins: return true
        default: return false
        }
    }

    /// `ConfigurerTab.byKey`: the first tab with exactly this key (case-sensitive), otherwise `nil`.
    public static func byKey(_ key: String) -> ConfigurerTab? {
        allCases.first { $0.key == key }
    }
}

/// A tab shown in the Settings window — `ConfigurerTabSpec` (`ConfigurerTab.kt:39`): the tab, its displayed label
/// and its state from `menu.json` (`enable`/`disable`; hidden tabs never get a spec).
///
/// `labelKey` is the text before translation; `isLabelTranslated` says whether Kotlin passes it through `tr`
/// (always for a spec from `menu.json`, only for the four `tr` titles in the fallback without a tab host).
public struct ConfigurerTabSpec: Equatable, Sendable {
    public let tab: ConfigurerTab
    public let labelKey: String
    public let isLabelTranslated: Bool
    public let state: MenuState

    public init(tab: ConfigurerTab, labelKey: String, isLabelTranslated: Bool, state: MenuState) {
        self.tab = tab
        self.labelKey = labelKey
        self.isLabelTranslated = isLabelTranslated
        self.state = state
    }
}
