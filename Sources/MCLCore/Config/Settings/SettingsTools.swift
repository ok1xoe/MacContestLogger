import Foundation

/// The pure helpers behind the tools of the Settings tabs (`HW:` = `ui/configurer/HardwareTab.kt`, `MT:` =
/// `ui/configurer/ModeTabs.kt`, `CT:` = `ui/configurer/ContestTab.kt`, `VK:` = `ui/configurer/VoiceKeyerTabs.kt` of
/// v1.1.1). Measured by a maintainer-only probe.
public enum SettingsTools {

    // MARK: - rig scan (HW:205-250)

    /// `HW:220` — the status when a scan starts (not translated).
    public static let scanning = "Skenuji…"
    /// `HW:229` — a probed candidate (`%s` = label, baud).
    public static let probing = "Zkouším %s @ %s…"
    /// `HW:243` — the scan was stopped (not translated).
    public static let scanStopped = "Scan zastaven"
    /// `HW:243` — no candidate answered (not translated).
    public static let nothingAnswered = "Nic se neozvalo"
    /// The bauds the scan tries (`HW:65` `BAUD_RATES`).
    public static let scanBauds: [Int] = ConfigurerCatalogs.baudRates

    /// `HW:241` — the found rig (not translated): `"Nalezeno: <label> @ <baud> baud (<freqHz / 1000.0> kHz)"`, the
    /// frequency as Kotlin's `Double` template (`Double.toString`).
    public static func found(_ outcome: RigScanner.Outcome) -> String {
        let khz: String = JavaDouble.toString(Double(outcome.freqHz) / 1000.0)
        let candidate: RigScanner.Candidate = outcome.candidate
        return "Nalezeno: \(candidate.label) @ \(candidate.baud) baud (\(khz) kHz)"
    }

    // MARK: - fldigi probe (MT:86-97)

    /// `MT:88` — while the probe runs.
    public static let fldigiProbing = "zkouším…"
    /// `MT:93` — the probe failed (`%s` = the exception message, `null` when it has none).
    public static let fldigiUnavailable = "nedostupné: %s"
    /// The port when the field is not a number (`MT:89` `toIntOrNull() ?: 7362`).
    public static let fldigiDefaultPort = 7362

    /// `MT:92` — the answer of fldigi (not translated).
    public static func fldigiAnswer(version: String, modem: String) -> String {
        "fldigi \(version), modem \(modem)"
    }

    /// `MT:89` — Kotlin `fldigiPort.toIntOrNull() ?: 7362` (no trimming).
    public static func fldigiPort(_ text: String) -> Int {
        KotlinNumber.toIntOrNull(text).map { Int($0) } ?? fldigiDefaultPort
    }

    /// Java `getMessage()` of an error of `FldigiClient` (`nil` = Java `null`).
    public static func fldigiErrorMessage(_ error: any Error) -> String? {
        switch error {
        case let failure as XmlRpc.Failure:
            return failure.message
        case let illegal as JavaIllegalArgumentError:
            return illegal.message
        case let number as JavaNumberFormatError:
            return number.message
        default:
            return JavaThrowables.describe(error).message
        }
    }

    // MARK: - audio devices (VK:36-46)

    /// `VK:36` — the first entry of both device lists (translated at rendering).
    public static let systemDefaultDevice = "Výchozí systémové"

    /// The device names after `tr("Výchozí systémové")`: `SoundCard.outputDevices()`/`inputDevices()` without Java's
    /// pseudo-mixer `Default Audio Device` (it means the same system default, so the list does not show it twice —
    /// a configured `Default Audio Device` still plays to the system default).
    public static func deviceChoices(_ devices: [String]) -> [String] {
        devices.filter { $0 != CoreAudioDevices.defaultDeviceName }
    }

    // MARK: - counts (CT:28-191)

    /// `CT:29-32` — `countYaml(contests/ when it is a directory, otherwise the root)`; `contestDataDir` as a Java
    /// `Path.of` (an empty text is the working directory).
    public static func contestYamlCount(contestDataDir: String) -> Int {
        let sub: String = resolve(contestDataDir, "contests")
        return yamlCount(ContestDataPaths.isDirectory(URL(fileURLWithPath: sub)) ? sub : root(contestDataDir))
    }

    /// `CT:33-35` — `countYaml(<root>/multipliers)`.
    public static func multiplierYamlCount(contestDataDir: String) -> Int {
        yamlCount(resolve(contestDataDir, "multipliers"))
    }

    /// `CT:72, 151-154` — blank → 0, otherwise `ScpDatabase.load(path).size` (a missing or unreadable file is empty).
    public static func scpCount(_ path: String) -> Int {
        if KotlinStrings.isBlank(path) {
            return 0
        }
        return ScpDatabase.load(path).size
    }

    /// `CT:120-123` — blank → 0, otherwise `CallHistory.load(path).size`.
    public static func callHistoryCount(_ path: String) -> Int {
        if KotlinStrings.isBlank(path) {
            return 0
        }
        return CallHistory.load(path).size
    }

    /// `CT:165-168` `countYaml`: the entries of the directory (not recursive, hidden files and directories
    /// included) whose name ends in `.yaml`; not a directory → 0. An unreadable directory gives 0 (Kotlin's
    /// `Files.list` throws inside the composition).
    static func yamlCount(_ dir: String) -> Int {
        let path: String = dir.isEmpty ? "." : dir
        guard ContestDataPaths.isDirectory(URL(fileURLWithPath: path)),
              let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return 0
        }
        let suffix: [UInt16] = Array(".yaml".utf16)
        return names.filter { name in
            let units: [UInt16] = Array(name.utf16)
            return units.count >= suffix.count && Array(units.suffix(suffix.count)) == suffix
        }.count
    }

    /// Java `Path.of(dir).resolve(name)` as a file-system path (an empty `dir` is the working directory).
    private static func resolve(_ dir: String, _ name: String) -> String {
        dir.isEmpty ? name : dir + "/" + name
    }

    private static func root(_ dir: String) -> String {
        dir.isEmpty ? "." : dir
    }

    // MARK: - menu file (MT:192-258)

    /// `MT:230` — the built-in menu was written (`%s` = the path).
    public static let menuCreated = "Vytvořeno: %s"
    /// `MT:231` — the file exists and was left alone.
    public static let menuExists = "Soubor už existuje, nechal jsem ho být. Uprav ho v textovém editoru."
    /// `MT:232` — no data directory.
    public static let menuNoDataDir = "Datový adresář není dostupný."
    /// `MT:235` — writing failed (`%s` = the exception message).
    public static let menuWriteFailed = "Zápis se nepovedl: %s"
    /// `MT:248` — after „Načíst menu znovu".
    public static let menuReloaded = "Menu načteno znovu."
    /// `AS:2672` — the status after a reload that found the user's file.
    public static let menuStatusUser = "Menu načteno z menu.json"
    /// `AS:2675` — the status after a reload without a user file.
    public static let menuStatusBuiltIn = "Menu: vlastní menu.json není, platí vestavěné"
}
