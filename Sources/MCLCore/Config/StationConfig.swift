import Foundation

/// Own-station data stored in `config.json`. Maps to/from `Station`
/// via `toStation()`/`from(_:)` (Java: `toStation()`/`from(Station)`).
///
/// A small deviation from Java: `call`/`operator`/`gridSquare`/`name` have in Java
/// a getter/setter that does not coerce `null` to `""` (unlike the remaining 20
/// fields, where it does) — so Java leaves these 4 fields `null` when JSON
/// sets them to `null`. In Swift all fields are non-optional `String`, so
/// `value(_:default:)` behaves the same for all fields (an explicit JSON `null`
/// → `""`). Not a regression, just a unification of behaviour that was
/// inconsistent in Java only because of a missing check on those 4 fields — no Java
/// test touches this asymmetry.
public struct StationConfig: Codable, Equatable, Sendable {
    public var call: String = ""
    public var `operator`: String = ""
    public var gridSquare: String = ""
    public var name: String = ""
    // Extended station data (like N1MM „Edit Station Information"). So far only
    // stored/editable; text (including zones and coordinates), without validation.
    public var address1: String = ""
    public var address2: String = ""
    public var city: String = ""
    public var state: String = ""
    public var zip: String = ""
    public var country: String = ""
    public var cqZone: String = ""
    public var ituZone: String = ""
    public var license: String = ""
    public var latitude: String = ""
    public var longitude: String = ""
    public var stationTxRx: String = ""
    public var power: String = ""
    public var antenna: String = ""
    public var antHeight: String = ""
    public var asl: String = ""
    public var arrlSection: String = ""
    public var roverQth: String = ""
    public var club: String = ""
    public var email: String = ""

    enum CodingKeys: String, CodingKey {
        case call, `operator`, gridSquare, name
        case address1, address2, city, state, zip, country, cqZone, ituZone, license
        case latitude, longitude, stationTxRx, power, antenna, antHeight, asl
        case arrlSection, roverQth, club, email
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StationConfig()
        call = c.value(.call, default: d.call)
        `operator` = c.value(.operator, default: d.operator)
        gridSquare = c.value(.gridSquare, default: d.gridSquare)
        name = c.value(.name, default: d.name)
        address1 = c.value(.address1, default: d.address1)
        address2 = c.value(.address2, default: d.address2)
        city = c.value(.city, default: d.city)
        state = c.value(.state, default: d.state)
        zip = c.value(.zip, default: d.zip)
        country = c.value(.country, default: d.country)
        cqZone = c.value(.cqZone, default: d.cqZone)
        ituZone = c.value(.ituZone, default: d.ituZone)
        license = c.value(.license, default: d.license)
        latitude = c.value(.latitude, default: d.latitude)
        longitude = c.value(.longitude, default: d.longitude)
        stationTxRx = c.value(.stationTxRx, default: d.stationTxRx)
        power = c.value(.power, default: d.power)
        antenna = c.value(.antenna, default: d.antenna)
        antHeight = c.value(.antHeight, default: d.antHeight)
        asl = c.value(.asl, default: d.asl)
        arrlSection = c.value(.arrlSection, default: d.arrlSection)
        roverQth = c.value(.roverQth, default: d.roverQth)
        club = c.value(.club, default: d.club)
        email = c.value(.email, default: d.email)
    }

    /// Immutable `Station` for export (ADIF/Cabrillo).
    public func toStation() -> Station {
        Station(call: call, operator: `operator`, gridSquare: gridSquare, name: name)
    }

    /// Creates the configuration from a `Station` (null-safe like the Java version).
    public static func from(_ station: Station?) -> StationConfig {
        var c = StationConfig()
        if let station {
            c.call = station.call
            c.operator = station.operator
            c.gridSquare = station.gridSquare
            c.name = station.name
        }
        return c
    }
}
