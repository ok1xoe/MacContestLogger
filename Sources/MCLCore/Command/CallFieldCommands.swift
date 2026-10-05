/// Recognition of text commands in the call field (Java `command.CallFieldCommands`). The set is based on N1MM+
/// (frequency, modes, WIPELOG, OPON, VERSION) and DXLog (aliases CLEARLOG/LOGIN/VER, EXPORT, IMPORT,
/// WRITELOG/MAKELOG, SETUP, NETON/NETOFF, ESM/NOESM, AUTORSP/NOAUTRSP, SWAP, SPOTME), N1MM TOUR, BONUS,
/// ROVERQTH, COUNTYLINE and own SPLIT/NOSPLIT; the second VFO frequency (`/14030`) and split via Ctrl+Enter
/// as in N1MM + own RESCORE.
///
/// Frequency is entered in kHz as in N1MM:
/// - full frequency (`14025.1`, also with a decimal comma) — valid if it lies within a band;
/// - partial relative to the lower edge of the current band (`025.1` on 20 m = 14 025.1; `0` = band start);
/// - signed offset (`+2`, `-3`).
///
/// A callsign is never a command: keywords are compared as the whole field content (OPONX, CW1A stay
/// callsigns) and a purely numeric entry cannot be a callsign.
///
/// Java pitfalls kept here (measured, a maintainer-only probe):
/// - numbers with ASCII digits only (`\d`), incomplete decimals (`1.`, `.5`) are not commands;
/// - kHz → Hz via `BigDecimal` with `HALF_UP` over the decimal notation; outside `long` →
///   `ArithmeticException: Overflow` (typed error `JavaArithmeticError`, thrown even with Ctrl+Enter);
/// - the sum of frequency and offset (also band lower edge and partial frequency) **silently wraps** in `long`;
/// - `isBlank` (Unicode white) before `trim` (only ≤ U+0020): NBSP and U+2003 are not trimmed and the word is not recognised;
/// - upper case `toUpperCase(Locale.ROOT)` (`ı` → `I`, `ſ` → `S`), keywords by UTF-16 units
///   (KELVIN SIGN ≠ `K`); `OPON`/`LOGIN` are recognised earlier by `OperatorCommand` with the default locale (see there).
public enum CallFieldCommands {

    /// Commands that take an argument after a space (the space bar in the call field does not jump to the exchange for them).
    /// Java `Set.of(…)`: equality by UTF-16 units (`JavaStringKey`), not canonical; query
    /// `isArgumentKeyword(_:)`.
    static let argumentKeywords: Set<JavaStringKey> = [
        JavaStringKey("OPON"), JavaStringKey("LOGIN"), JavaStringKey("TOUR"), JavaStringKey("BONUS"),
        JavaStringKey("ROVERQTH"), JavaStringKey("COUNTYLINE"), JavaStringKey("SPOTME"), JavaStringKey("RIT"),
        JavaStringKey("SCRIPT"),
    ]

    /// Java `ARGUMENT_KEYWORDS.contains(word)`.
    public static func isArgumentKeyword(_ word: String) -> Bool {
        argumentKeywords.contains(JavaStringKey(word))
    }

    private static func compile(_ pattern: String) -> JavaRegex {
        do {
            return try JavaRegex(pattern)
        } catch {
            preconditionFailure("vzor \(pattern) je pevný a platný: \(error)")
        }
    }

    /// `[+-]?\d+(?:[.,]\d+)?` — `\d` ASCII only.
    private static let number: JavaRegex = compile("[+-]?\\d+(?:[.,]\\d+)?")

    /// Argument of `RIT`: `[+-]?\d{1,5}`.
    private static let ritArgument: JavaRegex = compile("[+-]?\\d{1,5}")

    private static let modes: [JavaStringKey: Mode] = {
        // The mode in the logbook is only SSB; the sideband is chosen by CAT from the frequency
        // (conventionally LSB below 10 MHz, USB above), same as N1MM for the SSB command.
        let pairs: [(String, Mode)] = [
            ("CW", .cw), ("SSB", .ssb), ("USB", .ssb), ("LSB", .ssb), ("AM", .am), ("FM", .fm),
            ("RTTY", .rtty), ("PSK", .psk), ("PSK31", .psk), ("PSK63", .psk), ("PSK125", .psk),
            ("PSK250", .psk), ("FT8", .ft8), ("FT4", .ft4), ("JT65", .jt65), ("DIGITAL", .digital),
            ("DIGI", .digital),
        ]
        return keyed(pairs)
    }()

    private static let keywords: [JavaStringKey: CallFieldCommand] = {
        var pairs: [(String, CallFieldCommand)] = [
            ("WIPELOG", .wipeLog), ("CLEARLOG", .wipeLog), ("VERSION", .version), ("VER", .version),
            ("EXPORT", .exportAdif), ("IMPORT", .importLog), ("WRITELOG", .exportCabrillo),
            ("MAKELOG", .exportCabrillo), ("RESCORE", .rescore),
            ("AUTORSP", .autoRunSp(enabled: true)), ("AUTORSPON", .autoRunSp(enabled: true)),
            ("NOAUTRSP", .autoRunSp(enabled: false)), ("NOAUTORSP", .autoRunSp(enabled: false)),
            ("AUTORSPOFF", .autoRunSp(enabled: false)),
            ("ESM", .esmOn), ("ESMON", .esmOn), ("NOESM", .esmOff), ("ESMOFF", .esmOff),
        ]
        pairs.append(contentsOf: actionKeywords)
        pairs.append(contentsOf: settingKeywords)
        pairs.append(contentsOf: vfoAndNetworkKeywords)
        return keyed(pairs)
    }()

    private static let actionKeywords: [(String, CallFieldCommand)] = {
        let pairs: [(String, CallFieldCommand.Action)] = [
            ("BCLOG", .broadcastLog), ("BYE", .exit), ("EXIT", .exit), ("QUIT", .exit),
            ("EXITNOW", .exitNow), ("QUITNOW", .exitNow), ("CLEARLOGNOW", .wipeLogNow),
            ("CLOSE", .closeContest), ("NEW", .newContest), ("OPEN", .openContest), ("COPYLOG", .copyLog),
            ("RELOAD", .reload), ("RELOADNOW", .reload), ("REOPEN", .reopen), ("REOPENNOW", .reopen),
            ("DEBUGCAT", .debugCat), ("RESET", .resetInterfaces), ("BEACONS", .loadBeacons),
            ("OPOFF", .logout), ("LOGOUT", .logout),
        ]
        return pairs.map { ($0.0, CallFieldCommand.appAction(action: $0.1)) }
    }()

    private static let settingKeywords: [(String, CallFieldCommand)] = [
        ("RPT", .toggle(setting: .cqRepeat, on: true)), ("NORPT", .toggle(setting: .cqRepeat, on: false)),
        ("WORKDUPE", .toggle(setting: .workDupes, on: true)), ("WORKDUPEON", .toggle(setting: .workDupes, on: true)),
        ("NOWORKDUPE", .toggle(setting: .workDupes, on: false)),
        ("WORKDUPEOFF", .toggle(setting: .workDupes, on: false)),
        ("POSTCONTEST", .toggle(setting: .postContest, on: true)),
        ("NOPOSTCONTEST", .toggle(setting: .postContest, on: false)),
        ("AUTORELOAD", .toggle(setting: .autoReload, on: true)),
        ("NOAUTORELOAD", .toggle(setting: .autoReload, on: false)),
        ("RUNSP", .autoRunSp(enabled: true)), ("RUNSPON", .autoRunSp(enabled: true)),
        ("NORUNSP", .autoRunSp(enabled: false)), ("RUNSPOFF", .autoRunSp(enabled: false)),
        ("FULLABBREV", .cutNumbers(style: .tauedn)), ("PROABBREV", .cutNumbers(style: .tn)),
        ("SEMIABBREV", .cutNumbers(style: .allT)), ("NOABBREV", .cutNumbers(style: nil)),
        ("MSGS", .openSettingsTab(tabKey: "function-keys")), ("MESSAGES", .openSettingsTab(tabKey: "function-keys")),
        ("AMSGS", .openSettingsTab(tabKey: "function-keys")), ("AMESSAGES", .openSettingsTab(tabKey: "function-keys")),
        ("WKEY", .openSettingsTab(tabKey: "winkey")), ("WKSETUP", .openSettingsTab(tabKey: "winkey")),
        ("NETCONFIG", .openSettingsTab(tabKey: "cluster")),
    ]

    private static let vfoAndNetworkKeywords: [(String, CallFieldCommand)] = [
        ("NOTOUR", .tourOff), ("TOUROFF", .tourOff), ("NOCOUNTYLINE", .countyLineOff),
        ("SPLIT", .split(txFreqHz: 0)), ("NOSPLIT", .splitOff), ("SPLITOFF", .splitOff), ("SWAP", .swapVfo),
        ("NORIT", .rit(offsetHz: 0)), ("RITOFF", .rit(offsetHz: 0)), ("RITCLEAR", .rit(offsetHz: 0)),
        ("CLEARRIT", .rit(offsetHz: 0)), ("SETUP", .openSetup), ("NETON", .networkOn), ("NET", .networkOn),
        ("NETOFF", .networkOff), ("NONET", .networkOff),
    ]

    private static func keyed<Value>(_ pairs: [(String, Value)]) -> [JavaStringKey: Value] {
        var map: [JavaStringKey: Value] = [:]
        for (key, value) in pairs {
            precondition(map[JavaStringKey(key)] == nil, "duplicitní klíčové slovo \(key)")
            map[JavaStringKey(key)] = value
        }
        return map
    }

    /// Recognises a command in the content of the call field; `nil` = an ordinary callsign. Java `parse(input, freq)`
    /// is a call without `otherVfoHz`/`ctrlEnter`.
    ///
    /// - `/14030`, `/025`, `/+2` – frequency of the second VFO (relative to it when known, otherwise
    ///   to the first);
    /// - a frequency confirmed with **Ctrl+Enter** – split, the entered frequency is the transmit one (`+2` = 2 kHz higher).
    ///
    /// - Parameters:
    ///   - currentFreqHz: current frequency (0 = unknown) — the base for relative QSY
    ///   - otherVfoHz: frequency of the second VFO (0 = unknown)
    ///   - ctrlEnter: confirmed with Ctrl+Enter
    /// - Throws: `JavaArithmeticError("Overflow")` when the kHz after conversion to Hz do not fit in `long`
    ///   (Java `ArithmeticException` from `longValueExact`).
    public static func parse(_ input: String?, currentFreqHz: Int64, otherVfoHz: Int64 = 0,
                             ctrlEnter: Bool = false) throws(JavaArithmeticError) -> CallFieldCommand? {
        guard let input, !JavaText.isBlank(input) else { return nil }
        if let login = OperatorCommand.parse(input) {
            return .login(operator: login.operator)
        }
        let text: String = JavaText.toUpperCase(JavaText.trim(input))
        if text.utf16.first == 0x2F { // '/'
            let rest: String = String(text.unicodeScalars.dropFirst())
            if number.matches(rest) {
                let base: Int64 = otherVfoHz > 0 ? otherVfoHz : currentFreqHz
                let command: CallFieldCommand = try frequency(rest, currentFreqHz: base)
                if case .qsy(let hz) = command { return .otherVfo(freqHz: hz) }
                return command
            }
        }
        if number.matches(text) {
            let command: CallFieldCommand = try frequency(text, currentFreqHz: currentFreqHz)
            if ctrlEnter, case .qsy(let hz) = command { return .split(txFreqHz: hz) }
            return command
        }
        if let command = withArgument(text) {
            return command
        }
        if let mode = modes[JavaStringKey(text)] {
            return .changeMode(mode: mode)
        }
        return keywords[JavaStringKey(text)]
    }

    /// A command with an argument (`TOUR 1200/30`, `BONUS K1A,K1B`…), otherwise `nil`. Java:
    /// `text.split("\\s+", 2)`, argument `trim()`.
    private static func withArgument(_ text: String) -> CallFieldCommand? {
        let parts: [String] = JavaText.split(text, regex: OperatorCommand.whitespace, limit: 2)
        let arg: String = parts.count > 1 ? JavaText.trim(parts[1]) : ""
        switch JavaStringKey(parts[0]) {
        case JavaStringKey("TOUR"): return .setTour(params: arg)
        case JavaStringKey("BONUS"): return .bonusStations(calls: arg)
        case JavaStringKey("ROVERQTH"): return .roverQth(county: arg)
        case JavaStringKey("COUNTYLINE"): return .countyLine(counties: arg)
        case JavaStringKey("SPOTME"): return .spotMe(comment: arg)
        case JavaStringKey("SCRIPT"):
            return arg.isEmpty
                ? .invalid(message: "SCRIPT: zadej jméno skriptu (soubor scripts/<jméno>.txt)")
                : .runScript(name: arg)
        case JavaStringKey("RIT"):
            guard ritArgument.matches(arg), let hz = JavaInteger.parseInt(JavaText.replace(arg, "+", "")) else {
                return .invalid(message: "RIT: zadej posun v Hz, např. RIT 120 nebo RIT -50")
            }
            return .rit(offsetHz: hz)
        default:
            return nil
        }
    }

    /// `text` matches `number` (ASCII, at most one `.`/`,`).
    private static func frequency(_ text: String, currentFreqHz: Int64) throws(JavaArithmeticError)
        -> CallFieldCommand {
        let sign: UInt16 = text.utf16.first ?? 0
        let offsetHz: Int64 = try toHz(text)
        let currentBand: Band? = currentFreqHz > 0 ? Band.from(frequencyHz: Int(currentFreqHz)) : nil

        if sign == 0x2B || sign == 0x2D { // '+' / '-'
            if currentFreqHz <= 0 {
                return .invalid(message: "Posun \(text) kHz: aktuální frekvence není známá")
            }
            let target: Int64 = JavaMath.addLong(currentFreqHz, offsetHz)
            return Band.from(frequencyHz: Int(target)) != nil
                ? .qsy(freqHz: target)
                : .invalid(message: "Posun \(text) kHz vede mimo pásmo")
        }
        // A full frequency takes precedence — 1830 on 20 m is 160 m, not 14 000 + 1830.
        if Band.from(frequencyHz: Int(offsetHz)) != nil {
            return .qsy(freqHz: offsetHz)
        }
        if let band = currentBand {
            let target: Int64 = JavaMath.addLong(Int64(band.lowHz), offsetHz)
            if target <= Int64(band.highHz) {
                return .qsy(freqHz: target)
            }
        }
        return .invalid(message: "\(text) kHz neleží v žádném pásmu")
    }

    /// kHz written with a dot or a comma → Hz without double rounding errors:
    /// `new BigDecimal(khz.replace(',', '.')).movePointRight(3).setScale(0, HALF_UP).longValueExact()`.
    private static func toHz(_ khz: String) throws(JavaArithmeticError) -> Int64 {
        let overflow = JavaArithmeticError(message: "Overflow")
        // `number` guarantees a valid notation with a scale in `int`, so `BigDecimal` and `movePointRight`
        // pass; only `longValueExact` can fail (after `setScale(0)` only overflow).
        guard let decimal = JavaBigDecimal(JavaText.replace(khz, ",", ".")),
              let hz = decimal.movePointRight(3)?.setScaleZeroHalfUp() else {
            preconditionFailure("číslo prošlo vzorem frekvence: \(khz)")
        }
        guard let value = hz.longValueExact() else { throw overflow }
        return value
    }
}
