/// JSON of the event data for plugins — in Java it is assembled by the Kotlin UI (`AppState.firePlugins`:
/// `ObjectMapper().writeValueAsString(mapOf(…))`, `qsoData`); moved to the core.
/// Keys in insertion order, `null` is written, numbers bare, strings escaped like Jackson
/// (`WriterBasedJsonGenerator`: `\"`, `\\`, `\b \t \n \f \r`, others < U+0020 as `\u00XX`, everything else
/// including `/`, DEL, U+2028 and characters above U+FFFF raw). Measured by the maintainer-only probe.
public enum PluginEventJson {

    /// Field value: text (`nil` = `null`) or an integer (`Long`).
    public enum Value: Equatable, Sendable {
        case string(String?)
        case number(Int64)
        case bool(Bool)
        /// An already rendered JSON value (a nested object, a list, `null`).
        case raw(String)

        /// An integer or `null`.
        public static func optionalNumber(_ number: Int?) -> Value {
            number.map { .number(Int64($0)) } ?? .raw("null")
        }
    }

    /// Object from key–value pairs in the given order (Kotlin `mapOf`/`linkedMapOf`).
    public static func object(_ fields: [(String, Value)]) -> String {
        var writer = WireJsonWriter(escapeAstral: false)
        writer.bytes.append(0x7B)
        for (index, field) in fields.enumerated() {
            if index > 0 {
                writer.bytes.append(0x2C)
            }
            writer.string(field.0)
            writer.bytes.append(0x3A)
            switch field.1 {
            case .string(let text):
                if let text { writer.string(text) } else { writer.null() }
            case .number(let number):
                writer.ascii(String(number))
            case .bool(let flag):
                writer.ascii(flag ? "true" : "false")
            case .raw(let json):
                writer.bytes.append(contentsOf: Array(json.utf8))
            }
        }
        writer.bytes.append(0x7D)
        return String(decoding: writer.bytes, as: UTF8.self)
    }

    /// The `QSO_LOGGED` event (Kotlin `qsoData`). The text fields of the Swift `Qso` are `""` where Java has `null`
    /// (`null` × `""` divergence): Java writes `null`, Swift `""`.
    public static func qsoLogged(_ qso: Qso) -> String {
        let time: String? = qso.timestampUtc.map { JavaInstant(date: $0).toString() }
        let fields: [(String, Value)] = [
            ("time", .string(time)), ("call", .string(qso.call)), ("band", .string(qso.band?.adif)),
            ("freqHz", .number(Int64(qso.freqHz))), ("mode", .string(qso.mode?.rawValue)),
            ("rstSent", .string(qso.rstSent)), ("rstRcvd", .string(qso.rstRcvd)),
            ("exchangeSent", .string(qso.exchangeSent)), ("exchangeRcvd", .string(qso.exchangeRcvd)),
            ("operator", .string(qso.operator)), ("contestId", .string(qso.contestId)), ("uuid", .string(qso.uuid)),
        ]
        return object(fields)
    }

    /// The `CONTEST_OPENED` event (`contestId`, name from the definition metadata — may be missing, station callsign).
    public static func contestOpened(contestId: String, name: String?, call: String) -> String {
        object([("contestId", .string(contestId)), ("name", .string(name)), ("call", .string(call))])
    }

    /// The `SPOT_RECEIVED` event (a spot from the own DX cluster).
    public static func spotReceived(_ spot: DxSpot) -> String {
        let fields: [(String, Value)] = [
            ("dxCall", .string(spot.dxCall)), ("freqHz", .number(Int64(spot.freqHz))),
            ("spotter", .string(spot.spotter)), ("comment", .string(spot.comment)),
        ]
        return object(fields)
    }

    // MARK: - further events

    private static func contestFields(contestId: String?, name: String?) -> [(String, Value)] {
        [("contestId", .string(contestId)), ("name", .string(name))]
    }

    /// The `QSO_EDITED` event: the QSO before and after the edit, both in the shape of `QSO_LOGGED`.
    public static func qsoEdited(old: Qso, new: Qso) -> String {
        object([("old", .raw(qsoLogged(old))), ("new", .raw(qsoLogged(new)))])
    }

    /// The `QSO_DELETED` event: the deleted QSO in the shape of `QSO_LOGGED`.
    public static func qsoDeleted(_ qso: Qso) -> String {
        qsoLogged(qso)
    }

    /// The `CONTEST_CLOSED` event (the contest that was left).
    public static func contestClosed(contestId: String, name: String?) -> String {
        object(contestFields(contestId: contestId, name: name))
    }

    /// The `APP_STARTED` and `APP_QUITTING` events: the app version and the active contest (`null` when none).
    public static func app(version: String?, contestId: String?, name: String?) -> String {
        object([("version", .string(version))] + contestFields(contestId: contestId, name: name))
    }

    /// The `BAND_CHANGED` event (`radio` is the 0-based radio / VFO index; bands in ADIF notation).
    public static func bandChanged(radio: Int, old: String?, new: String?) -> String {
        object([("radio", .number(Int64(radio))), ("oldBand", .string(old)), ("newBand", .string(new))])
    }

    /// The `MODE_CHANGED` event.
    public static func modeChanged(radio: Int, old: String?, new: String?) -> String {
        object([("radio", .number(Int64(radio))), ("oldMode", .string(old)), ("newMode", .string(new))])
    }

    /// The `FREQUENCY_CHANGED` event.
    public static func frequencyChanged(radio: Int, oldHz: Int64, newHz: Int64) -> String {
        object([("radio", .number(Int64(radio))), ("oldFreqHz", .number(oldHz)), ("newFreqHz", .number(newHz))])
    }

    /// The `SELF_SPOTTED` event: someone spotted the station (`source` is `skimmer` for an RBN spot, else `human`).
    public static func selfSpotted(_ spot: SelfSpot) -> String {
        object([
            ("spotter", .string(spot.spotter)), ("freqHz", .number(Int64(spot.freqHz))),
            ("source", .string(spot.rbn ? "skimmer" : "human")),
            ("snr", .optionalNumber(spot.snrDb)), ("wpm", .optionalNumber(spot.wpm)),
        ])
    }

    /// The `NEW_MULTIPLIER` event: the multipliers (`set` id and `key`) a logged QSO made new.
    public static func newMultiplier(contestId: String?, call: String, band: String, mode: String,
                                     multipliers: [(set: String?, key: String?)]) -> String {
        let list: [String] = multipliers.map { item in
            object([("set", .string(item.set)), ("key", .string(item.key))])
        }
        return object([
            ("contestId", .string(contestId)), ("call", .string(call)), ("band", .string(band)),
            ("mode", .string(mode)), ("multipliers", .raw("[" + list.joined(separator: ",") + "]")),
        ])
    }

    /// The `SCORE_CHANGED` event.
    public static func scoreChanged(contestId: String?, score: ScoreState) -> String {
        object([
            ("contestId", .string(contestId)), ("qsos", .number(Int64(score.qsoCount))),
            ("qsoPoints", .number(score.qsoPoints)), ("mults", .number(Int64(score.multTotal))),
            ("bonusPoints", .number(score.bonusPoints)), ("qtcPoints", .number(score.qtcPoints)),
            ("total", .number(score.total)),
        ])
    }

    /// The `SCORE_REPORTED` event (`status` 0 = the server did not answer; never the full URL).
    public static func scoreReported(host: String?, status: Int, accepted: Bool, message: String) -> String {
        object([("host", .string(host)), ("status", .number(Int64(status))), ("accepted", .bool(accepted)),
                ("message", .string(message))])
    }

    /// The `CLUBLOG_UPLOAD` event (`outcome`: `ok`, `rejected` or `retry`).
    public static func clublogUpload(outcome: String, call: String, status: String) -> String {
        object([("outcome", .string(outcome)), ("call", .string(call)), ("status", .string(status))])
    }
}
