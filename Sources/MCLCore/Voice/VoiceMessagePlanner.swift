/// Conversion of the text of an SSB F-key message (N1MM+ format) to a list of wav files to play (Java
/// `voice/VoiceMessagePlanner`).
///
/// The text is a comma-separated list of items:
/// - a wav file name relative to the wav directory; `{OPERATOR}` and `{WAVDIR}` (also `{operator}`, not
///   `{Operator}`) are replaced by the operator callsign, backslashes from N1MM files work too;
/// - `!` the other station's callsign, `#` serial number, `*`/`{MYCALL}` my callsign, `@` frequency in kHz —
///   assembled from recorded letters and digits in the letters directory, a recorded snippet (`DL1.wav`) takes precedence;
/// - `[text]` (longer than 2 characters) is spoken by speech synthesis;
/// - control macros are performed, not played (same set and meaning as in CW, `CwMessageBuilder`): `{LOG}`, `{WIPE}`,
///   `{RUN}`, `{S&P}`, `{CLEARRIT}`/`{RITCLEAR}`, `{CQFREQ}`, `{NOSPLIT}`; `{F1}`…`{F12}` insert another F-key's
///   message (at most 3 levels); `{END}` ends the message (the rest is ignored); any other `{…}` item is reported
///   in `unknownMacros` and never looked up as a file. An action runs in message order: after the audio before it.
///
/// Paths are Java `Path` (`JavaPath`): `resolve` + `normalize` (`../../cq3.wav` over `/wav` →
/// `/cq3.wav`), a missing message file is reported relative to wav (`a//b.wav` → `a/b.wav`), a missing
/// letter with the full path. Lengths, positions and comparisons by UTF-16 units like Java;
/// `toUpperCase(Locale.ROOT)` = Swift `uppercased()` (port convention).
public enum VoiceMessagePlanner {

    /// Data for macros. Java takes `null` strings; the app always passes text.
    public struct Context: Equatable, Sendable {
        public var operatorCall: String
        public var myCall: String
        public var hisCall: String
        public var serial: Int32
        public var freqHz: Int64
        /// Texts F1…F12 of the current set for `{F1}`…; missing item = "".
        public var functionKeys: [String]

        public init(operatorCall: String, myCall: String, hisCall: String, serial: Int32, freqHz: Int64,
                    functionKeys: [String] = []) {
            self.functionKeys = functionKeys
            self.operatorCall = operatorCall
            self.myCall = myCall
            self.hisCall = hisCall
            self.serial = serial
            self.freqHz = freqHz
        }
    }

    /// One step of a message, in message order.
    public enum Step: Equatable, Sendable {
        /// Audio files played in a row.
        case play([JavaPath])
        /// A control macro; performed after the audio before it has finished.
        case action(CwMessage.Action)
    }

    /// Files in playback order + those that are missing (paths for reporting), the same as `steps` (audio and control
    /// macros in message order) and the macros that are not known.
    public struct Plan: Equatable, Sendable {
        public var files: [JavaPath]
        public var missing: [String]
        public var steps: [Step]
        public var unknownMacros: [String]

        public init(files: [JavaPath], missing: [String], steps: [Step]? = nil, unknownMacros: [String] = []) {
            self.files = files
            self.missing = missing
            self.steps = steps ?? (files.isEmpty ? [] : [.play(files)])
            self.unknownMacros = unknownMacros
        }

        /// The actions before any audio: performed at once, before the transmitter is keyed.
        public var leadingActions: [CwMessage.Action] {
            var out: [CwMessage.Action] = []
            for step in steps {
                guard case .action(let action) = step else { break }
                out.append(action)
            }
            return out
        }

        /// The steps from the first audio on (what the voice keyer plays).
        public var playSteps: [Step] {
            Array(steps.drop { if case .action = $0 { true } else { false } })
        }
    }

    private static let actions: [String: CwMessage.Action] = [
        "{LOG}": .log, "{WIPE}": .wipe, "{RUN}": .run, "{S&P}": .searchAndPounce,
        "{CLEARRIT}": .clearRit, "{RITCLEAR}": .clearRit, "{CQFREQ}": .cqFrequency, "{NOSPLIT}": .splitOff,
    ]

    /// Items of a message with `{F1}`…`{F12}` replaced by the items of that key (depth ≤ 2 as in CW; deeper stays
    /// and is reported as unknown).
    static func items(_ text: String, _ functionKeys: [String], depth: Int = 0) -> [String] {
        var out: [String] = []
        for raw in JavaText.split(text, unit: 0x2C) {
            let token = JavaText.trim(raw)
            if depth <= 2, let key = functionKeyIndex(token) {
                if key < functionKeys.count {
                    out.append(contentsOf: items(functionKeys[key], functionKeys, depth: depth + 1))
                }
            } else {
                out.append(token)
            }
        }
        return out
    }

    /// `{F1}`…`{F12}` (ASCII case-insensitive) → index from 0.
    private static func functionKeyIndex(_ token: String) -> Int? {
        let units = Array(token.utf16)
        guard units.count >= 4, units.first == 0x7B, units.last == 0x7D,
              units[1] == 0x46 || units[1] == 0x66,
              let n = Int(String(decoding: units[2..<(units.count - 1)], as: UTF16.self)),
              (1...12).contains(n), units.count == String(n).utf16.count + 3 else { return nil }
        return n - 1
    }

    /// A `{…}` item that is a macro (a single brace group), not a path with `{OPERATOR}`/`{WAVDIR}`.
    private static func isMacroToken(_ token: String) -> Bool {
        let units = Array(token.utf16)
        guard units.count >= 2, units.first == 0x7B, units.last == 0x7D else { return false }
        return !units[1..<(units.count - 1)].contains(0x7B) && !units[1..<(units.count - 1)].contains(0x7D)
    }

    /// Speech synthesis (TTS) to a wav file; `nil` = synthesis failed (Java `Speech`).
    public typealias Speech = (String) -> JavaPath?

    /// Replacement of `{OPERATOR}`/`{WAVDIR}` and unification of path separators.
    static func expandPath(_ token: String, _ operatorCall: String?) -> String {
        let op: String
        if let operatorCall, !JavaText.isBlank(operatorCall) {
            op = JavaText.trim(operatorCall).uppercased()
        } else {
            op = ""
        }
        var out = JavaText.replace(token, "{OPERATOR}", op)
        out = JavaText.replace(out, "{WAVDIR}", op)
        out = JavaText.replace(out, "{operator}", op)
        return JavaText.replace(out, "\\", "/")
    }

    /// Directory (relative to wav, or absolute) with the operator substituted.
    public static func resolveDir(_ template: String, operatorCall: String?, wavDir: JavaPath)
        throws(JavaInvalidPathError) -> JavaPath {
        let path = try JavaPath(expandPath(template, operatorCall))
        return path.isAbsolute ? path : wavDir.resolve(path).normalize()
    }

    private static let nato: [String] = [
        "Alfa", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliett",
        "Kilo", "Lima", "Mike", "November", "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform",
        "Victor", "Whiskey", "X-ray", "Yankee", "Zulu",
    ]

    /// NATO spelling of callsigns and numbers for TTS (in English, as spelled on the band).
    static func phonetic(_ text: String?) -> String {
        var out = ""
        for unit in (text ?? "").uppercased().utf16 {
            switch unit {
            case 0x41...0x5A: out += nato[Int(unit - 0x41)] + " "
            case 0x30...0x39: out += String(Character(Unicode.Scalar(unit)!)) + " "
            case 0x2F: out += "stroke "
            case 0x2E: out += "point "
            default: break
            }
        }
        return JavaText.trim(out)
    }

    /// Text of the `[..]` item for TTS with macros substituted (callsigns spelled out).
    static func ttsText(_ inner: String, _ ctx: Context) -> String {
        var out = JavaText.replace(inner, "!", " " + phonetic(ctx.hisCall) + " ")
        out = JavaText.replace(out, "{MYCALL}", " " + phonetic(ctx.myCall) + " ")
        out = JavaText.replace(out, "*", " " + phonetic(ctx.myCall) + " ")
        out = JavaText.replace(out, "#", " " + phonetic(String(ctx.serial)) + " ")
        out = JavaText.replace(out, "@", " " + phonetic(frequency(ctx.freqHz)) + " ")
        return JavaText.trim(collapseRegexSpaces(out))
    }

    /// Java `replaceAll("\\s+", " ")` — `\s` in Java is only ASCII `[ \t\n\x0B\f\r]`.
    private static func collapseRegexSpaces(_ text: String) -> String {
        var out: [UInt16] = []
        var inSpace = false
        for unit in text.utf16 {
            if JavaChar.isRegexSpace(unit) {
                if !inSpace { out.append(0x20) }
                inSpace = true
            } else {
                out.append(unit)
                inSpace = false
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// Builds the file list; an item `[text]` is spoken by speech synthesis (`speech`).
    ///
    /// Throws like Java: `JavaInvalidPathError` for an item with NUL (`Path.of`), `JavaIllegalArgumentError`
    /// from `relativize` when a relative `wavDir` contains `..` that cannot be subtracted.
    public static func plan(_ text: String?, ctx: Context, wavDir: JavaPath, lettersDir: JavaPath,
                            exists: (JavaPath) -> Bool, speech: Speech? = nil) throws -> Plan {
        var files: [JavaPath] = []
        var missing: [String] = []
        var steps: [Step] = []
        var unknown: [String] = []
        var flushed = 0
        guard let text else {
            return Plan(files: files, missing: missing)
        }
        for token in items(text, ctx.functionKeys) {
            if token.isEmpty || JavaChar.equalsIgnoreCase(token, "empty.wav") {
                continue
            }
            let macro = token.uppercased()
            if macro == "{END}" {
                break
            }
            if let action = actions[macro] {
                if files.count > flushed {
                    steps.append(.play(Array(files[flushed...])))
                    flushed = files.count
                }
                steps.append(.action(action))
                continue
            }
            if isMacroToken(token) && !["{MYCALL}", "{OPERATOR}", "{WAVDIR}"].contains(macro) {
                unknown.append(macro)
                continue
            }
            let units = Array(token.utf16)
            if units.first == 0x5B && units.last == 0x5D && units.count > 2 { // "[" … "]"
                let inner = String(decoding: units[1..<(units.count - 1)], as: UTF16.self)
                let say = ttsText(inner, ctx)
                if let path = speech?(say) {
                    files.append(path)
                } else {
                    missing.append("TTS: " + say)
                }
                continue
            }
            switch token.uppercased() {
            case "!": voice(ctx.hisCall, lettersDir, exists, &files, &missing)
            case "#": voice(String(ctx.serial), lettersDir, exists, &files, &missing)
            case "*", "{MYCALL}": voice(ctx.myCall, lettersDir, exists, &files, &missing)
            case "@": voice(frequency(ctx.freqHz), lettersDir, exists, &files, &missing)
            default:
                let rel = expandPath(token, ctx.operatorCall)
                let relPath = try JavaPath(rel)
                let path = relPath.isAbsolute ? relPath : wavDir.resolve(relPath).normalize()
                if exists(path) {
                    files.append(path)
                } else {
                    missing.append(relPath.isAbsolute ? rel : try wavDir.relativize(path).description)
                }
            }
        }
        if files.count > flushed {
            steps.append(.play(Array(files[flushed...])))
        }
        return Plan(files: files, missing: missing, steps: steps, unknownMacros: unknown)
    }

    /// Where to record a message (N1MM "Recording on the Fly"): only when the message plays exactly one
    /// `.wav` file and nothing else — a composite message cannot be recorded in one recording.
    public static func recordTarget(_ text: String?, operatorCall: String?, wavDir: JavaPath)
        throws(JavaInvalidPathError) -> JavaPath? {
        guard let text else { return nil }
        var tokens: [String] = []
        for raw in JavaText.split(text, unit: 0x2C) where !JavaText.isBlank(raw) {
            tokens.append(JavaText.trim(raw))
        }
        guard tokens.count == 1 else { return nil }
        let token = tokens[0]
        let lower = Array(JavaText.toLowerCase(token).utf16)
        let suffix = Array(".wav".utf16)
        if lower.count < suffix.count || Array(lower.suffix(suffix.count)) != suffix
            || JavaChar.equalsIgnoreCase(token, "empty.wav") {
            return nil
        }
        let rel = try JavaPath(expandPath(token, operatorCall))
        return rel.isAbsolute ? rel : wavDir.resolve(rel).normalize()
    }

    /// Why a message text has no single wav file to record into (Settings → Function Keys).
    public enum NotRecordable: Equatable, Sendable {
        /// Empty text or `empty.wav`: the message transmits nothing.
        case empty
        /// More than one item: a recording replaces exactly one file.
        case several
        /// `[text]`: spoken by speech synthesis, no recording involved.
        case speech
        /// `!`, `#`, `*`, `@`, `{MYCALL}` or a control macro such as `{WIPE}`, `{LOG}`, `{RUN}`: not a wav file.
        case macro
        /// A single item that is not a `.wav` name.
        case notWav
        /// The path uses `{OPERATOR}` but no operator callsign is set, so the folder would be empty.
        case operatorMissing
        /// The path has a NUL character or otherwise cannot be a path.
        case invalidPath
    }

    /// The result of `recordability`.
    public enum RecordTarget: Equatable, Sendable {
        case target(JavaPath)
        case unavailable(NotRecordable)
    }

    /// Control macros that run an action instead of playing audio (they may stand beside one audio file).
    static func isControlMacro(_ item: String) -> Bool {
        let name = item.uppercased()
        switch name {
        case "{LOG}", "{WIPE}", "{RUN}", "{S&P}", "{END}", "{CLEARRIT}", "{RITCLEAR}", "{CQFREQ}", "{NOSPLIT}":
            return true
        default:
            guard name.hasPrefix("{F"), name.hasSuffix("}"), let number = Int(name.dropFirst(2).dropLast()) else {
                return false
            }
            return (1...12).contains(number) && !name.dropFirst(2).dropLast().hasPrefix("0")
        }
    }

    /// The file the voice keyer plays for a message with one audio file item, beside any control macros (`recordTarget`), or the reason there
    /// is none. Settings records, picks and deletes this file, so the voice keyer finds it under the same name.
    public static func recordability(_ text: String?, operatorCall: String?, wavDir: JavaPath) -> RecordTarget {
        guard let text, !JavaText.isBlank(text) else { return .unavailable(.empty) }
        var tokens: [String] = []
        var sawControl = false
        for raw in JavaText.split(text, unit: 0x2C) where !JavaText.isBlank(raw) {
            let item = JavaText.trim(raw)
            if isControlMacro(item) {
                sawControl = true
            } else {
                tokens.append(item)
            }
        }
        guard let token = tokens.first else { return .unavailable(sawControl ? .macro : .empty) }
        if tokens.count > 1 { return .unavailable(.several) }
        if JavaChar.equalsIgnoreCase(token, "empty.wav") { return .unavailable(.empty) }
        let units = Array(token.utf16)
        if units.first == 0x5B && units.last == 0x5D && units.count > 2 { return .unavailable(.speech) }
        switch token.uppercased() {
        case "!", "#", "*", "@", "{MYCALL}": return .unavailable(.macro)
        default: break
        }
        let hasOperator = token.contains("{OPERATOR}") || token.contains("{WAVDIR}") || token.contains("{operator}")
        if hasOperator && (operatorCall.map { JavaText.isBlank($0) } ?? true) {
            return .unavailable(.operatorMissing)
        }
        let expanded = expandPath(token, operatorCall)
        if expanded.contains("{") { return .unavailable(.macro) }
        do {
            if let target = try recordTarget(token, operatorCall: operatorCall, wavDir: wavDir) {
                return .target(target)
            }
        } catch {
            return .unavailable(.invalidPath)
        }
        return .unavailable(.notWav)
    }

    /// kHz with one decimal when non-zero: 14 250 500 Hz → "14250.5".
    static func frequency(_ freqHz: Int64) -> String {
        if freqHz <= 0 {
            return ""
        }
        let tenths = JavaMath.round(Double(freqHz) / 100.0)
        let khz = tenths / 10
        let dec = tenths % 10
        return dec == 0 ? String(khz) : String(khz) + "." + String(dec)
    }

    /// Splits text into recordings: the longest recorded snippet (at least 2 characters `[A-Z0-9]`), otherwise character by
    /// character. A trailing "/P" has its own `strokep.wav` if recorded.
    private static func voice(_ text: String, _ letters: JavaPath, _ exists: (JavaPath) -> Bool,
                              _ files: inout [JavaPath], _ missing: inout [String]) {
        let s = Array(JavaText.trim(text).uppercased().utf16)
        var i = 0
        while i < s.count {
            var matched = 0
            var end = s.count
            while end >= i + 2 {
                let fragment = s[i..<end]
                if fragment.allSatisfy(isUpperAlnum) {
                    let path = letters.resolve(fileName: String(decoding: fragment, as: UTF16.self) + ".wav")
                    if exists(path) {
                        files.append(path)
                        matched = end - i
                        break
                    }
                }
                end -= 1
            }
            if matched > 0 {
                i += matched
                continue
            }
            if i + 2 == s.count && s[i] == 0x2F && s[i + 1] == 0x50 { // "/P" at the end
                let path = letters.resolve(fileName: "strokep.wav")
                if exists(path) {
                    files.append(path)
                    i += 2
                    continue
                }
            }
            let name: String?
            switch s[i] {
            case 0x2F: name = "stroke"
            case 0x3F: name = "query"
            case 0x2E: name = "point"
            default: name = JavaChar.isLetterOrDigit(s[i]) ? String(decoding: [s[i]], as: UTF16.self) : nil
            }
            i += 1
            guard let name else { continue }
            let path = letters.resolve(fileName: name + ".wav")
            if exists(path) {
                files.append(path)
            } else {
                missing.append(path.description)
            }
        }
    }

    private static func isUpperAlnum(_ unit: UInt16) -> Bool {
        (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x30 && unit <= 0x39)
    }
}
