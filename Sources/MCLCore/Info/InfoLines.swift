import Foundation

/// The header of the Info window (Kotlin `Header`, `RW:263-299`): the station call and the sent exchange on the
/// left, the operator's call on the right.
public struct InfoHeader: Equatable, Sendable {
    /// The station call; `—` when blank.
    public let stationCall: String
    /// `Výměna: <exchange>` (translated); `nil` when the exchange is blank (the text is not shown).
    public let exchangeText: String?
    /// The operator's call; `—` when blank.
    public let operatorCall: String
}

/// The four information lines about the call being typed and the header of the Info window of v1.1.1
/// (`ui/RateWindow.kt`: `InfoLines` `:301-322`, `spotLine` `:340`, `countryLine` `:349`, `sunLine` `:360`,
/// `wwvLine` `:369`, `dayShort` `:375`). Pure functions over values; a line with no content is an empty string
/// (the window then does not draw it).
///
/// `countryLine`, `sunLine` and `dayShort` are the Kotlin private functions measured on the JVM
/// (maintainer-only probe, rows `country`, `sun`, `dayShort`, `callinfo`); `spotLine`, `wwvLine` and the
/// header take an `AppState` in Kotlin and are transcribed (rows `spot`, `wwv`, `header`).
public enum InfoLines {

    /// The typed call as the window uses it: Kotlin `trim().uppercase()` (`RW:302`).
    public static func normalizedCall(_ typed: String) -> String {
        KotlinText.trim(typed).uppercased()
    }

    /// My position from the station settings (`AppState.myLatLon`): `trim().replace(',', '.').toDoubleOrNull()`;
    /// `NaN` for an empty or unreadable field (azimuth and distance are then not computed).
    public static func position(latitude: String, longitude: String) -> (lat: Double, lon: Double) {
        func parse(_ text: String) -> Double {
            let normalized: String = KotlinText.trim(text).replacingOccurrences(of: ",", with: ".")
            return KotlinNumber.toDoubleOrNull(normalized) ?? Double.nan
        }
        return (parse(latitude), parse(longitude))
    }

    /// The information about the typed call (`RW:302-309`): `nil` for fewer than two characters or an unknown call.
    ///
    /// - Throws: `JavaDateTimeException` at the edges of the `Instant` range, like `CallsignInfo.forEntity`.
    public static func callsignInfo(typedCall: String, lookup: (any DxccLookup)?, myLat: Double, myLon: Double,
                                    now: JavaInstant) throws(JavaDateTimeException) -> CallsignInfo? {
        let call: String = normalizedCall(typedCall)
        if call.utf16.count < 2 {
            return nil
        }
        guard let entity = lookup?.resolve(call) else { return nil }
        return try CallsignInfo.forEntity(entity, myLat: myLat, myLon: myLon, now: now)
    }

    /// `MI0BPB - 14090.07 [VE3KI @ 3 min]` — the last spot of the typed call (`RW:340-346`); `""` without a spot.
    ///
    /// - Parameters:
    ///   - call: the normalized call (`normalizedCall(_:)`).
    ///   - decimalSeparator: the decimal separator of the Java default locale (`"%.2f".format` — `"."` for
    ///     `en_US`, `","` for `cs_CZ`).
    public static func spot(call: String, spots: SpotBuffer, now: JavaInstant,
                            decimalSeparator: String = ".") -> String {
        guard let spotted = spots.find(call) else { return "" }
        let freq: String = JavaFormat.fixed(Double(spotted.spot.freqHz) / 1000.0, precision: 2)
            .replacingOccurrences(of: ".", with: decimalSeparator)
        let comment: String = spotted.spot.comment
        let age: Int64 = spotted.ageMinutes(now.date)
        let head: String = call + " - " + freq + " [" + spotted.spot.spotter + " @ " + String(age) + " min]"
        return KotlinText.isBlank(comment) ? head : head + " " + comment
    }

    /// `GI: EU/NORTHERN IRELAND, Zn 14, Hdg 51° LP 232° 3012mi 4847km` (`RW:349-357`). Like Kotlin string templates a
    /// missing prefix, continent or entity name is the text `null`.
    public static func country(_ info: CallsignInfo?) -> String {
        guard let info else { return "" }
        var parts: [String] = []
        parts.append(javaText(info.prefix) + ": " + javaText(info.continent) + "/" + javaText(info.entityName))
        if let zone = info.cqZone {
            parts.append("Zn " + String(zone))
        }
        if let shortPath = info.shortPathDeg {
            parts.append("Hdg " + String(shortPath) + "° LP " + javaText(info.longPathDeg) + "°")
        }
        if let miles = info.distanceMiles {
            parts.append(String(miles) + "mi " + javaText(info.distanceKm) + "km")
        }
        return parts.joined(separator: ", ")
    }

    /// `Sunrise:06:29Z Sunset:18:38Z His time: 1412(so)` (`RW:360-366`); `""` without sun times. A call with a
    /// sunrise always has a sunset and a local time (`CallsignInfo.forEntity`), so the missing-piece branches are
    /// unreachable (Kotlin would throw there).
    public static func sun(_ info: CallsignInfo?, translate: Translator = .source) -> String {
        guard let info, let sunrise = info.sunrise else { return "" }
        guard let sunset = info.sunset, let local = info.dxLocalTime else { return "" }
        let localSecond: Int64 = local / 1_000_000_000
        let localText: String = twoDigits(localSecond / 3600) + twoDigits(localSecond / 60 % 60)
        return "Sunrise:" + clock(sunrise) + "Z Sunset:" + clock(sunset) + "Z His time: " + localText + "("
            + dayShort(info.dxDayOfWeek, translate: translate) + ")"
    }

    /// `WWV de VE7CC <18Z> SFI=142 A=8 K=3 No Storms -> No Storms` — the last WWV message (`RW:369-373`); `""`
    /// without one. The trailing space before an empty `conditions` is kept, as in Kotlin.
    public static func wwv(_ message: WwvMessage?) -> String {
        guard let w = message else { return "" }
        return "WWV de " + w.spotter + " <" + String(w.hourUtc) + "Z> SFI=" + String(w.sfi) + " A=" + String(w.aIndex)
            + " K=" + String(w.kIndex) + " " + w.conditions
    }

    /// The short Czech day name (`RW:375-384`): `po`, `út`, `st`, `čt`, `pá`, `so`, `ne` — only `út`, `čt`, `pá`
    /// go through `tr`, the others are literals (so they stay Czech in every language).
    public static func dayShort(_ day: CallsignInfo.DayOfWeek?, translate: Translator = .source) -> String {
        guard let day else { return "" }
        switch day {
        case .monday: return "po"
        case .tuesday: return translate.translate("út")
        case .wednesday: return "st"
        case .thursday: return translate.translate("čt")
        case .friday: return translate.translate("pá")
        case .saturday: return "so"
        case .sunday: return "ne"
        }
    }

    /// The header (`RW:263-299`).
    public static func header(stationCall: String, sentExchange: String, operatorCall: String,
                              translate: Translator = .source) -> InfoHeader {
        let exchange: String? = KotlinText.isBlank(sentExchange)
            ? nil : translate.translate("Výměna: %s", [.string(sentExchange)])
        return InfoHeader(stationCall: KotlinText.isBlank(stationCall) ? "—" : stationCall, exchangeText: exchange,
                          operatorCall: KotlinText.isBlank(operatorCall) ? "—" : operatorCall)
    }

    // MARK: - Helpers

    /// A Kotlin string template of a nullable value.
    private static func javaText(_ value: Int?) -> String {
        value.map { String($0) } ?? "null"
    }

    private static func javaText(_ value: String?) -> String {
        value ?? "null"
    }

    private static func twoDigits(_ value: Int64) -> String {
        JavaLocalDate.twoDigits(value)
    }

    /// `HH:mm` of a second of the day.
    private static func clock(_ secondOfDay: Int32) -> String {
        let s = Int64(secondOfDay)
        return twoDigits(s / 3600) + ":" + twoDigits(s / 60 % 60)
    }
}
