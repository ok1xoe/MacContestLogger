/// Antenna selection by band and azimuth (N1MM "Auto-select Antenna Based on Azimuth to
/// Station", band decoder): from the antennas for the given band it picks the one whose sector contains the
/// azimuth, otherwise the first; `next` cycles between the band's antennas. Mirrors the Java `radio.AntennaSelector`.
///
/// **Identity.** The Java `AntennaEntry` has no `equals`, so `next` looks for the current antenna
/// (`indexOf`) **by instance identity**: two value-identical antennas in the table are different
/// and a foreign instance (e.g. after reloading the configuration) is not found → the band's first antenna.
/// The Swift `AntennaEntry` is a value, so `select` and `next` work with the **position in the table
/// `all`** — that is the identity here. A caller that replaces the table must discard the position
/// (`nil` = a Java foreign instance). Rules for the caller:
/// (a) keep the `Int?` position for identity and the `AntennaEntry?` value separately for display;
/// (b) on **every** write of `config.antennas` (every save of the Configurer — Java replaces the instances
/// even without a change) set the position to `nil` and keep the value; (c) convert the Java shortcut
/// `currentAntenna === a` to `position != nil && position == new position`
/// (a deliberate divergence from Java v1.1.1).
public enum AntennaSelector {

    /// Java `split("[,;\\s]+")` — `\s` is ASCII (NBSP and U+2003 do not separate bands).
    private static let bandSeparator: JavaRegex = {
        do {
            return try JavaRegex("[,;\\s]+")
        } catch {
            preconditionFailure("pevný vzor oddělovače pásem musí jít zkompilovat: \(error)")
        }
    }()

    /// Java `split("-")`.
    private static let sectorSeparator: JavaRegex = {
        do {
            return try JavaRegex("-")
        } catch {
            preconditionFailure("pevný vzor oddělovače sektoru musí jít zkompilovat: \(error)")
        }
    }()

    /// Antennas usable on the band, in table order.
    public static func forBand(_ all: [AntennaEntry], band: Band) -> [AntennaEntry] {
        all.filter { covers($0, band) }
    }

    /// Positions of the band's antennas in `all` (Java `forBand`, but with identity = position).
    private static func candidates(_ all: [AntennaEntry], band: Band) -> [Int] {
        all.indices.filter { covers(all[$0], band) }
    }

    /// Antenna for a band: the first whose non-empty sector contains `azimuth`, otherwise the first
    /// antenna of the band; `nil` if the band has none.
    /// - Returns: position of the selected antenna in `all`.
    public static func select(_ all: [AntennaEntry], band: Band, azimuth: Int?) -> Int? {
        let indices = candidates(all, band: band)
        guard let first = indices.first else { return nil }
        if let azimuth {
            for index in indices where !JavaText.isBlank(all[index].sector) && inSector(all[index].sector, azimuth) {
                return index
            }
        }
        return first
    }

    /// Next antenna of the band after the antenna at position `currentIndex` (cyclically). If the current
    /// antenna is not among the band's antennas (or `nil`), returns the band's first antenna (Java `indexOf` = −1).
    /// - Returns: position of the next antenna in `all`.
    public static func next(_ all: [AntennaEntry], band: Band, currentIndex: Int?) -> Int? {
        let indices = candidates(all, band: band)
        guard !indices.isEmpty else { return nil }
        let i: Int = currentIndex.flatMap { indices.firstIndex(of: $0) } ?? -1
        return indices[(i + 1) % indices.count]
    }

    /// Does the antenna cover the band? The `bands` items (split by `[,;\s]+`) are an ADIF notation
    /// (`20m`, after `toLowerCase(ROOT)`) or MHz via Java `Double.parseDouble`
    /// (`14d`, `1e1`, `0x1.cp3`, not `١٤`) rounded by `Math.round` to Hz, with a lower
    /// tolerance of 500 kHz. A comma splits items, so `14,5` = 20 m and 60 m.
    static func covers(_ antenna: AntennaEntry, _ band: Band) -> Bool {
        for raw in JavaText.split(antenna.bands, regex: bandSeparator, limit: 0) {
            let token = JavaText.toLowerCase(JavaText.trim(raw))
            if token.isEmpty {
                continue
            }
            if token == band.adif {
                return true
            }
            // Java `t.replace(',', '.')` — after splitting by comma none remain.
            guard let mhz = JavaDouble.parseDouble(token) else {
                continue // not a number — ADIF notation only
            }
            let hz = JavaMath.round(mhz * 1_000_000)
            if hz >= Int64(band.lowHz - 500_000) && hz <= Int64(band.highHz) {
                return true
            }
        }
        return false
    }

    /// Sector `from-to` in degrees, also across north (`300-60`). A different number of parts after
    /// `split("-")` (`-10-20`, `45`, empty) and non-numeric bounds (`Integer.parseInt`:
    /// accepts `+10` and `١`, not a space inside) mean "always". The azimuth is a Java `int`
    /// normalised as `((az % 360) + 360) % 360`.
    static func inSector(_ sector: String, _ azimuth: Int) -> Bool {
        let parts = JavaText.split(sector, regex: sectorSeparator, limit: 0)
        if parts.count != 2 {
            return true
        }
        guard let from = JavaInteger.parseInt(JavaText.trim(parts[0])),
              let to = JavaInteger.parseInt(JavaText.trim(parts[1])) else {
            return true
        }
        let az = ((Int(Int32(truncatingIfNeeded: azimuth)) % 360) + 360) % 360
        let lower = Int(from)
        let upper = Int(to)
        return lower <= upper ? az >= lower && az <= upper : az >= lower || az <= upper
    }
}
