import Foundation

/// Scoring core of Java `cli/ScoreCheck.java` (v1.1.1): recomputing the score of a Cabrillo log
/// and comparing it with the claimed `CLAIMED-SCORE`. Only what the Java parity suite measures is converted —
/// `evaluate` and its helpers (header, `QSO:` line tokenizer, contest detection, own
/// locator), `Result` with the verdict and the DXCC source choice (`loadDxcc`). The CLI, histograms,
/// downloading and reports stay in Java.
///
/// Java behaviour that is copied:
/// - the log is read **strictly as UTF-8** (`Files.readString`); an invalid sequence = "cannot
///   load". A leading BOM stays a character, `stripBlank` removes it from the header;
/// - QSOs are written to `ContestSession.log` **in file order** (no sorting by time
///   as in `ContestReplay`) and **any error** of the session (`ContestSessionError` from `log`,
///   `ExpressionError` from `activeReceivedFields` and `score`) discards the whole log — `check` turns it
///   into the result of Java `evalSafe` (`Failure` carries the Java exception class);
/// - from the header only `CONTEST`, `CALLSIGN` and `CLAIMED-SCORE` are read; QSO date and time,
///   `CATEGORY-*`, `LOCATION`, `GRID-LOCATOR` and `X-QSO:` are not read;
/// - the session is without TOUR, without `ownQth`, without bonus stations and without QTC.
public enum ScoreCheck {

    /// Result of verifying one log. Port of the Java record `ScoreCheck.Result`.
    public struct Result: Equatable, Sendable {
        public let file: String
        public let contest: String?
        public let qsoCount: Int32
        public let qsoPoints: Int64
        public let multTotal: Int32
        public let multByGroup: JavaLinkedMap<Int32>
        public let computed: Int64
        public let claimed: Int64?
        public let pass: Bool
        public let unresolvedCalls: [String]
        public let error: String?

        public init(file: String, contest: String?, qsoCount: Int32, qsoPoints: Int64, multTotal: Int32,
                    multByGroup: JavaLinkedMap<Int32>, computed: Int64, claimed: Int64?, pass: Bool,
                    unresolvedCalls: [String], error: String?) {
            self.file = file
            self.contest = contest
            self.qsoCount = qsoCount
            self.qsoPoints = qsoPoints
            self.multTotal = multTotal
            self.multByGroup = multByGroup
            self.computed = computed
            self.claimed = claimed
            self.pass = pass
            self.unresolvedCalls = unresolvedCalls
            self.error = error
        }

        /// Deviation of the computed score from claimed in percent (`nil` when not possible). Java
        /// `100.0 * (computed - claimed) / claimed`: difference in `long` (wraps around), then `double`.
        public var diffPct: Double? {
            guard let claimed, claimed != 0 else { return nil }
            return 100.0 * Double(computed &- claimed) / Double(claimed)
        }

        /// Classification by two bounds: |deviation| up to `okPct` = OK, up to `failPct` = CLOSE, otherwise FAILED.
        public func verdict(okPct: Double, failPct: Double) -> Verdict {
            if pass {
                return .ok // exact match (even claimed == 0)
            }
            if error != nil {
                return .failed
            }
            guard let d = diffPct else { return .failed }
            let magnitude = Swift.abs(d)
            if magnitude <= okPct {
                return .ok
            }
            if magnitude <= failPct {
                return .close
            }
            return .failed
        }
    }

    /// Classification of the result by two bounds (Java `Verdict`).
    public enum Verdict: Equatable, Sendable {
        case ok, close, failed
    }

    /// An exception that in Java brings down the whole log (`evalSafe` catches it as `RuntimeException`).
    /// Unifies two error types of the session API (`ContestSessionError` from `log`, `ExpressionError`
    /// from `activeReceivedFields` and `score`) — `scoreCheck` does not distinguish them, it discards the log on either.
    public struct Failure: Error, Equatable, Sendable, CustomStringConvertible {
        /// Simple name of the Java exception class (`NumberFormatException`…) = error category
        /// for the gate. `StackOverflowError` and `UnsupportedPattern` are only
        /// Swift counterparts of places where Java fails differently, or not at all (see `init(_: ExpressionError)`).
        public let javaClass: String
        /// Exception text (`getMessage()`).
        public let message: String

        public init(javaClass: String, message: String) {
            self.javaClass = javaClass
            self.message = message
        }

        init(_ error: ContestSessionError) {
            switch error {
            case .expression(let e):
                self.init(e)
            case .exchange(let e):
                switch e.kind {
                case .numberFormat: self.init(javaClass: "NumberFormatException", message: e.message)
                case .patternSyntax: self.init(javaClass: "PatternSyntaxException", message: e.message)
                }
            case .multiplier(let e):
                switch e {
                case .failure, .invalidDefinition:
                    self.init(javaClass: "MultiplierException", message: e.message)
                case .emptyDefinition:
                    self.init(javaClass: "NullPointerException", message: e.message)
                case .invalidPattern:
                    self.init(javaClass: "PatternSyntaxException", message: e.message)
                }
            }
        }

        init(_ error: ExpressionError) {
            switch error.kind {
            case .illegalArgument: self.init(javaClass: "IllegalArgumentException", message: error.message)
            case .numberFormat: self.init(javaClass: "NumberFormatException", message: error.message)
            case .patternSyntax: self.init(javaClass: "PatternSyntaxException", message: error.message)
            // A pattern that the `JavaRegex` adapter does not convert — Java may accept it (Swift only).
            case .unsupportedPattern: self.init(javaClass: "UnsupportedPattern", message: error.message)
            // Java fails here with a `StackOverflowError`, which `evalSafe` does not catch (the whole run crashes).
            case .nestingTooDeep: self.init(javaClass: "StackOverflowError", message: error.message)
            }
        }

        public var description: String { javaClass + ": " + message }
    }

    /// Result of the whole `scoreCheck` path over one file: reading, `skipReason`
    /// and `evaluate` with the exception caught. Carries the tuple that the Java parity suite compares.
    public struct LogOutcome: Equatable, Sendable {
        public enum Status: String, Sendable {
            /// Score computed (`Result.error == nil`).
            case ok = "OK"
            /// Error reported by `evaluate` (missing / unknown contest, definition without `cabrillo`).
            case error = "ERR"
            /// An exception brought down the whole log (Java `evalSafe`); `exceptionClass` = category.
            case exception = "EXC"
            /// The file is not valid UTF-8 ("cannot load").
            case unreadable = "UNREADABLE"
        }

        public let status: Status
        /// For `.exception` this is Java `error(name, null, null, e.getMessage())`.
        public let result: Result
        /// `skipReason` of the content (`checklog` / `bez CLAIMED-SCORE`), computed even for errors;
        /// `nil` for an unreadable file.
        public let skipReason: String?
        /// Name of the Java exception class for `.exception`, otherwise `nil`.
        public let exceptionClass: String?

        public init(status: Status, result: Result, skipReason: String?, exceptionClass: String?) {
            self.status = status
            self.result = result
            self.skipReason = skipReason
            self.exceptionClass = exceptionClass
        }
    }

    /// DXCC source chosen by `loadDxcc`.
    public enum DxccSource: Equatable, Sendable {
        case ctyDat
        case dxccJson
    }

    // MARK: - entry points

    /// Java `loadDxcc(dir)`: prefers `cty.dat` (more precise), otherwise `dxcc.json`; wraps both in
    /// `DxccSpecialCases`. `cty.dat` is taken if it is readable and can be read (parsing
    /// itself never throws); `CtyDxccResolver` is **without** `DxccCodeIndex` as in Java.
    /// If neither works, `nil`. Java's output "DXCC zdroj: …" is replaced by `source`.
    public static func loadDxcc(directory: URL) -> (lookup: any DxccLookup, source: DxccSource)? {
        let cty = directory.appendingPathComponent("cty.dat")
        if FileManager.default.isReadableFile(atPath: cty.path), let data = try? Data(contentsOf: cty) {
            return (DxccSpecialCases(CtyDxccResolver.fromData(data)), .ctyDat)
        }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("dxcc.json")),
              let resolver = try? DxccResolver.fromData(data) else {
            return nil
        }
        return (DxccSpecialCases(resolver), .dxccJson)
    }

    /// File bytes like Java `Files.readString(f, UTF_8)`: strict UTF-8 (an invalid
    /// sequence, a surrogate or an overlong encoding → `nil`), the BOM **stays** as the character U+FEFF.
    /// Validation via `transcode` from the standard library — agreement with the Java decoder measured
    /// on 2 million random short sequences (0 differences).
    static func decode(_ data: Data) -> String? {
        let invalid = transcode(data.makeIterator(), from: UTF8.self, to: UTF16.self,
                                stoppingOnError: true, into: { _ in })
        return invalid ? nil : String(decoding: data, as: UTF8.self)
    }

    /// The whole `scoreCheck` path over file bytes (invalid UTF-8 → `.unreadable`).
    public static func check(fileName: String, data: Data, definitions: [ContestDefinition],
                             dxcc: any DxccLookup, registry: MultiplierSetRegistry) -> LogOutcome {
        guard let content = decode(data) else {
            return LogOutcome(status: .unreadable, result: errorResult(fileName, nil, nil, "nelze načíst"),
                              skipReason: nil, exceptionClass: nil)
        }
        return check(fileName: fileName, content: content, definitions: definitions, dxcc: dxcc, registry: registry)
    }

    /// The whole `scoreCheck` path over text: `skipReason` and `evaluate` with the exception caught
    /// (Java `evalSafe`). Unlike the interactive `scoreCheck`, checklogs and logs without claimed
    /// are also evaluated (like the gate reference generator); the reason for skipping is carried by `skipReason`.
    public static func check(fileName: String, content: String, definitions: [ContestDefinition],
                             dxcc: any DxccLookup, registry: MultiplierSetRegistry) -> LogOutcome {
        let text = CabrilloText(content)
        let skip = text.skipReason()
        do {
            let result = try evaluate(fileName: fileName, text: text, definitions: definitions, dxcc: dxcc,
                                      registry: registry)
            return LogOutcome(status: result.error == nil ? .ok : .error, result: result, skipReason: skip,
                              exceptionClass: nil)
        } catch {
            return LogOutcome(status: .exception, result: errorResult(fileName, nil, nil, error.message),
                              skipReason: skip, exceptionClass: error.javaClass)
        }
    }

    /// Java `evaluate`: evaluates one Cabrillo log. Errors reported in `Result.error`
    /// ("chybí hlavička CONTEST", "neznámý závod: …", "definice nemá cabrillo layout") are
    /// returned; an exception anywhere later (session, but also the header — see `CabrilloText.header`) is thrown.
    public static func evaluate(fileName: String, content: String, definitions: [ContestDefinition],
                                dxcc: any DxccLookup, registry: MultiplierSetRegistry) throws(Failure) -> Result {
        try evaluate(fileName: fileName, text: CabrilloText(content), definitions: definitions, dxcc: dxcc,
                     registry: registry)
    }

    static func evaluate(fileName: String, text: CabrilloText, definitions: [ContestDefinition],
                         dxcc: any DxccLookup, registry: MultiplierSetRegistry) throws(Failure) -> Result {
        let contestName = try text.header("CONTEST")
        let myCall = try text.header("CALLSIGN")
        let claimed = parseLong(try text.header("CLAIMED-SCORE"))

        guard let contestName else {
            return errorResult(fileName, nil, claimed, "chybí hlavička CONTEST")
        }
        guard let def = findDef(definitions, contestName) else {
            return errorResult(fileName, contestName, claimed, "neznámý závod: " + contestName)
        }
        guard let cabrillo = def.cabrillo else {
            return errorResult(fileName, contestName, claimed, "definice nemá cabrillo layout")
        }

        let sent = cabrillo.sentOrder?.count ?? 0
        let myGrid = try usesPerKm(def) ? text.detectOwnGrid(sent: sent) : nil
        let session = ContestSession(definition: def, dxcc: dxcc, registry: registry, myCall: myCall, myGrid: myGrid)
        var unresolved: [String] = []

        for line in text.lines {
            let t = text.javaTrim(line)
            if text.upperStartsWith(t, CabrilloText.qsoPrefix) {
                let rest = text.javaTrim(t.lowerBound + CabrilloText.qsoPrefix.count..<t.upperBound)
                if let his = try logLine(session, text, rest, sent), dxcc.resolve(his.call, at: his.date) == nil {
                    unresolved.append(his.call)
                }
            }
        }

        let score: ScoreState
        do {
            score = try session.score()
        } catch {
            throw Failure(error)
        }
        let computed = score.total
        // a missing CLAIMED-SCORE is NOT an error — the score is computed, claimed stays nil
        let pass = claimed.map { $0 == computed } ?? false
        return Result(file: fileName, contest: contestName, qsoCount: score.qsoCount, qsoPoints: score.qsoPoints,
                      multTotal: score.multTotal, multByGroup: score.multByGroup, computed: computed,
                      claimed: claimed, pass: pass, unresolvedCalls: unresolved, error: nil)
    }

    static func errorResult(_ file: String, _ contest: String?, _ claimed: Int64?, _ message: String) -> Result {
        Result(file: file, contest: contest, qsoCount: 0, qsoPoints: 0, multTotal: 0, multByGroup: JavaLinkedMap(),
               computed: 0, claimed: claimed, pass: false, unresolvedCalls: [], error: message)
    }

    /// One `QSO:` line (already without `QSO:` and trimmed): `freq mode date time sentCall [sent…]
    /// rcvdCall [rcvd…]`. A shorter line is silently skipped (`nil`). Received fields are taken by
    /// the class of the counterpart and mapped positionally after `rcvdCall`.
    private static func logLine(_ session: ContestSession, _ text: CabrilloText, _ rest: Range<Int>,
                                _ sent: Int) throws(Failure) -> (call: String, date: Date?)? {
        let tok = text.splitWhitespace(rest)
        let rcvdCallIdx = 5 + sent
        if tok.count <= rcvdCallIdx {
            return nil // corrupted line
        }
        let hisCall = text.string(tok[rcvdCallIdx])

        let fields: [ContestDefinition.ExchangeField]
        do {
            fields = try session.activeReceivedFields(call: hisCall)
        } catch {
            throw Failure(error)
        }
        var received = JavaLinkedMap<String>()
        for (i, field) in fields.enumerated() {
            let idx = rcvdCallIdx + 1 + i
            if idx < tok.count {
                received.put(field.id, text.string(tok[idx]))
            }
        }
        // The QSO's date and time for the DXCC lookup (Club Log data are date-ranged; the other sources ignore it).
        let date: Date? = qsoDate(text.string(tok[2]), text.string(tok[3]))
        do {
            // Java 4-argument `log` with `Instant.now()` (without TOUR the time is irrelevant)
            try session.log(call: hisCall, band: band(text.string(tok[0])), mode: mode(text.string(tok[1])),
                            receivedRaw: received, dxccAt: date)
        } catch {
            throw Failure(error)
        }
        return (hisCall, date)
    }

    /// Cabrillo `yyyy-mm-dd` + `hhmm` (UTC); `nil` when either does not read.
    static func qsoDate(_ day: String, _ time: String) -> Date? {
        let d = day.split(separator: "-")
        guard d.count == 3, let year = Int(d[0]), let month = Int(d[1]), let dayOfMonth = Int(d[2]),
              time.count == 4, time.allSatisfy({ $0.isASCII && $0.isNumber }),
              let hour = Int(time.prefix(2)), let minute = Int(time.suffix(2)) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    // MARK: - contest detection

    private static func findDef(_ defs: [ContestDefinition], _ contestName: String) -> ContestDefinition? {
        if let d = matchDef(defs, contestName) {
            return d
        }
        // The header often carries a year (CONTEST: CQ-WW-SSB 2005) — try without it.
        let stripped = stripTrailingYear(contestName)
        return JavaChar.equalsIgnoreCase(stripped, contestName) ? nil : matchDef(defs, stripped)
    }

    private static func matchDef(_ defs: [ContestDefinition], _ contestName: String) -> ContestDefinition? {
        for d in defs {
            if let cabrillo = d.cabrillo, JavaChar.equalsIgnoreCase(contestName, cabrillo.contestName) {
                return d
            }
        }
        for d in defs where JavaChar.equalsIgnoreCase(contestName, d.id) {
            return d
        }
        return nil
    }

    private static let trailingYear: JavaRegex = {
        do {
            return try JavaRegex("[\\s-]+(?:19|20)\\d{2}\\s*$")
        } catch {
            preconditionFailure("pevný vzor ročníku musí jít zkompilovat: \(error)")
        }
    }()

    /// Java `stripTrailingYear`: `replaceAll("[\\s-]+(?:19|20)\\d{2}\\s*$", "").trim()` —
    /// `\s` and `\d` are ASCII, `$` also takes the place before a trailing line terminator (also U+0085).
    static func stripTrailingYear(_ contestName: String) -> String {
        let ns = contestName as NSString
        var out = ""
        var index = 0
        for match in trailingYear.allMatches(in: contestName) {
            out += ns.substring(with: NSRange(location: index, length: match.range.lowerBound - index))
            index = match.range.upperBound
        }
        if index == 0 {
            return JavaText.trim(contestName)
        }
        out += ns.substring(from: index)
        return JavaText.trim(out)
    }

    /// The contest uses distance scoring (`perKm`) — then an own grid is needed. A `nil` element of the
    /// rules before the first `perKm` is in Java a `NullPointerException` (`r.value()`), which brings down the
    /// whole log — copied as a `Failure` of the same category.
    private static func usesPerKm(_ def: ContestDefinition) throws(Failure) -> Bool {
        guard let rules = def.scoring?.qsoPoints?.rules else { return false }
        for rule in rules {
            guard let rule else {
                throw Failure(javaClass: "NullPointerException",
                              message: "null prvek scoring.qsoPoints.rules")
            }
            if rule.value?.perKm != nil {
                return true
            }
        }
        return false
    }

    // MARK: - band, mode, CLAIMED-SCORE

    /// Java `band`: `Math.round(Double.parseDouble(freqKHz) * 1000.0)` → `Band.fromFrequencyHz`
    /// → ADIF; a non-number → `""`. `parseDouble` also accepts `14042d`, `1.4042e4F`, `0x1.b6ap13`, `NaN`.
    static func band(_ freqKHz: String) -> String {
        guard let value = JavaDouble.parseDouble(freqKHz) else { return "" }
        let hz = JavaMath.round(value * 1000.0)
        return Band.from(frequencyHz: Int(hz))?.adif ?? ""
    }

    /// Java `mode`: Cabrillo abbreviations (`PH`/`SSB`/`USB`/`LSB` → SSB, `RY` → RTTY…), otherwise
    /// `Mode.fromAdif`, otherwise upper-cased text. `toUpperCase` is a full mapping (`ßB` → `SSB`).
    static func mode(_ m: String) -> String {
        let upper = m.uppercased()
        for (names, mode) in modeAliases where names.contains(where: { JavaText.equals($0, upper) }) {
            return mode.rawValue
        }
        return Mode.from(adif: m)?.rawValue ?? upper
    }

    private static let modeAliases: [([String], Mode)] = [
        (["CW"], .cw), (["PH", "SSB", "USB", "LSB"], .ssb), (["FM"], .fm), (["RY", "RTTY"], .rtty),
    ]

    /// Java `parseLong`: `nil`/empty (Java `isBlank`) → `nil`; otherwise `trim()`, delete everything
    /// except ASCII digits and `-` and `Long.parseLong` — an error (a lone `-`, `12-3`, overflow) → `nil`.
    static func parseLong(_ s: String?) -> Int64? {
        guard let s, !JavaText.isBlank(s) else { return nil }
        let kept = JavaText.trim(s).utf16.filter { ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D }
        // Only ASCII digits and `-` remain: here `Int64(_:radix:)` is exactly `Long.parseLong`
        // (sign only at the start, at least one digit, overflow → nil).
        return Int64(String(decoding: kept, as: UTF16.self), radix: 10)
    }

    // MARK: - helpers over text (interface of Java static methods)

    /// Java `stripBlank`: trimming of edge characters `isWhitespace || isSpaceChar || U+FEFF`.
    static func stripBlank(_ s: String) -> String {
        let text = CabrilloText(s)
        return text.string(text.stripBlank(0..<text.units.count))
    }

    /// Java `header(content, key)`. Throws only where Java throws
    /// `StringIndexOutOfBoundsException` (see `CabrilloText.header`).
    static func header(_ content: String, _ key: String) throws(Failure) -> String? {
        try CabrilloText(content).header(key)
    }

    /// Java `detectOwnGrid(content, sent)`.
    static func detectOwnGrid(_ content: String, sent: Int) -> String? {
        CabrilloText(content).detectOwnGrid(sent: sent)
    }

    /// Java `isChecklog`.
    static func isChecklog(_ content: String) -> Bool {
        CabrilloText(content).isChecklog()
    }

    /// Java `skipReason`.
    static func skipReason(_ content: String) -> String? {
        CabrilloText(content).skipReason()
    }
}
