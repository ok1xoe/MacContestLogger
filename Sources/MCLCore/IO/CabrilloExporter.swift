import Foundation

/// Exception of `CabrilloExporter.export` — Java class and text (for
/// `IllegalArgumentException` from the export the text is mandatory, it goes to the user's status line).
public enum CabrilloExportError: Error, Equatable, Sendable {
    /// `java.lang.IllegalArgumentException`: the definition has no `cabrillo:` block (or an empty
    /// `contestName`).
    case illegalArgument(message: String)

    /// Full name of the Java exception class.
    public var javaClass: String {
        switch self {
        case .illegalArgument: return "java.lang.IllegalArgumentException"
        }
    }
}

/// Export of a contest log to Cabrillo 3.0 format — port of `io/CabrilloExporter.java` (Java v1.1.1),
/// behaviour measured in.4 and in `Fixtures/cabrillo-export-java.tsv`.
///
/// Nothing is hardcoded: the contest name and the order of exchange fields on the QSO line come from the `cabrillo:` block
/// of the definition (`contestName`, `sentOrder`, `receivedOrder`). The sent exchange is composed as
/// in the entry window (defaults from the definition and setup), preferring the stored
/// sent exchange and the actually sent report; the received one is split out of `exchangeRcvd` according to
/// the fields active for the counterpart station.
///
/// Java subtleties that recur here:
/// - the QSO column width is Java `String.length()` (**UTF-16 units**) computed **before**
///   conversion to ASCII — a decomposed `É` (2 units) yields one extra space after conversion, an emoji
///   (2 units) becomes a single `?`;
/// - likewise the wrapping of `SOAPBOX` (66 UTF-16 units of content);
/// - `toAscii` of the whole file: NFD, delete marks (`\p{M}`), every remaining non-ASCII **code
///   point** → `?`;
/// - sorting by time is stable (index as second key), QSOs without time at the
///   end — so their omission warnings come last;
/// - frequency `Math.round(hz / 1000.0)` (half up), time `HHmm` with truncated seconds;
/// - `X-QSO:` is a prefix two characters longer, so the whole line shifts.
///
/// Java `null` × `""`: the text fields of `Qso` and `StationConfig` are `""` here;
/// Java treats them everywhere via `isBlank()`; a `null` QSO callsign (omission with warning
/// `QSO null vynecháno`) and a `null` station callsign (NPE) are unreachable in Swift.
public enum CabrilloExporter {

    /// Maximum header line length per the specification.
    static let maxLine = 75

    /// Placeholder token for a missing value — keeps the column count so the exchange does not shift.
    static let missing = "-"

    /// Order of categories in the header (keys from `ContestSetup.category`).
    private static let categoryOrder: [String] = [
        "OPERATOR", "ASSISTED", "BAND", "MODE", "POWER", "STATION", "TIME", "TRANSMITTER", "OVERLAY",
    ]

    /// Value offered by the category picker as "nothing" — does not belong in Cabrillo.
    private static let notApplicable = "N/A"

    /// Export result: the whole file (lines terminated by `\n`, pure ASCII), the number of written QSO
    /// lines and what needs to be checked before sending.
    public struct Result: Equatable, Sendable {
        public let text: String
        public let qsoCount: Int
        public let warnings: [String]

        public init(text: String, qsoCount: Int, warnings: [String]) {
            self.text = text
            self.qsoCount = qsoCount
            self.warnings = warnings
        }
    }

    /// Export input — Java `Input.builder(...)` as a struct with default values.
    /// `category` and `sentExchange` are Java `Map`s (`get`/`getOrDefault`,
    /// order does not matter).
    public struct Input {
        /// Contest definition (must have a `cabrillo:` block).
        public var definition: ContestDefinition
        /// Station data (callsign, address…).
        public var station: StationConfig
        /// QSOs of the contest; deleted ones are dropped, order does not matter.
        public var qsos: [Qso]
        /// Received fields active for the given callsign (conditional exchange); `nil` = none. An error
        /// (e.g. the `stationClasses` expression in `ContestSession`) passes through `export` unchanged.
        public var receivedFields: (String) throws -> [ContestDefinition.ExchangeField]?
        /// Categories from the contest setup (OPERATOR → SINGLE-OP…).
        public var category = JavaLinkedMap<String>()
        /// Sent-exchange values entered in the contest setup (zone, district…).
        public var sentExchange = JavaLinkedMap<String>()
        /// List of operators; empty = derived from the QSOs.
        public var operators = ""
        public var soapbox = ""
        /// Declared score; `nil` = the CLAIMED-SCORE line is not written.
        public var claimedScore: Int64?
        public var createdBy = "MacContestLogger"
        /// QTC (WAE) — written as `QTC:` lines after the QSOs.
        public var qtcs: [QtcRecord] = []

        public init(definition: ContestDefinition, station: StationConfig, qsos: [Qso],
                    receivedFields: @escaping (String) throws -> [ContestDefinition.ExchangeField]?) {
            self.definition = definition
            self.station = station
            self.qsos = qsos
            self.receivedFields = receivedFields
        }
    }

    /// Builds the Cabrillo file.
    ///
    /// - Throws: `CabrilloExportError.illegalArgument` when the definition has no `cabrillo:` block;
    ///   otherwise the error from `receivedFields`.
    public static func export(_ input: Input) throws -> Result {
        guard let cab = input.definition.cabrillo, let contestName = cab.contestName,
              !JavaText.isBlank(contestName) else {
            throw CabrilloExportError.illegalArgument(
                message: "Definice závodu nemá blok cabrillo: — export do Cabrilla není možný")
        }
        var warnings: [String] = []
        let myCall = JavaText.trim(input.station.call).uppercased()
        if myCall.isEmpty {
            warnings.append("Chybí volačka stanice (Nastavení → Station data → My Call)")
        }

        let sorted = sortedByTime(input.qsos)
        let multiTwo = JavaChar.equalsIgnoreCase("TWO", getOrDefault(input.category, "TRANSMITTER", ""))
        var transmitterIds = JavaLinkedMap<Int>()
        let layout = SentLayout(input.definition)
        let engine = ExchangeEngine()

        var rows: [[String]] = []
        var xqso: [Bool] = []
        for q in sorted {
            guard let freq = frequency(q), let timestamp = q.timestampUtc, let stamp = utc(timestamp) else {
                warnings.append("QSO " + q.call + " vynecháno — chybí pásmo/frekvence nebo čas")
                continue
            }
            var row: [String] = [freq, modeCode(q.mode), stamp.date, stamp.time, myCall.isEmpty ? missing : myCall]
            row.append(contentsOf: sentValues(input, layout, engine, q))
            row.append(JavaText.trim(q.call).uppercased())
            let received = try receivedValues(input, q)
            // All received fields of the definitions are mandatory, so MISSING means a genuinely
            // missing value — not an unfilled optional item.
            let incompleteExchange = received.contains(missing)
            if incompleteExchange {
                warnings.append("QSO " + q.call + " " + stamp.date + " " + stamp.time
                                + ": chybí část přijaté výměny — zapsáno jako X-QSO")
            }
            row.append(contentsOf: received)
            if multiTwo {
                let station = q.stationId // Java null ≡ ""
                let id: Int
                if let known = transmitterIds[station] {
                    id = known
                } else {
                    id = transmitterIds.count
                    transmitterIds.put(station, id)
                }
                row.append(String(id))
            }
            rows.append(row)
            // A mode the contest does not have is not counted in the score (ContestSession.log) — so the
            // program does not claim it either. A manual user flag takes precedence.
            let modeNotInContest = !ModeEligibility.counts(input.definition.modes, q.mode?.rawValue)
            if modeNotInContest && !q.xqso {
                warnings.append("QSO " + q.call + " v módu " + modeCode(q.mode) + " závod nemá — zapsáno jako X-QSO")
            }
            xqso.append(q.xqso || modeNotInContest || incompleteExchange)
        }
        if multiTwo && transmitterIds.count > 2 {
            warnings.append("Multi-Two: v deníku je " + String(transmitterIds.count)
                            + " stanic, Cabrillo zná jen vysílače 0 a 1")
        }

        var out = ""
        header(&out, input, contestName, myCall, sorted)
        writeQsoLines(&out, rows, xqso)
        for q in input.qtcs {
            out += QtcPlanner.cabrilloLine(q, myCall)
            out += "\n"
        }
        out += "END-OF-LOG:\n"
        return Result(text: toAscii(out), qsoCount: rows.count, warnings: warnings)
    }

    /// Cabrillo is an ASCII format: NFD, delete marks (`\p{M}+`), every remaining non-ASCII code point
    /// → `?` (emoji = one `?`, `ß` = `?`, `한` = three `?` after decomposition into jamo).
    static func toAscii(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            default:
                out.append(scalar.value < 0x80 ? scalar : "?")
            }
        }
        return String(out)
    }

    // MARK: - header

    private static func header(_ out: inout String, _ input: Input, _ contestName: String, _ myCall: String,
                               _ qsos: [Qso]) {
        line(&out, "START-OF-LOG", "3.0")
        line(&out, "CONTEST", contestName)
        line(&out, "CALLSIGN", myCall)
        for dim in categoryOrder {
            guard let value = input.category[dim], !JavaText.isBlank(value),
                  !JavaChar.equalsIgnoreCase(notApplicable, JavaText.trim(value)) else {
                continue
            }
            line(&out, "CATEGORY-" + dim, categoryValue(dim, JavaText.trim(value).uppercased()))
        }
        if let claimed = input.claimedScore {
            line(&out, "CLAIMED-SCORE", String(claimed))
        }
        let s = input.station
        line(&out, "CLUB", s.club)
        line(&out, "LOCATION", s.arrlSection)
        line(&out, "GRID-LOCATOR", s.gridSquare)
        line(&out, "NAME", s.name)
        line(&out, "ADDRESS", s.address1)
        line(&out, "ADDRESS", s.address2)
        line(&out, "ADDRESS-CITY", s.city)
        line(&out, "ADDRESS-STATE-PROVINCE", s.state)
        line(&out, "ADDRESS-POSTALCODE", s.zip)
        line(&out, "ADDRESS-COUNTRY", s.country)
        line(&out, "EMAIL", s.email)
        line(&out, "OPERATORS", operators(input, myCall, qsos))
        for soap in wrap(input.soapbox, width: maxLine - "SOAPBOX: ".utf16.count) {
            line(&out, "SOAPBOX", soap)
        }
        line(&out, "CREATED-BY", input.createdBy)
    }

    /// Writes `TAG: value`; empty values are omitted. The value is only trimmed — `\n` in an address
    /// breaks the header (written verbatim, as in Java).
    private static func line(_ out: inout String, _ tag: String, _ value: String) {
        if JavaText.isBlank(value) { return }
        out += tag
        out += ": "
        out += JavaText.trim(value)
        out += "\n"
    }

    /// Values of our category selection converted to a Cabrillo 3.0 dictionary.
    private static func categoryValue(_ dim: String, _ value: String) -> String {
        if dim == "MODE" {
            if isAny(value, ["DIGITAL", "FT8", "FT4", "PSK", "JT65"]) { return "DIGI" }
            if isAny(value, ["PH", "PHONE"]) { return "SSB" }
        } else if dim == "BAND" {
            if JavaText.equals("70CM", value) { return "432" }
            if JavaText.equals("23CM", value) { return "1.2G" }
            // Post-port microwave bands (Cabrillo 3.0 designators); Java v1.1.1 passes these through unchanged.
            if JavaText.equals("13CM", value) { return "2.3G" }
            if JavaText.equals("9CM", value) { return "3.4G" }
            if JavaText.equals("6CM", value) { return "5.7G" }
            if JavaText.equals("3CM", value) { return "10G" }
        }
        return value
    }

    /// Java `switch` over a string: match by UTF-16 units (not Swift's canonical equivalence).
    private static func isAny(_ value: String, _ options: [String]) -> Bool {
        options.contains { JavaText.equals($0, value) }
    }

    /// Operators from the setup, otherwise those who logged in the log (in order of first QSO).
    private static func operators(_ input: Input, _ myCall: String, _ qsos: [Qso]) -> String {
        if !JavaText.isBlank(input.operators) {
            // `replaceAll("[,;\\s]+", " ")` — `\s` is Java's ASCII `[ \t\n\x0B\f\r]`.
            return collapse(JavaText.trim(input.operators).uppercased()) { $0 == 0x2C || $0 == 0x3B || isSpace($0) }
        }
        var ops = JavaLinkedMap<Bool>()
        for q in qsos where !JavaText.isBlank(q.operator) {
            ops.put(JavaText.trim(q.operator).uppercased(), true)
        }
        return ops.isEmpty ? myCall : ops.keys.map { $0 ?? "null" }.joined(separator: " ")
    }

    /// Splits text into lines of the given width in UTF-16 units (keeps manual breaks
    /// `\r?\n`, wraps on words `\s+`; a word longer than the width stays whole).
    static func wrap(_ text: String, width: Int) -> [String] {
        var out: [String] = []
        for paragraph in splitLines(text) {
            var cur = ""
            var curLength = 0
            for word in ImportedExchange.splitOnJavaSpace(JavaText.trim(paragraph)) where !word.isEmpty {
                let wordLength = word.utf16.count
                if curLength > 0 && curLength + 1 + wordLength > width {
                    out.append(cur)
                    cur = ""
                    curLength = 0
                }
                if curLength > 0 {
                    cur += " "
                    curLength += 1
                }
                cur += word
                curLength += wordLength
            }
            if curLength > 0 {
                out.append(cur)
            }
        }
        return out
    }

    /// Java `text.split("\\r?\\n")`: a lone `\r` does not end a line, trailing empty parts
    /// vanish, leading ones stay.
    private static func splitLines(_ text: String) -> [String] {
        var parts: [String] = []
        var current: [UInt16] = []
        for unit in text.utf16 {
            if unit == 0x0A {
                if current.last == 0x0D { current.removeLast() }
                parts.append(String(decoding: current, as: UTF16.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(unit)
            }
        }
        parts.append(String(decoding: current, as: UTF16.self))
        while let last = parts.last, last.isEmpty {
            parts.removeLast()
        }
        return parts
    }

    // MARK: - QSO lines

    /// Java stable `sorted(comparing(timestampUtc, nullsLast(naturalOrder())))` without deleted ones.
    private static func sortedByTime(_ qsos: [Qso]) -> [Qso] {
        let live: [(offset: Int, element: Qso)] = Array(qsos.filter { !$0.deleted }.enumerated())
        return live.sorted { a, b in
            switch (a.element.timestampUtc, b.element.timestampUtc) {
            case let (x?, y?):
                return x != y ? x < y : a.offset < b.offset
            case (nil, nil):
                return a.offset < b.offset
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }.map(\.element)
    }

    /// `yyyy-MM-dd` and `HHmm` in UTC (seconds truncated). `nil` only outside the `Int64` seconds range
    /// that Java's `Instant` does not have (the QSO is then omitted as having no time).
    static func utc(_ instant: Date) -> (date: String, time: String)? {
        guard let (day, second) = JavaLocalDate.split(instant) else { return nil }
        let civil = JavaLocalDate.civil(epochDay: day)
        let date: String = JavaLocalDate.formatYearOfEra(civil.year) + "-" + JavaLocalDate.twoDigits(civil.month)
            + "-" + JavaLocalDate.twoDigits(civil.day)
        let time: String = JavaLocalDate.twoDigits(second / 3600) + JavaLocalDate.twoDigits(second / 60 % 60)
        return (date, time)
    }

    /// Frequency in kHz for HF, band designation from 50 MHz up (Cabrillo 3.0). Without a frequency, the
    /// lower band edge is used for HF, as N1MM does. `nil` = neither band nor frequency present.
    static func frequency(_ q: Qso) -> String? {
        var band = q.band
        if band == nil && q.freqHz > 0 {
            band = Band.from(frequencyHz: q.freqHz)
        }
        guard let band else { return nil }
        switch band {
        case .m6: return "50"
        case .m2: return "144"
        case .cm70: return "432"
        // Post-port microwave bands: the Cabrillo 3.0 band designators.
        case .cm23: return "1.2G"
        case .cm13: return "2.3G"
        case .cm9: return "3.4G"
        case .cm6: return "5.7G"
        case .cm3: return "10G"
        default:
            let hz = q.freqHz > 0 ? q.freqHz : band.lowHz
            return String(JavaMath.round(Double(hz) / 1000.0))
        }
    }

    /// Mode in Cabrillo: CW, PH (phone), FM, RY (RTTY), DG (other digital); `nil` → CW.
    static func modeCode(_ mode: Mode?) -> String {
        guard let mode else { return "CW" }
        switch mode {
        case .cw: return "CW"
        case .ssb, .am: return "PH"
        case .fm: return "FM"
        case .rtty: return "RY"
        case .psk, .ft8, .ft4, .jt65, .digital: return "DG"
        }
    }

    /// Sent fields of the definition: order (for the stored exchange) and source by id (Java
    /// `LinkedHashMap` — a later field with the same id overwrites the source).
    private struct SentLayout {
        let fields: [ContestDefinition.ExchangeField?]
        let sources: JavaLinkedMap<ContestDefinition.FieldSource>

        init(_ definition: ContestDefinition) {
            fields = definition.exchange?.sent ?? []
            var sources = JavaLinkedMap<ContestDefinition.FieldSource>()
            for field in fields {
                guard let field else { continue } // Java: NPE already in `sentDefaults`
                sources.put(field.id, field.source)
            }
            self.sources = sources
        }
    }

    private static func sentValues(_ input: Input, _ layout: SentLayout, _ engine: ExchangeEngine,
                                   _ q: Qso) -> [String] {
        let serial = Int32(truncatingIfNeeded: q.serialSent ?? 0)
        let defaults = engine.sentDefaults(input.definition,
                                           ExchangeContext(mode: q.mode, nextSerial: serial, station: input.sentExchange))
        // The sent exchange stored on the QSO (values of the sent fields in definition order, "-" = empty)
        // takes precedence: a rover changes county during the contest, a county line has the county on every copy.
        var stored = JavaLinkedMap<String>()
        if !JavaText.isBlank(q.exchangeSent) && input.definition.exchange?.sent != nil {
            let tokens = ImportedExchange.splitOnJavaSpace(JavaText.trim(q.exchangeSent))
            for (field, token) in zip(layout.fields, tokens) where !JavaText.equals(missing, token) {
                guard let field else { continue }
                stored.put(field.id, token)
            }
        }
        var out: [String] = []
        for id in input.definition.cabrillo?.sentOrder ?? [] {
            var value: String? = stored.containsKey(id) ? stored[id] : getOrDefault(defaults, id, "")
            // The actually sent report (the operator could have changed it) takes precedence over the default.
            if !stored.containsKey(id) && layout.sources[id] == .AUTO_RST && !JavaText.isBlank(q.rstSent) {
                value = q.rstSent
            }
            out.append(token(value))
        }
        return out
    }

    private static func receivedValues(_ input: Input, _ q: Qso) throws -> [String] {
        let active = try input.receivedFields(q.call) ?? []
        var values = JavaLinkedMap<String>()
        let flat = JavaText.trim(q.exchangeRcvd)
        let tokens: [String] = flat.isEmpty ? [] : ImportedExchange.splitOnJavaSpace(flat)
        for (field, token) in zip(active, tokens) {
            values.put(field.id, token)
        }
        // Imported QSOs (ADIF/Cabrillo/WSJT-X) carry the report and number only in their own columns.
        // Java `rstRcvd != null` — `""` (≡ null) gives the same result: token `-`.
        for field in active where !values.containsKey(field.id) {
            if field.type == .RST || field.type == .RS {
                values.put(field.id, q.rstRcvd)
            } else if field.type == .SERIAL, let serial = q.serialRcvd {
                values.put(field.id, String(serial))
            }
        }
        var activeIds = JavaLinkedMap<Bool>()
        for field in active {
            activeIds.put(field.id, true)
        }
        var out: [String] = []
        // A field that does not apply to this counterpart (OK/OM district vs. DX number) is not written.
        for id in input.definition.cabrillo?.receivedOrder ?? [] where activeIds.containsKey(id) {
            out.append(token(getOrDefault(values, id, "")))
        }
        return out
    }

    /// One value as one token: no whitespace (`\s`), uppercase, empty → `-`.
    private static func token(_ value: String?) -> String {
        guard let value, !JavaText.isBlank(value) else { return missing }
        let upper = JavaText.trim(value).uppercased()
        return String(String.UnicodeScalarView(upper.unicodeScalars.filter { !isSpace($0.value) }))
    }

    /// Writes QSO lines with aligned columns (frequency right, others left); width in
    /// UTF-16 units.
    private static func writeQsoLines(_ out: inout String, _ rows: [[String]], _ xqso: [Bool]) {
        let columns = rows.map(\.count).max() ?? 0
        var width = [Int](repeating: 0, count: columns)
        let lengths: [[Int]] = rows.map { $0.map(\.utf16.count) }
        for row in lengths {
            for (i, length) in row.enumerated() where length > width[i] {
                width[i] = length
            }
        }
        for (r, row) in rows.enumerated() {
            // X-QSO (Cabrillo 3.0): a QSO in the log that is not to be counted (duplicate, invalid…).
            var line = xqso[r] ? "X-QSO:" : "QSO:"
            for (i, value) in row.enumerated() {
                line += " "
                let pad = String(repeating: " ", count: width[i] - lengths[r][i])
                if i == 0 {
                    line += pad
                    line += value
                } else {
                    line += value
                    line += pad
                }
            }
            out += stripTrailing(line)
            out += "\n"
        }
    }

    // MARK: - helpers

    /// Java `map.getOrDefault(key, fallback)`: a present key returns even a `null` value.
    private static func getOrDefault(_ map: JavaLinkedMap<String>, _ key: String?, _ fallback: String) -> String? {
        map.containsKey(key) ? map[key] : fallback
    }

    /// Java regex `\s` without `UNICODE_CHARACTER_CLASS`.
    private static func isSpace(_ value: UInt32) -> Bool {
        value == 0x20 || (value >= 0x09 && value <= 0x0D)
    }

    /// `replaceAll("[…]+", " ")` for an ASCII character class given by a predicate.
    private static func collapse(_ text: String, _ isSeparator: (UInt32) -> Bool) -> String {
        var out = String.UnicodeScalarView()
        var inRun = false
        for scalar in text.unicodeScalars {
            if isSeparator(scalar.value) {
                if !inRun { out.append(" ") }
                inRun = true
            } else {
                out.append(scalar)
                inRun = false
            }
        }
        return String(out)
    }

    /// Java `String.stripTrailing()` (`Character.isWhitespace`).
    private static func stripTrailing(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let last = scalars.lastIndex(where: { !JavaText.isWhitespace($0) }) else { return "" }
        let end = scalars.index(after: last)
        return end == scalars.endIndex ? text : String(scalars[..<end])
    }
}
