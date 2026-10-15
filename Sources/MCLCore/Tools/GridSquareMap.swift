import Foundation

/// N1MM „Grid Square Map" (Window → Multipliers, VHF and up): a matrix of 4-character Maidenhead squares centred on
/// the own square (or a square the operator picked), each square coloured worked / spotted / expected / empty, with a
/// right-click menu (calls worked and spots, turn the antenna, centre, beam heading, expected list, export). Pure.
///
/// A square is addressed by its longitude index (`field × 10 + digit`, 0…179, 2° each, wrapping around the globe) and
/// its latitude index (0…179, 1° each, clamped at the poles).
public enum GridSquareMap {

    /// The state of one square, in priority order (worked beats spotted beats expected).
    public enum Cell: Sendable, Equatable {
        case worked
        case spotted
        case expected
        case empty
    }

    /// Cell colours as `0xAARRGGBB`: worked and spotted as in the multiplier windows, expected brown (N1MM).
    public static let expectedColor: UInt32 = 0xFF8D_6E63

    public static func color(_ cell: Cell) -> UInt32? {
        switch cell {
        case .worked: return MultGridLayout.workedColor
        case .spotted: return MultGridLayout.spottedColor
        case .expected: return expectedColor
        case .empty: return nil
        }
    }

    /// The 4-character square of a locator (`jn79ab` → `JN79`), `nil` for anything that is not a locator.
    public static func square(_ grid: String?) -> String? {
        guard let grid else { return nil }
        let upper: String = grid.trimmingCharacters(in: .whitespaces).uppercased()
        guard QsoSearch.isLocator(upper) else { return nil }
        return String(upper.prefix(4))
    }

    /// The longitude and latitude index of a square.
    static func indices(_ square: String) -> (lon: Int, lat: Int)? {
        guard let normalized = self.square(square) else { return nil }
        let units: [UInt8] = Array(normalized.utf8)
        let lon: Int = Int(units[0] - 0x41) * 10 + Int(units[2] - 0x30)
        let lat: Int = Int(units[1] - 0x41) * 10 + Int(units[3] - 0x30)
        return (lon, lat)
    }

    /// The square of a longitude and latitude index (the longitude wraps, a latitude off the globe is `nil`).
    static func square(lon: Int, lat: Int) -> String? {
        guard (0..<180).contains(lat) else { return nil }
        let wrapped: Int = ((lon % 180) + 180) % 180
        let chars: [UInt8] = [UInt8(0x41 + wrapped / 10), UInt8(0x41 + lat / 10), UInt8(0x30 + wrapped % 10),
                              UInt8(0x30 + lat % 10)]
        return String(decoding: chars, as: UTF8.self)
    }

    /// The square `east` squares to the east and `north` squares to the north of `square`; `nil` beyond a pole.
    public static func neighbour(_ square: String, east: Int, north: Int) -> String? {
        guard let index = indices(square) else { return nil }
        return self.square(lon: index.lon + east, lat: index.lat + north)
    }

    /// The matrix around `center`: `rows` lines from north to south, `columns` squares from west to east, the centre
    /// in the middle (even counts are made odd by one more). Squares beyond a pole are `nil`; an invalid centre gives
    /// an empty matrix.
    public static func matrix(center: String, columns: Int, rows: Int) -> [[String?]] {
        guard indices(center) != nil else { return [] }
        let cols: Int = oddCount(columns)
        let lines: Int = oddCount(rows)
        let halfCols: Int = cols / 2
        let halfRows: Int = lines / 2
        return (0..<lines).map { row in
            (0..<cols).map { col in
                neighbour(center, east: col - halfCols, north: halfRows - row)
            }
        }
    }

    /// At least 1, odd.
    public static func oddCount(_ count: Int) -> Int {
        let positive: Int = Swift.max(count, 1)
        return positive % 2 == 0 ? positive + 1 : positive
    }

    /// How many squares fit into a length (in points) with a square size; odd, at least 1.
    public static func fit(length: Double, cell: Double) -> Int {
        guard cell > 0, length.isFinite else { return 1 }
        let count: Int = Int((length / cell).rounded(.down))
        return count % 2 == 0 ? Swift.max(count - 1, 1) : count
    }

    /// A spot already reduced to its square and band.
    public struct SpotSquare: Sendable, Equatable {
        public let square: String
        public let band: Band?
        public let call: String
        public let freqHz: Int
        public let comment: String

        public init(square: String, band: Band?, call: String, freqHz: Int, comment: String = "") {
            self.square = square
            self.band = band
            self.call = call
            self.freqHz = freqHz
            self.comment = comment
        }
    }

    /// The QSOs that count for the map: not deleted, not X-QSO, with a received locator.
    public static func countedSquare(_ qso: Qso) -> String? {
        guard !qso.deleted, !qso.xqso else { return nil }
        return QsoSearch.locators(qso).first.flatMap { square($0) }
    }

    /// The state of every square that is not empty: worked on `band` (`nil` = any band), spotted on `band` and not
    /// worked, expected and neither.
    public static func cells(qsos: [Qso], spots: [SpotSquare], band: Band?, expected: Set<String>) -> [String: Cell] {
        var out: [String: Cell] = [:]
        for square in expected {
            if let normalized = self.square(square) {
                out[normalized] = .expected
            }
        }
        for spot in spots where band == nil || spot.band == band {
            if out[spot.square] != .worked {
                out[spot.square] = .spotted
            }
        }
        for qso in qsos where band == nil || qso.band == band {
            if let square = countedSquare(qso) {
                out[square] = .worked
            }
        }
        return out
    }

    /// How many squares are worked.
    public static func workedCount(_ cells: [String: Cell]) -> Int {
        cells.values.filter { $0 == .worked }.count
    }

    /// The bands of the logged QSOs and the spots, in band order (the band filter's choices).
    public static func bands(qsos: [Qso], spots: [SpotSquare]) -> [Band] {
        var seen: Set<Band> = []
        for qso in qsos where countedSquare(qso) != nil {
            if let band = qso.band {
                seen.insert(band)
            }
        }
        for spot in spots {
            if let band = spot.band {
                seen.insert(band)
            }
        }
        return Band.allCases.filter { seen.contains($0) }
    }

    /// The QSOs in a square (all bands), in log order.
    public static func qsos(in square: String, _ qsos: [Qso]) -> [Qso] {
        guard let wanted = self.square(square) else { return [] }
        return qsos.filter { countedSquare($0) == wanted }
    }

    /// N1MM „Show Beam Heading to Grid Center": the short-path bearing (whole degrees) and distance (whole km) from
    /// the own locator to the centre of the square; `nil` when either locator is invalid.
    public static func heading(from myGrid: String, to square: String) -> (bearing: Int, km: Int)? {
        guard let mine = Maidenhead.centerLatLon(myGrid), let target = Maidenhead.centerLatLon(self.square(square))
        else { return nil }
        let bearing: Int = Int(GreatCircle.bearingDeg(mine.lat, mine.lon, target.lat, target.lon).rounded()) % 360
        let km: Int = Int(Maidenhead.distanceKm(myGrid, self.square(square)).rounded())
        return (bearing, km)
    }

    /// The azimuth to the square's centre for the rotator; `nil` when either locator is invalid.
    public static func azimuth(from myGrid: String, to square: String) -> Double? {
        guard let mine = Maidenhead.centerLatLon(myGrid), let target = Maidenhead.centerLatLon(self.square(square))
        else { return nil }
        return GreatCircle.bearingDeg(mine.lat, mine.lon, target.lat, target.lon)
    }

    /// N1MM „Export Mults & Bands from this Contest": every worked square with its worked bands in MHz
    /// (`JN79 144 432`), sorted; readable back as an expected list (the first word of a line counts).
    public static func export(qsos: [Qso]) -> String {
        var bandsBySquare: [String: Set<Band>] = [:]
        for qso in qsos {
            guard let square = countedSquare(qso) else { continue }
            var bands: Set<Band> = bandsBySquare[square] ?? []
            if let band = qso.band {
                bands.insert(band)
            }
            bandsBySquare[square] = bands
        }
        return bandsBySquare.keys.sorted().map { square in
            let bands: [String] = Band.allCases.filter { bandsBySquare[square]?.contains($0) == true }.map(mhz)
            return ([square] + bands).joined(separator: " ") + "\n"
        }.joined()
    }

    /// The lower edge of a band in whole MHz (`0.1357` stays as it is below 1 MHz).
    static func mhz(_ band: Band) -> String {
        let value: Double = Double(band.lowHz) / 1_000_000
        return value >= 1 ? String(Int(value)) : String(value)
    }
}
