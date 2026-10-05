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
}
