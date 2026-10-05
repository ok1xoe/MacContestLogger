import Foundation

/// DXCC entity derived from `~/dxcc-json/dxcc.json` (or from `cty.dat`).
///
/// Port of the Java `dxcc/DxccEntity.java` (`record`). Note: `cq`/`itu` are
/// **lists** -- large countries span several zones (Canada, USA, Russia). For
/// a zone multiplier the value is therefore taken from the exchange, and the entity's zones serve only
/// for a cross-check; the entity itself is the country multiplier.
///
/// All reference fields are optional, because the Java record validates nothing
/// and `DxccResolver` really does pass `null` into it (measured: an entity without `name`,
/// `countryCode`, `continent`, `cq`, `itu` is built from a `dxcc.json` without those keys
/// and goes through). An empty list is not the same as a missing list.
///
/// The list **elements** are optional too: the Java `List<Integer>`/`List<String>`
/// tolerate `null` and Jackson lets it through from the data (measured: `"cq":[15,null]` ->
/// `cq=[15, null]`, `"continent":[null]` -> `continents=[null]`, and
/// `primaryContinent()` then returns `null`). A zero in place of such an element would not be
/// a "missing value", but **a different zone number**.
///
/// - `entityCode`: DXCC entity number -- only an **internal identity**; from `cty.dat` it is
///   the order of the record in the file, not the DXCC number.
/// - `name`: country name.
/// - `countryCode`: ISO-like code (CZ, US, CA, DE...).
/// - `continents`: continents (usually 1, exceptionally more); the order is significant.
/// - `cq`: CQ zones of the entity.
/// - `itu`: ITU zones of the entity.
/// - `lat`: latitude (north positive), `NaN` = unknown.
/// - `lon`: longitude (east positive), `NaN` = unknown.
/// - `primaryPrefix`: DXCC primary prefix (OK, DL, F, CE9...); exact only from `cty.dat`.
/// - `adifDxcc`: DXCC entity number for ADIF, `nil` = unknown. This field belongs
///   outside (ADIF, LoTW), not `entityCode`.
public struct DxccEntity: Equatable, Sendable {

    public let entityCode: Int
    public let name: String?
    public let countryCode: String?
    public let continents: [String?]?
    public let cq: [Int?]?
    public let itu: [Int?]?
    public let lat: Double
    public let lon: Double
    public let primaryPrefix: String?
    public let adifDxcc: Int?

    /// Canonical constructor with all ten fields.
    public init(entityCode: Int, name: String?, countryCode: String?, continents: [String?]?,
                cq: [Int?]?, itu: [Int?]?, lat: Double, lon: Double,
                primaryPrefix: String?, adifDxcc: Int?) {
        self.entityCode = entityCode
        self.name = name
        self.countryCode = countryCode
        self.continents = continents
        self.cq = cq
        self.itu = itu
        self.lat = lat
        self.lon = lon
        self.primaryPrefix = primaryPrefix
        self.adifDxcc = adifDxcc
    }

    /// Constructor without a number for ADIF -- uses `entityCode`. Applies to data
    /// from `dxcc.json`, where both numbers are identical; `cty.dat` must supply the number
    /// separately, otherwise the record order would leak outside.
    public init(entityCode: Int, name: String?, countryCode: String?, continents: [String?]?,
                cq: [Int?]?, itu: [Int?]?, lat: Double, lon: Double, primaryPrefix: String?) {
        self.init(entityCode: entityCode, name: name, countryCode: countryCode,
                  continents: continents, cq: cq, itu: itu, lat: lat, lon: lon,
                  primaryPrefix: primaryPrefix, adifDxcc: entityCode)
    }

    /// Backward-compatible constructor without a prefix (prefix = `countryCode`).
    public init(entityCode: Int, name: String?, countryCode: String?, continents: [String?]?,
                cq: [Int?]?, itu: [Int?]?, lat: Double, lon: Double) {
        self.init(entityCode: entityCode, name: name, countryCode: countryCode,
                  continents: continents, cq: cq, itu: itu, lat: lat, lon: lon,
                  primaryPrefix: countryCode, adifDxcc: entityCode)
    }

    /// Primary continent (first in the list) or `nil`.
    ///
    /// `nil` means both of what `null` means in Java: the list is missing, is empty,
    /// **or its first element is `null`** (measured: `"continent":[null,"EU"]` ->
    /// `primaryContinent()` = `null`).
    public var primaryContinent: String? {
        guard let continents, !continents.isEmpty else { return nil }
        return continents[0]
    }

    /// True when the entity has valid coordinates (for azimuth).
    public var hasLatLon: Bool {
        !lat.isNaN && !lon.isNaN
    }

    /// Equality copies the Java `record`, which compares `double` via
    /// `Double.compare`, not via `==`. Measured on Java v1.1.1:
    /// two entities with `NaN` coordinates are **equal** (`EQ[NaN==NaN] true`),
    /// whereas `0.0` and `-0.0` are **not** (`EQ[0.0==-0.0] false`). Swift's `Double.==`
    /// says the exact opposite for both, so a synthesized equality would be wrong here --
    /// and `DxccResolver` builds all entities precisely with `NaN`.
    public static func == (a: DxccEntity, b: DxccEntity) -> Bool {
        a.entityCode == b.entityCode
            && a.name == b.name
            && a.countryCode == b.countryCode
            && a.continents == b.continents
            && a.cq == b.cq
            && a.itu == b.itu
            && javaDoubleEquals(a.lat, b.lat)
            && javaDoubleEquals(a.lon, b.lon)
            && a.primaryPrefix == b.primaryPrefix
            && a.adifDxcc == b.adifDxcc
    }

    /// `Double.compare(a, b) == 0` from Java: all `NaN`s are equal and zero is
    /// distinguished by its sign.
    private static func javaDoubleEquals(_ a: Double, _ b: Double) -> Bool {
        if a.isNaN || b.isNaN { return a.isNaN && b.isNaN }
        return a.bitPattern == b.bitPattern
    }
}
