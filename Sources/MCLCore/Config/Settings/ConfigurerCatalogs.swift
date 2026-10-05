/// Fixed choice lists of the Settings tabs. Czech entries that Kotlin wraps in a frozen `tr` are kept as
/// translation keys and translated when rendered; the rest are literals.
public enum ConfigurerCatalogs {

    /// `BAUD_RATES` (`HardwareTab.kt:65`).
    public static let baudRates: [Int] = [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200]

    /// `REGIONS` (`BandPlanTab.kt:30`).
    public static let regions: [String] = ["R1", "R2", "R3"]

    /// `MODES` of the band plan (`BandPlanTab.kt:31`).
    public static let bandPlanModes: [String] = ["CW", "DIGI", "PHONE"]

    /// Data-mode choices of the rig (`ModeTabs.kt:62`).
    public static let dataModes: [String] = ["DIGITAL", "FT8", "FT4", "RTTY", "PSK", "JT65"]

    /// Foot-switch wires (`HardwareTab.kt:133`).
    public static let footswitchPins: [String] = ["CTS", "DSR", "DCD"]

    /// Foot-switch actions (`HardwareTab.kt:136`).
    public static let footswitchActions: [String] = ["PTT", "ENTER", "F1"]

    /// `ACCENTS` (`ModeTabs.kt:261-266`): key → Czech translation key, in order.
    public static let accents: [(key: String, labelKey: String)] = [
        ("TEAL", "Tyrkysová (výchozí)"),
        ("BLUE", "Modrá"),
        ("ORANGE", "Oranžová"),
        ("CONTRAST", "Vysoký kontrast"),
    ]

    /// Label shown for an accent outside `ACCENTS` (`ACCENTS[x] ?: tr("Tyrkysová")`, `ModeTabs.kt:172`).
    public static let unknownAccentLabelKey = "Tyrkysová"

    /// The accent label key for `key` (`ACCENTS[key] ?: tr("Tyrkysová")`).
    public static func accentLabelKey(_ key: String) -> String {
        accents.first { $0.key == key }?.labelKey ?? unknownAccentLabelKey
    }

    /// `SCOREBOARDS` (`ScoreReportingTab.kt:69-72`): name → posting URL, in order.
    public static let scoreboards: [(name: String, url: String)] = [
        ("contestonlinescore.com", "https://contestonlinescore.com/post/"),
        ("cqcontest.net", "https://cqcontest.net/post.php"),
    ]

    /// `MAP_SCHEMES` (`ui/MapStyle.kt:21-42`): key → Czech translation key, in order (colours live in the views).
    public static let mapSchemes: [(key: String, labelKey: String)] = [
        ("green", "Zelená"),
        ("gray", "Šedá"),
        ("sepia", "Sépiová"),
        ("slate", "Modrošedá"),
    ]

    /// Theme radio buttons (`ModeTabs.kt:167-169`): key → Czech translation key, in order.
    public static let themeModes: [(key: String, labelKey: String)] = [
        ("SYSTEM", "Podle systému"),
        ("LIGHT", "Světlý"),
        ("DARK", "Tmavý"),
    ]
}
