import Foundation

/// Declarative contest definition loaded from YAML. Pure data — no contest
/// logic; the nested types describe the individual DSL sections and the engine interprets them.
///
/// Multipliers are **not owned** here — they only reference a set from the registry
/// (`MultiplierBinding.set`) and say where the key comes from
/// (`MultiplierBinding.from` = `"callsign"` or the id of a received field).
///
/// Port of Java `contest/def/ContestDefinition.java` (a record, 26 nested
/// records, 4 enums), read by Jackson. Hence:
/// - **Every Java field** of every record is read (Jackson checks the type
///   even for fields nobody reads afterwards), via the `YamlObject` accessors.
/// - A Java primitive is `Int`/`Bool`/`Double` with a zero default
///   (`schemaVersion`, `ExchangeField.required`, `QsoPoints.defaultValue`,
///   `PerKm.factor`); a Java `Integer`/`Boolean`/`String` is optional.
///   Text fields hold `nil`, not `""` — the validator and editing distinguish them.
/// - Lists carry `nil` elements (`bands: [~, 160m]` → `[nil, "160m"]`),
///   maps `nil` values — Java lets both through.
/// - Enums are case-sensitive and also take the ordinal (`scope: 1` → `PER_BAND_MODE`);
///   the case order is Java's.
/// - `period: 24` (a scalar instead of a map) is `Period(durationHours: 24,
///   sessions: nil)` — the Java one-parameter constructor, see `Period`.
/// - Java secondary constructors are default `nil` arguments here.
public struct ContestDefinition: YamlRecord, Equatable, Sendable {

    // MARK: - Enums (case order = Java constant order, because of the ordinal)

    public enum FieldType: String, YamlEnum, Sendable {
        case RST, RS, SERIAL, INTEGER, TEXT, LOCATOR, CQ_ZONE, ITU_ZONE, DXCC, PREFIX, HQ, NATIONAL,
             STATE, PROVINCE, DISTRICT, IOTA, QTC
    }

    /// Where the value of the sent field comes from. `ROVER_QTH` = the rover's
    /// current county (N1MM ROVERQTH), in county-line mode the county of the given QSO copy.
    public enum FieldSource: String, YamlEnum, Sendable {
        case MANUAL, AUTO_RST, AUTO_SERIAL, FROM_STATION, DERIVED, ROVER_QTH
    }

    public enum Scope: String, YamlEnum, Sendable {
        case PER_BAND, PER_BAND_MODE, PER_MODE, ONCE
    }

    public enum PointsMode: String, YamlEnum, Sendable {
        case FIRST_MATCH, SUM
    }

    // MARK: - Operation

    /// Operating rules that the Info window timers live on. Optional —
    /// contests without them omit the block and the timers run only as information.
    public struct Operating: YamlRecord, Equatable, Sendable {
        public var offTime: OffTime?
        public var bandChange: BandChange?
        public var rules: [OperatingRule?]?

        public init(offTime: OffTime?, bandChange: BandChange?, rules: [OperatingRule?]? = nil) {
            self.offTime = offTime
            self.bandChange = bandChange
            self.rules = rules
        }

        public init(yaml object: YamlObject) {
            offTime = object.decode("offTime", as: OffTime.self)
            bandChange = object.decode("bandChange", as: BandChange.self)
            rules = object.list("rules", of: OperatingRule.self)
        }
    }

    /// Operating rules for some categories only: `when` = category dimension →
    /// value (`OPERATOR: MULTI-OP`), all items must match.
    public struct OperatingRule: YamlRecord, Equatable, Sendable {
        /// Java `Map<String, String>` (`LinkedHashMap`), values may be `nil`.
        public var when: YamlOrderedMap<String>?
        public var offTime: OffTime?
        public var bandChange: BandChange?

        public init(when: YamlOrderedMap<String>?, offTime: OffTime?, bandChange: BandChange?) {
            self.when = when
            self.offTime = offTime
            self.bandChange = bandChange
        }

        public init(yaml object: YamlObject) {
            when = object.map("when", of: String.self)
            offTime = object.decode("offTime", as: OffTime.self)
            bandChange = object.decode("bandChange", as: BandChange.self)
        }
    }

    /// Off-time: `minimumMinutes` = the shortest countable break,
    /// `requiredMinutes` = the total of breaks the station must accumulate.
    public struct OffTime: YamlRecord, Equatable, Sendable {
        public var minimumMinutes: Int?
        public var requiredMinutes: Int?

        public init(minimumMinutes: Int?, requiredMinutes: Int?) {
            self.minimumMinutes = minimumMinutes
            self.requiredMinutes = requiredMinutes
        }

        public init(yaml object: YamlObject) {
            minimumMinutes = object.int("minimumMinutes").map(Int.init)
            requiredMinutes = object.int("requiredMinutes").map(Int.init)
        }
    }

    /// Band change: `minimumMinutes` on the new band (the ten-minute rule),
    /// `perHour` allowed number of changes per hour.
    public struct BandChange: YamlRecord, Equatable, Sendable {
        public var minimumMinutes: Int?
        public var perHour: Int?

        public init(minimumMinutes: Int?, perHour: Int?) {
            self.minimumMinutes = minimumMinutes
            self.perHour = perHour
        }

        public init(yaml object: YamlObject) {
            minimumMinutes = object.int("minimumMinutes").map(Int.init)
            perHour = object.int("perHour").map(Int.init)
        }
    }

    // MARK: - Description and time

    public struct Metadata: YamlRecord, Equatable, Sendable {
        public var name: String?
        public var organizer: String?
        public var description: String?
        public var officialUrl: String?

        public init(name: String?, organizer: String?, description: String?, officialUrl: String?) {
            self.name = name
            self.organizer = organizer
            self.description = description
            self.officialUrl = officialUrl
        }

        public init(yaml object: YamlObject) {
            name = object.string("name")
            organizer = object.string("organizer")
            description = object.string("description")
            officialUrl = object.string("officialUrl")
        }
    }

    /// Contest duration and optional sessions (periods).
    ///
    /// The Java record additionally has a constructor `Period(Integer)`, which Jackson
    /// uses as a delegating creator, so a scalar passes instead of a map too
    /// (measured, probe `ProbeContest`):
    /// - an integer in `int` range → `Period(n, nil)` (`24`, `0x18`, `-3`),
    ///   out of range is an error at the **start** of the token (not at the end as for an `int` field),
    /// - text → Java `trim()` and `Integer.parseInt` (`"24"`, `" 24 "`, `"+24"`,
    ///   `"٣"`); empty/blank text and `"null"` are an **error** (for an `Integer` field
    ///   it would give `null`),
    /// - a decimal number (`1.5`, `1e3`), a boolean and a sequence are an error.
    ///   Beware: the baseline (3.1) and the assignment both claim `1.5` → 1 — measured that it is **not**.
    public struct Period: YamlDecodable, Equatable, Sendable {
        public var durationHours: Int?
        public var sessions: Sessions?
        /// N1MM `StartOfContest`: the weekday (`MON`…`SUN`) and the UTC time (`hhmm`) the contest usually starts on —
        /// the New contest dialog proposes the next such date. Swift-only keys.
        public var startWeekday: String?
        public var startTime: String?

        public init(durationHours: Int?, sessions: Sessions? = nil, startWeekday: String? = nil,
                    startTime: String? = nil) {
            self.durationHours = durationHours
            self.sessions = sessions
            self.startWeekday = startWeekday
            self.startTime = startTime
        }

        public init?(yamlNode node: YamlNode) {
            switch node.value {
            case .mapping:
                guard let object = node.object() else { return nil }
                self = Period(durationHours: object.int("durationHours").map(Int.init),
                              sessions: object.decode("sessions", as: Sessions.self),
                              startWeekday: object.string("startWeekday"), startTime: object.string("startTime"))
            case .int(let value, _):
                guard let exact = Int32(exactly: value) else {
                    node.typeMismatch("číslo \(value) je mimo rozsah int (délka závodu v hodinách)")
                    return nil
                }
                self = Period(durationHours: Int(exact))
            case .string(let text):
                let trimmed = JavaText.trim(text)
                if trimmed.isEmpty {
                    node.typeMismatch("prázdný text nejde převést na délku závodu")
                    return nil
                }
                guard let value = JavaInteger.parseInt(trimmed) else {
                    node.typeMismatch("„\(text)\" není celé číslo (délka závodu v hodinách)")
                    return nil
                }
                self = Period(durationHours: Int(value))
            default:
                node.typeMismatch("\(node.value.kindDescription) nejde převést na délku závodu (čeká se celé číslo nebo mapa)")
                return nil
            }
        }
    }

    /// Contest session: start `hhmm` UTC and length in minutes.
    public struct Sessions: YamlRecord, Equatable, Sendable {
        public var start: String?
        public var minutes: Int?
        /// N1MM `ResetMultsEverySession`: the multipliers count anew in every session (Swift-only key).
        public var resetMultipliers: Bool?

        public init(start: String?, minutes: Int?, resetMultipliers: Bool? = nil) {
            self.start = start
            self.minutes = minutes
            self.resetMultipliers = resetMultipliers
        }

        public init(yaml object: YamlObject) {
            start = object.string("start")
            minutes = object.int("minutes").map(Int.init)
            resetMultipliers = object.bool("resetMultipliers")
        }
    }

    public struct Category: YamlRecord, Equatable, Sendable {
        public var id: String?
        public var label: String?

        public init(id: String?, label: String?) {
            self.id = id
            self.label = label
        }

        public init(yaml object: YamlObject) {
            id = object.string("id")
            label = object.string("label")
        }
    }

    public struct StationClass: YamlRecord, Equatable, Sendable {
        public var id: String?
        public var when: Condition?

        public init(id: String?, when: Condition?) {
            self.id = id
            self.when = when
        }

        public init(yaml object: YamlObject) {
            id = object.string("id")
            when = object.decode("when", as: Condition.self)
        }
    }

    // MARK: - Exchange

    public struct Exchange: YamlRecord, Equatable, Sendable {
        public var sent: [ExchangeField?]?
        public var received: [ExchangeField?]?
        /// `freeForm: true` (Swift-only key, N1MM Sweepstakes): the entry window has one exchange box, its words
        /// are assigned to the received fields by what they look like, in any order (`ExchangeFreeForm`).
        public var freeForm: Bool

        public init(sent: [ExchangeField?]?, received: [ExchangeField?]?, freeForm: Bool = false) {
            self.sent = sent
            self.received = received
            self.freeForm = freeForm
        }

        public init(yaml object: YamlObject) {
            sent = object.list("sent", of: ExchangeField.self)
            received = object.list("received", of: ExchangeField.self)
            freeForm = object.bool("freeForm") ?? false
        }
    }

    public struct ExchangeField: YamlRecord, Equatable, Sendable {
        public var id: String?
        public var type: FieldType?
        /// Java `boolean`: a missing key and `~` → `false`.
        public var required: Bool
        public var source: FieldSource?
        public var appliesWhen: AppliesWhen?
        public var validation: FieldValidation?
        /// Value estimate from the callsign; `nil` = none.
        public var estimate: String?
        /// A `DERIVED` sent field's value (Swift-only key): `lastCall2L` = the last two letters, `lastCallSuffix` =
        /// the suffix of the previous QSO's call (N1MM `Last2L` / `LastCallSuff`).
        public var derive: String?
        /// `split: true` (Swift-only key, N1MM 7QP county line): a received value `A/B/C` logs one QSO per part;
        /// a shorter part takes the leading characters of the first one (`ORDES/JEF` = `ORDES` + `ORJEF`).
        public var split: Bool

        public init(id: String?, type: FieldType?, required: Bool, source: FieldSource?,
                    appliesWhen: AppliesWhen?, validation: FieldValidation?, estimate: String? = nil,
                    derive: String? = nil, split: Bool = false) {
            self.derive = derive
            self.split = split
            self.id = id
            self.type = type
            self.required = required
            self.source = source
            self.appliesWhen = appliesWhen
            self.validation = validation
            self.estimate = estimate
        }

        public init(yaml object: YamlObject) {
            id = object.string("id")
            type = object.decode("type", as: FieldType.self)
            required = object.bool("required") ?? false
            source = object.decode("source", as: FieldSource.self)
            appliesWhen = object.decode("appliesWhen", as: AppliesWhen.self)
            validation = object.decode("validation", as: FieldValidation.self)
            estimate = object.string("estimate")
            derive = object.string("derive")
            split = object.bool("split") ?? false
        }

        /// `derive: lastCall2L` / `lastCallSuffix` (case-insensitive) of a `DERIVED` field.
        public var derivesFromLastCall: LastCall.Part? {
            guard source == .DERIVED, let derive else { return nil }
            switch KotlinText.trim(derive).lowercased() {
            case "lastcall2l": return .lastTwoLetters
            case "lastcallsuffix": return .suffix
            default: return nil
            }
        }
    }

    /// Single-component record — it does **not** accept a scalar (`appliesWhen: wve` is an error).
    public struct AppliesWhen: YamlRecord, Equatable, Sendable {
        public var workedClass: String?

        public init(workedClass: String?) {
            self.workedClass = workedClass
        }

        public init(yaml object: YamlObject) {
            workedClass = object.string("workedClass")
        }
    }

    public struct FieldValidation: YamlRecord, Equatable, Sendable {
        public var regex: String?
        public var min: Int?
        public var max: Int?
        public var length: Int?

        public init(regex: String?, min: Int?, max: Int?, length: Int?) {
            self.regex = regex
            self.min = min
            self.max = max
            self.length = length
        }

        public init(yaml object: YamlObject) {
            regex = object.string("regex")
            min = object.int("min").map(Int.init)
            max = object.int("max").map(Int.init)
            length = object.int("length").map(Int.init)
        }
    }

    // MARK: - Condition

    /// Condition (a recursive tree). Evaluated by the evaluator; here only data.
    /// Only the relevant part (predicates / combinators) is always filled in.
    ///
    /// `not` is a recursive value — the struct holds it in a box
    /// (`ConditionBox`), outwardly it is an ordinary `Condition?` property.
    public struct Condition: YamlRecord, Equatable, Sendable {
        public var allOf: [Condition?]?
        public var anyOf: [Condition?]?
        private var notBox: ConditionBox?
        public var ownDxcc: Bool?
        public var sameDxcc: Bool?
        public var sameContinent: Bool?
        public var otherContinent: Bool?
        public var continentIs: String?
        public var ownContinentIs: String?
        public var workedClass: String?
        public var dxccIn: [String?]?
        public var bandIn: [String?]?
        public var mode: String?
        public var fieldEquals: FieldEquals?
        public var fieldPresent: String?
        public var expr: String?
        public var bonusStation: Bool?
        /// The QSO time is in the UTC window `"HHMM-HHMM"` (both minutes included; `"2200-0559"` wraps midnight).
        /// N1MM `PointsMultAtTimeGMT`. Swift-only key.
        public var timeBetween: String?
        /// My own country is one of these DXCC codes (like `dxccIn` for the worked station). Swift-only key.
        public var ownDxccIn: [String?]?
        /// The worked / my own station's ADIF DXCC entity number is one of these (`291` = USA, `1` = Canada, `6` = Alaska):
        /// unlike the country codes of `dxccIn` they tell Alaska, Hawaii or Asiatic Russia apart. Swift-only keys.
        public var entityIn: [Int?]?
        public var ownEntityIn: [Int?]?
        /// I am an in-state station of the QSO party (`inState.sections` holds my ARRL section). Swift-only key.
        public var inState: Bool?
        /// The received field matches the regex (whole value, after trimming and upper-casing). Swift-only key.
        public var fieldMatches: FieldMatches?

        public var not: Condition? {
            get { notBox?.value }
            set { notBox = newValue.map(ConditionBox.init) }
        }

        public init(allOf: [Condition?]? = nil, anyOf: [Condition?]? = nil, not: Condition? = nil,
                    ownDxcc: Bool? = nil, sameDxcc: Bool? = nil, sameContinent: Bool? = nil,
                    otherContinent: Bool? = nil, continentIs: String? = nil, ownContinentIs: String? = nil,
                    workedClass: String? = nil, dxccIn: [String?]? = nil, bandIn: [String?]? = nil,
                    mode: String? = nil, fieldEquals: FieldEquals? = nil, fieldPresent: String? = nil,
                    expr: String? = nil, bonusStation: Bool? = nil, timeBetween: String? = nil,
                    ownDxccIn: [String?]? = nil, entityIn: [Int?]? = nil, ownEntityIn: [Int?]? = nil) {
            self.timeBetween = timeBetween
            self.ownDxccIn = ownDxccIn
            self.entityIn = entityIn
            self.ownEntityIn = ownEntityIn
            self.allOf = allOf
            self.anyOf = anyOf
            self.notBox = not.map(ConditionBox.init)
            self.ownDxcc = ownDxcc
            self.sameDxcc = sameDxcc
            self.sameContinent = sameContinent
            self.otherContinent = otherContinent
            self.continentIs = continentIs
            self.ownContinentIs = ownContinentIs
            self.workedClass = workedClass
            self.dxccIn = dxccIn
            self.bandIn = bandIn
            self.mode = mode
            self.fieldEquals = fieldEquals
            self.fieldPresent = fieldPresent
            self.expr = expr
            self.bonusStation = bonusStation
        }

        public init(yaml object: YamlObject) {
            allOf = object.list("allOf", of: Condition.self)
            anyOf = object.list("anyOf", of: Condition.self)
            notBox = object.decode("not", as: Condition.self).map(ConditionBox.init)
            ownDxcc = object.bool("ownDxcc")
            sameDxcc = object.bool("sameDxcc")
            sameContinent = object.bool("sameContinent")
            otherContinent = object.bool("otherContinent")
            continentIs = object.string("continentIs")
            ownContinentIs = object.string("ownContinentIs")
            workedClass = object.string("workedClass")
            dxccIn = object.list("dxccIn", of: String.self)
            bandIn = object.list("bandIn", of: String.self)
            mode = object.string("mode")
            fieldEquals = object.decode("fieldEquals", as: FieldEquals.self)
            fieldPresent = object.string("fieldPresent")
            expr = object.string("expr")
            bonusStation = object.bool("bonusStation")
            timeBetween = object.string("timeBetween")
            ownDxccIn = object.list("ownDxccIn", of: String.self)
            entityIn = object.list("entityIn", of: Int32.self).map { $0.map { $0.map(Int.init) } }
            ownEntityIn = object.list("ownEntityIn", of: Int32.self).map { $0.map { $0.map(Int.init) } }
            inState = object.bool("inState")
            fieldMatches = object.decode("fieldMatches", as: FieldMatches.self)
        }
    }

    /// Immutable box for the recursive `Condition.not`; equality by content.
    final class ConditionBox: Equatable, Sendable {
        let value: Condition

        init(_ value: Condition) {
            self.value = value
        }

        static func == (lhs: ConditionBox, rhs: ConditionBox) -> Bool {
            lhs.value == rhs.value
        }
    }

    public struct FieldMatches: YamlRecord, Equatable, Sendable {
        public var field: String?
        public var regex: String?

        public init(field: String?, regex: String?) {
            self.field = field
            self.regex = regex
        }

        public init(yaml object: YamlObject) {
            field = object.string("field")
            regex = object.string("regex")
        }
    }

    public struct FieldEquals: YamlRecord, Equatable, Sendable {
        public var field: String?
        public var value: String?

        public init(field: String?, value: String?) {
            self.field = field
            self.value = value
        }

        public init(yaml object: YamlObject) {
            field = object.string("field")
            value = object.string("value")
        }
    }

    // MARK: - Scoring

    public struct Scoring: YamlRecord, Equatable, Sendable {
        public var qsoPoints: QsoPoints?
        public var bonuses: [Bonus?]?
        public var total: String?
        /// QTC traffic (WAE): `nil` = the contest has no QTC.
        public var qtc: Qtc?
        /// N1MM `PowerMult`: the final score multiplied by the factor of the Cabrillo power category chosen in the
        /// contest setup (`HIGH: 1, LOW: 2, QRP: 4`); a category that is not listed = ×1. Swift-only key.
        public var powerFactor: YamlOrderedMap<Int>?

        public init(qsoPoints: QsoPoints?, bonuses: [Bonus?]?, total: String?, qtc: Qtc? = nil,
                    powerFactor: YamlOrderedMap<Int>? = nil) {
            self.qsoPoints = qsoPoints
            self.bonuses = bonuses
            self.total = total
            self.qtc = qtc
            self.powerFactor = powerFactor
        }

        public init(yaml object: YamlObject) {
            qsoPoints = object.decode("qsoPoints", as: QsoPoints.self)
            bonuses = object.list("bonuses", of: Bonus.self)
            total = object.string("total")
            qtc = object.decode("qtc", as: Qtc.self)
            powerFactor = Self.intMap(object.map("powerFactor", of: Int32.self))
        }

        static func intMap(_ map: YamlOrderedMap<Int32>?) -> YamlOrderedMap<Int>? {
            map.map { values in
                var out = YamlOrderedMap<Int>()
                for pair in values.pairs {
                    out.set(pair.key, pair.value.map(Int.init))
                }
                return out
            }
        }

        /// The factor of a power category (`HIGH`, `LOW`, `QRP`; N1MM `HP`/`LP` are accepted as keys too).
        public func powerFactorFor(_ category: String?) -> Int {
            guard let powerFactor, let category else { return 1 }
            let wanted: String = KotlinText.trim(category).uppercased()
            let aliases: [String: String] = ["HP": "HIGH", "LP": "LOW"]
            for pair in powerFactor.pairs {
                let key: String = KotlinText.trim(pair.key ?? "").uppercased()
                if key == wanted || aliases[key] == wanted, let value = pair.value {
                    return value
                }
            }
            return 1
        }
    }

    /// QTC (WAE DX Contest): each QTC = `points` points; at most `maxPerStation`
    /// QTCs with one station and `groupSize` in one series.
    public struct Qtc: YamlRecord, Equatable, Sendable {
        public var points: Int?
        public var maxPerStation: Int?
        public var groupSize: Int?

        public init(points: Int?, maxPerStation: Int?, groupSize: Int?) {
            self.points = points
            self.maxPerStation = maxPerStation
            self.groupSize = groupSize
        }

        public init(yaml object: YamlObject) {
            points = object.int("points").map(Int.init)
            maxPerStation = object.int("maxPerStation").map(Int.init)
            groupSize = object.int("groupSize").map(Int.init)
        }

        public var pointsOrDefault: Int { points ?? 1 }
        public var maxPerStationOrDefault: Int { maxPerStation ?? 10 }
        public var groupSizeOrDefault: Int { groupSize ?? 10 }
    }

    public struct QsoPoints: YamlRecord, Equatable, Sendable {
        public var mode: PointsMode?
        /// YAML key **`default`** (Java `@JsonProperty("default")`); the key
        /// `defaultValue` is ignored as unknown. Java `int` → default `0`.
        public var defaultValue: Int
        public var rules: [PointRule?]?
        /// N1MM `PointsMultAtTime…`, `PointsMultByBand/Mode/Continent/Country`: the points of a QSO multiplied by the
        /// factor of every entry whose condition holds. Swift-only key.
        public var factors: [PointFactor?]?

        public init(mode: PointsMode?, defaultValue: Int, rules: [PointRule?]?, factors: [PointFactor?]? = nil) {
            self.mode = mode
            self.defaultValue = defaultValue
            self.rules = rules
            self.factors = factors
        }

        public init(yaml object: YamlObject) {
            mode = object.decode("mode", as: PointsMode.self)
            defaultValue = object.int("default").map(Int.init) ?? 0
            rules = object.list("rules", of: PointRule.self)
            factors = object.list("factors", of: PointFactor.self)
        }
    }

    /// One `qsoPoints.factors` entry: `{ when: …, factor: 2 }`.
    public struct PointFactor: YamlRecord, Equatable, Sendable {
        public var when: Condition?
        public var factor: Double?

        public init(when: Condition?, factor: Double?) {
            self.when = when
            self.factor = factor
        }

        public init(yaml object: YamlObject) {
            when = object.decode("when", as: Condition.self)
            factor = object.double("factor")
        }
    }

    public struct PointRule: YamlRecord, Equatable, Sendable {
        public var when: Condition?
        public var value: PointValue?

        public init(when: Condition?, value: PointValue?) {
            self.when = when
            self.value = value
        }

        public init(yaml object: YamlObject) {
            when = object.decode("when", as: Condition.self)
            value = object.decode("value", as: PointValue.self)
        }
    }

    /// Exactly one of the variants is non-zero: fixed points / expression / points per km.
    public struct PointValue: YamlRecord, Equatable, Sendable {
        public var fixed: Int?
        public var expr: String?
        public var perKm: PerKm?

        public init(fixed: Int?, expr: String?, perKm: PerKm?) {
            self.fixed = fixed
            self.expr = expr
            self.perKm = perKm
        }

        public init(yaml object: YamlObject) {
            fixed = object.int("fixed").map(Int.init)
            expr = object.string("expr")
            perKm = object.decode("perKm", as: PerKm.self)
        }
    }

    public struct PerKm: YamlRecord, Equatable, Sendable {
        public var field: String?
        /// Java `double`: a missing key and `~` → `0.0`.
        public var factor: Double
        public var round: String?
        public var min: Int?
        public var max: Int?

        public init(field: String?, factor: Double, round: String?, min: Int?, max: Int?) {
            self.field = field
            self.factor = factor
            self.round = round
            self.min = min
            self.max = max
        }

        public init(yaml object: YamlObject) {
            field = object.string("field")
            factor = object.double("factor") ?? 0
            round = object.string("round")
            min = object.int("min").map(Int.init)
            max = object.int("max").map(Int.init)
        }
    }

    public struct Bonus: YamlRecord, Equatable, Sendable {
        public var id: String?
        public var when: Condition?
        public var value: PointValue?
        public var scope: Scope?

        public init(id: String?, when: Condition?, value: PointValue?, scope: Scope?) {
            self.id = id
            self.when = when
            self.value = value
            self.scope = scope
        }

        public init(yaml object: YamlObject) {
            id = object.string("id")
            when = object.decode("when", as: Condition.self)
            value = object.decode("value", as: PointValue.self)
            scope = object.decode("scope", as: Scope.self)
        }
    }

    // MARK: - Multipliers, dupes, output

    public struct MultiplierBinding: YamlRecord, Equatable, Sendable {
        public var id: String?
        public var set: String?
        public var from: String?
        public var scope: Scope?
        public var label: String?
        public var appliesWhen: AppliesWhen?
        /// Multiple of the number of multipliers per band (WAE: 80m ×4, 40m ×3, higher ×2);
        /// only for scope `PER_BAND`/`PER_BAND_MODE`, `nil` = weight 1.
        /// Java `Map<String, Integer>` (`LinkedHashMap`), values may be `nil`.
        public var bandWeights: YamlOrderedMap<Int>?
        /// The multiplier counts only for QSOs meeting this condition (N1MM `CountMultOnlyFor`,
        /// `DoNotCountMultOnlyFor`, `DoNotCountMeAsMult`: `when: { not: { ownDxcc: true } }`). Swift-only key.
        public var when: Condition?

        public init(id: String?, set: String?, from: String?, scope: Scope?, label: String?,
                    appliesWhen: AppliesWhen?, bandWeights: YamlOrderedMap<Int>? = nil, when: Condition? = nil) {
            self.when = when
            self.id = id
            self.set = set
            self.from = from
            self.scope = scope
            self.label = label
            self.appliesWhen = appliesWhen
            self.bandWeights = bandWeights
        }

        public init(yaml object: YamlObject) {
            id = object.string("id")
            set = object.string("set")
            from = object.string("from")
            scope = object.decode("scope", as: Scope.self)
            label = object.string("label")
            appliesWhen = object.decode("appliesWhen", as: AppliesWhen.self)
            when = object.decode("when", as: Condition.self)
            bandWeights = object.map("bandWeights", of: Int32.self).map { weights in
                var out = YamlOrderedMap<Int>()
                for pair in weights.pairs {
                    out.set(pair.key, pair.value.map(Int.init))
                }
                return out
            }
        }
    }

    public struct Dupe: YamlRecord, Equatable, Sendable {
        public var scope: Scope?
        public var dupeWorthZero: Bool?
        /// N1MM `DupeType 4`: no dupe check, a station may be worked any number of times. Swift-only key.
        public var none: Bool?
        /// N1MM `DupeQSOMinutesAgo`: the same station may be worked again after this many minutes. Swift-only key.
        public var reworkMinutes: Int?
        /// N1MM `DupeSqlString`: a received field that is part of the dupe key (a rover or mobile in another
        /// county / grid may be worked again). Swift-only key.
        public var byField: String?

        public init(scope: Scope?, dupeWorthZero: Bool?, none: Bool? = nil, reworkMinutes: Int? = nil,
                    byField: String? = nil) {
            self.scope = scope
            self.dupeWorthZero = dupeWorthZero
            self.none = none
            self.reworkMinutes = reworkMinutes
            self.byField = byField
        }

        public init(yaml object: YamlObject) {
            scope = object.decode("scope", as: Scope.self)
            dupeWorthZero = object.bool("dupeWorthZero")
            none = object.bool("none")
            reworkMinutes = object.int("reworkMinutes").map(Int.init)
            byField = object.string("byField")
        }
    }

    public struct Cabrillo: YamlRecord, Equatable, Sendable {
        public var contestName: String?
        public var sentOrder: [String?]?
        public var receivedOrder: [String?]?

        public init(contestName: String?, sentOrder: [String?]?, receivedOrder: [String?]?) {
            self.contestName = contestName
            self.sentOrder = sentOrder
            self.receivedOrder = receivedOrder
        }

        public init(yaml object: YamlObject) {
            contestName = object.string("contestName")
            sentOrder = object.list("sentOrder", of: String.self)
            receivedOrder = object.list("receivedOrder", of: String.self)
        }
    }

    public struct Ui: YamlRecord, Equatable, Sendable {
        public var entryOrder: [String?]?
        public var logColumns: [String?]?

        public init(entryOrder: [String?]?, logColumns: [String?]?) {
            self.entryOrder = entryOrder
            self.logColumns = logColumns
        }

        public init(yaml object: YamlObject) {
            entryOrder = object.list("entryOrder", of: String.self)
            logColumns = object.list("logColumns", of: String.self)
        }
    }

    // MARK: - Root

    /// Java `int`: a missing key and `~` → `0`. A version above
    /// `ContestDefinitionLoader.currentSchemaVersion` is rejected by the loader.
    public var schemaVersion: Int
    public var id: String?
    public var metadata: Metadata?
    public var period: Period?
    public var bands: [String?]?
    public var modes: [String?]?
    public var categories: [Category?]?
    public var stationClasses: [StationClass?]?
    public var exchange: Exchange?
    public var scoring: Scoring?
    public var multipliers: [MultiplierBinding?]?
    public var dupe: Dupe?
    public var cabrillo: Cabrillo?
    public var ui: Ui?
    public var operating: Operating?
    /// N1MM `QsoNumbersByBand`: serial numbering (Swift-only key).
    public var numbering: Numbering?
    /// N1MM `IsWorkable`: who may be worked (`continentIs: EU`, `not: { ownDxcc: true }`…); a QSO outside it is
    /// logged with a warning and scores nothing. Swift-only key.
    public var workable: Condition?
    /// QSO party in-state stations (Swift-only key): my ARRL section from the station data is one of `sections`
    /// (N1MM decides in-state / out-of-state the same way). Read by the condition `inState`.
    public var inState: InState?
    /// Extra ADIF fields of the file export (Swift-only key): ADIF name → received field id, or `=text` for a fixed
    /// value (`{ SAT_NAME: sat, PROP_MODE: "=SAT" }`, N1MM DXSATELLIT).
    public var adif: YamlOrderedMap<String>?
    /// The generic text export (Swift-only key): `export: { text: "{date:10} {time:4} {call:13} {nr:-4}" }`.
    public var export: Export?

    public struct Export: YamlRecord, Equatable, Sendable {
        public var text: String?

        public init(text: String?) {
            self.text = text
        }

        public init(yaml object: YamlObject) {
            text = object.string("text")
        }
    }

    public struct InState: YamlRecord, Equatable, Sendable {
        public var sections: [String?]?

        public init(sections: [String?]?) {
            self.sections = sections
        }

        public init(yaml object: YamlObject) {
            sections = object.list("sections", of: String.self)
        }

        /// Is the ARRL section one of `sections`? (trimmed, case-insensitive; blank = no)
        public func contains(section: String?) -> Bool {
            let wanted: String = KotlinText.trim(section ?? "").uppercased()
            guard !wanted.isEmpty, let sections else { return false }
            return sections.contains { ($0.map { KotlinText.trim($0).uppercased() }) == wanted }
        }
    }

    /// `numbering`: `perBand` = a sequence of its own on every band; `multiOpOnly` = only in a multi-transmitter
    /// category (N1MM `QsoNumbersByBand 2`).
    public struct Numbering: YamlRecord, Equatable, Sendable {
        public var perBand: Bool?
        public var multiOpOnly: Bool?

        public init(perBand: Bool?, multiOpOnly: Bool? = nil) {
            self.perBand = perBand
            self.multiOpOnly = multiOpOnly
        }

        public init(yaml object: YamlObject) {
            perBand = object.bool("perBand")
            multiOpOnly = object.bool("multiOpOnly")
        }

        /// Numbering per band for the setup's categories (`TRANSMITTER` other than `ONE` counts as multi).
        public func perBand(category: [String: String]) -> Bool {
            guard perBand == true else { return false }
            guard multiOpOnly == true else { return true }
            let transmitter: String = (category["TRANSMITTER"] ?? "").uppercased()
            let op: String = (category["OPERATOR"] ?? "").uppercased()
            return op == "MULTI-OP" && (transmitter == "UNLIMITED" || transmitter == "DISTRIBUTED")
        }
    }

    public init(schemaVersion: Int = 0, id: String?, metadata: Metadata? = nil, period: Period? = nil,
                bands: [String?]? = nil, modes: [String?]? = nil, categories: [Category?]? = nil,
                stationClasses: [StationClass?]? = nil, exchange: Exchange? = nil, scoring: Scoring? = nil,
                multipliers: [MultiplierBinding?]? = nil, dupe: Dupe? = nil, cabrillo: Cabrillo? = nil,
                ui: Ui? = nil, operating: Operating? = nil) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.metadata = metadata
        self.period = period
        self.bands = bands
        self.modes = modes
        self.categories = categories
        self.stationClasses = stationClasses
        self.exchange = exchange
        self.scoring = scoring
        self.multipliers = multipliers
        self.dupe = dupe
        self.cabrillo = cabrillo
        self.ui = ui
        self.operating = operating
    }

    public init(yaml object: YamlObject) {
        schemaVersion = object.int("schemaVersion").map(Int.init) ?? 0
        id = object.string("id")
        metadata = object.decode("metadata", as: Metadata.self)
        period = object.decode("period", as: Period.self)
        bands = object.list("bands", of: String.self)
        modes = object.list("modes", of: String.self)
        categories = object.list("categories", of: Category.self)
        stationClasses = object.list("stationClasses", of: StationClass.self)
        exchange = object.decode("exchange", as: Exchange.self)
        scoring = object.decode("scoring", as: Scoring.self)
        multipliers = object.list("multipliers", of: MultiplierBinding.self)
        dupe = object.decode("dupe", as: Dupe.self)
        cabrillo = object.decode("cabrillo", as: Cabrillo.self)
        ui = object.decode("ui", as: Ui.self)
        operating = object.decode("operating", as: Operating.self)
        numbering = object.decode("numbering", as: Numbering.self)
        workable = object.decode("workable", as: Condition.self)
        inState = object.decode("inState", as: InState.self)
        adif = object.map("adif", of: String.self)
        export = object.decode("export", as: Export.self)
    }
}
