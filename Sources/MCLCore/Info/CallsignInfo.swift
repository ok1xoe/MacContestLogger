import Foundation

/// Basis of the Info window's information lines about the callsign being typed — what N1MM shows as
/// `GI: EU/NORTHERN IRELAND, Zn 14, Hdg 51° LP 232° 3012mi 4847km` and
/// `Sunrise:06:29Z Sunset:18:38Z His time: 1412(Sat)`. Port of Java `info/CallsignInfo` (`record`, v1.1.1).
///
/// Pure data without formatting — the UI composes the text. Items that cannot be computed from the available data (an entity
/// without coordinates, a missing CQ zone) stay `nil`; the line is then shown shortened, but does not disappear.
///
/// Java time types are numbers here: `sunrise`/`sunset` = `LocalTime.toSecondOfDay()` (like `SolarTimes`),
/// `dxLocalTime` = `LocalTime.toNanoOfDay()` (it also carries the fraction of a second of the instant `now`).
public struct CallsignInfo: Equatable, Sendable {

    /// Java `java.time.DayOfWeek` (`getValue()`: Monday = 1 … Sunday = 7).
    public enum DayOfWeek: Int, Sendable, CaseIterable {
        case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

        /// Java `name()` (`MONDAY` …).
        public var javaName: String {
            switch self {
            case .monday: return "MONDAY"
            case .tuesday: return "TUESDAY"
            case .wednesday: return "WEDNESDAY"
            case .thursday: return "THURSDAY"
            case .friday: return "FRIDAY"
            case .saturday: return "SATURDAY"
            case .sunday: return "SUNDAY"
            }
        }
    }

    /// DXCC primary prefix.
    public let prefix: String?
    /// Entity name.
    public let entityName: String?
    /// Main continent.
    public let continent: String?
    /// CQ zone (the first of the entity's list), or `nil`.
    public let cqZone: Int?
    /// Short-path azimuth in degrees, or `nil`.
    public let shortPathDeg: Int?
    /// Long-path azimuth in degrees, or `nil`.
    public let longPathDeg: Int?
    /// Short-path distance in km, or `nil`.
    public let distanceKm: Int?
    /// The same distance in miles, or `nil`.
    public let distanceMiles: Int?
    /// Sunrise at the DX location (UTC) as a second of the day, or `nil`.
    public let sunrise: Int32?
    /// Sunset at the DX location (UTC) as a second of the day, or `nil`.
    public let sunset: Int32?
    /// Local time at the DX location as a nanosecond of the day, or `nil`.
    public let dxLocalTime: Int64?
    /// Day of the week at the DX location, or `nil`.
    public let dxDayOfWeek: DayOfWeek?

    public init(prefix: String?, entityName: String?, continent: String?, cqZone: Int?,
                shortPathDeg: Int?, longPathDeg: Int?, distanceKm: Int?, distanceMiles: Int?,
                sunrise: Int32?, sunset: Int32?, dxLocalTime: Int64?, dxDayOfWeek: DayOfWeek?) {
        self.prefix = prefix
        self.entityName = entityName
        self.continent = continent
        self.cqZone = cqZone
        self.shortPathDeg = shortPathDeg
        self.longPathDeg = longPathDeg
        self.distanceKm = distanceKm
        self.distanceMiles = distanceMiles
        self.sunrise = sunrise
        self.sunset = sunset
        self.dxLocalTime = dxLocalTime
        self.dxDayOfWeek = dxDayOfWeek
    }

    private static let kmPerMile: Double = 1.609344
    private static let nanosPerDay: Int64 = 86_400_000_000_000
    private static let nanosPerHour: Int64 = 3_600_000_000_000

    /// Builds the information about an entity relative to my position at time `now`.
    ///
    /// - azimuth `(int) Math.round(bearing) % 360`, long path `(sp + 180) % 360`, km and miles `Math.round`
    ///   (`JavaMath.round` — half toward +∞; an infinite own position gives `NaN` → 0);
    /// - local time = `now` in UTC shifted by `Math.round(lon / 15)` hours — **−2.5 → −2**, not −3 (Swift
    ///   `rounded()` rounds away from zero);
    /// - `myLat`/`myLon` `NaN` = unknown position (no azimuth and distance).
    ///
    /// Throws like Java (`DateTimeException`) for an entity with coordinates when the UTC date of `now` lies outside the
    /// `LocalDate` range (the `Instant.MIN`/`MAX` edges) or when the hour shift from a huge longitude (`±1e15`, `±∞`) comes out outside
    /// it. An entity without coordinates is returned earlier and never throws.
    public static func forEntity(_ entity: DxccEntity, myLat: Double, myLon: Double,
                                 now: JavaInstant) throws(JavaDateTimeException) -> CallsignInfo {
        var cq: Int?
        if let zones = entity.cq, let first = zones.first {
            cq = first
        }

        guard entity.hasLatLon else {
            return CallsignInfo(prefix: entity.primaryPrefix, entityName: entity.name,
                                continent: entity.primaryContinent, cqZone: cq,
                                shortPathDeg: nil, longPathDeg: nil, distanceKm: nil, distanceMiles: nil,
                                sunrise: nil, sunset: nil, dxLocalTime: nil, dxDayOfWeek: nil)
        }

        var shortPath: Int?
        var longPath: Int?
        var km: Int?
        var miles: Int?
        if !myLat.isNaN && !myLon.isNaN {
            let bearing: Double = GreatCircle.bearingDeg(myLat, myLon, entity.lat, entity.lon)
            let sp: Int32 = JavaMath.l2i(JavaMath.round(bearing)) % 360
            shortPath = Int(sp)
            longPath = Int((sp &+ 180) % 360)
            let distance: Double = GreatCircle.distanceKm(myLat, myLon, entity.lat, entity.lon)
            km = Int(JavaMath.l2i(JavaMath.round(distance)))
            miles = Int(JavaMath.l2i(JavaMath.round(distance / kmPerMile)))
        }

        // `now.atZone(UTC).toLocalDate()` — outside the `LocalDate` range it throws already here.
        let epochDay: Int64 = try JavaDateTimeException.utcEpochDay(now)
        let sun: SolarTimes? = SolarTimes.forLocation(entity.lat, entity.lon, epochDay: epochDay)

        // Time zone estimated from the longitude (15° per hour) — as in Java only approximate, without a zone table.
        let hours: Int64 = JavaMath.round(entity.lon / 15.0)
        let local = try plusHours(epochDay: epochDay, now: now, hours: hours)

        return CallsignInfo(prefix: entity.primaryPrefix, entityName: entity.name,
                            continent: entity.primaryContinent, cqZone: cq,
                            shortPathDeg: shortPath, longPathDeg: longPath, distanceKm: km, distanceMiles: miles,
                            sunrise: sun?.sunrise, sunset: sun?.sunset,
                            dxLocalTime: local.nanoOfDay, dxDayOfWeek: local.dayOfWeek)
    }

    /// `OffsetDateTime.plusHours(hours).toLocalDateTime()` in UTC (`LocalDateTime.plusWithOverflow`):
    /// days `hours / 24` (truncation), the remaining hours in nanoseconds added to the time of day with `floorDiv`/`floorMod`,
    /// a resulting date outside `LocalDate.MIN…MAX` → `DateTimeException`.
    private static func plusHours(epochDay: Int64, now: JavaInstant,
                                  hours: Int64) throws(JavaDateTimeException) -> (nanoOfDay: Int64, dayOfWeek: DayOfWeek) {
        let secondOfDay: Int64 = now.epochSecond - epochDay * 86_400
        let current: Int64 = secondOfDay * 1_000_000_000 + Int64(now.nano)
        let totNanos: Int64 = (hours % 24) * nanosPerHour + current
        let totDays: Int64 = hours / 24 + JavaMath.floorDiv(totNanos, nanosPerDay)
        let nanoOfDay: Int64 = totNanos - JavaMath.floorDiv(totNanos, nanosPerDay) * nanosPerDay
        let newDay: Int64 = epochDay + totDays
        guard newDay >= JavaDateTimeException.minEpochDay, newDay <= JavaDateTimeException.maxEpochDay else {
            throw JavaDateTimeException()
        }
        // `LocalDate.getDayOfWeek()`: `floorMod(epochDay + 3, 7)`, 0 = Monday.
        let shifted: Int64 = newDay + 3
        let index: Int64 = shifted - JavaMath.floorDiv(shifted, 7) * 7
        let day: DayOfWeek = DayOfWeek(rawValue: Int(index) + 1) ?? .monday
        return (nanoOfDay, day)
    }
}
