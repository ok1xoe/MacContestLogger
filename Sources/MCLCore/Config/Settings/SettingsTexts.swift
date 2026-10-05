import Foundation

/// Fixed texts of the Settings window that the core hands to the app (`CD:` = `ui/configurer/ConfigurerDraft.kt`,
/// `AS:` = `ui/AppState.kt`, `KT:` = `ui/configurer/KeysTab.kt`, `DX:` = `ui/configurer/DxClusterTab.kt` of v1.1.1).
/// Keys are the Czech originals the app translates with `tr`; literals Kotlin does not translate are marked so.
public enum SettingsTexts {

    /// `CD:569` — after a successful commit.
    public static let saved = "Nastavení uloženo"
    /// `CD:566` — the write failed (`%s` = the exception message).
    public static let saveFailed = "Uložení nastavení selhalo: %s"
    /// `CD:607` — writing the band plan / digi frequencies failed (`%s` = the message).
    public static let bandDataSaveFailed = "Uložení bandplánu/digi selhalo: %s"
    /// `CD:610` — the CAT disconnect reason before the reconnect.
    public static let catReconfigured = "překonfigurováno"
    /// `AS:2511` — the prefix of a failed profile load (not translated; followed by the message).
    public static let profileFailurePrefix = "Profil: "
    /// `AS:2521` — after a profile load (`%s` = the profile name).
    public static let profileLoaded = "Profil „%s“ načten — rig a síťová spojení připoj znovu (nebo restartuj aplikaci)"

    /// `KT:64` — shown in place of the keys while capturing.
    public static let capturePrompt = "stiskni klávesy… (Esc zruší)"
    /// `KT:76` — a combination that is not allowed (`%s` = `KeyCombo.format()`).
    public static let keyNotAllowed = "%s nejde — bez Ctrl/Alt/Cmd by přebila psaní (povolené jsou F-klávesy, ; a ')"
    /// `KT:56` — an action without a key (not translated).
    public static let noKey = "—"
    /// `KT:91` — the conflict prefix (not translated).
    public static let conflictPrefix = "koliduje: "

    /// `DX:164-165` — the hint under a blacklist editor.
    public static let blacklistSpottersHint = "Spoty těchto spotterů se nezobrazují v bandmapě."
    public static let blacklistCallsHint = "Spoty těchto volaček se nezobrazují v bandmapě."

    /// `BlacklistEditor` picks its hint by `title.contains("spot")` over the **translated** title (Kotlin String
    /// `contains`, case-sensitive, by UTF-16 units). Kept as in Kotlin: in English the spotter title
    /// "Spotter blacklist" has a capital `S`, so the spotter editor shows the callsign hint.
    public static func blacklistHintKey(translatedTitle: String) -> String {
        let found: Bool = JavaText.indexOf(Array(translatedTitle.utf16), Array("spot".utf16)) >= 0
        return found ? blacklistSpottersHint : blacklistCallsHint
    }
}
