import Foundation

/// The NCDXF/IARU International Beacon Project (N1MM shows "the beacon transmitting at that time" in the entry
/// window's status line when you listen on one of its frequencies): 18 beacons, each sending for 10 seconds on 14100,
/// 18110, 21150, 24930 and 28200 kHz in turn, a 3-minute cycle that starts at 00:00:00 UTC (every whole 3 minutes).
/// In each 10-second slot the beacons on the five bands follow one another: the beacon on 18110 kHz is the one that
/// was on 14100 kHz in the previous slot. Pure; the time comes from the caller (the PC clock must be right).
extension NcdxfBeacons {

    public struct Beacon: Equatable, Sendable {
        public let call: String
        public let location: String
        /// The beacon's published Maidenhead locator (for the bearing).
        public let grid: String

        public init(call: String, location: String, grid: String = "") {
            self.call = call
            self.location = location
            self.grid = grid
        }
    }

    /// The beacons in transmit order (the published schedule and locators).
    public static let beacons: [Beacon] = [
        Beacon(call: "4U1UN", location: "United Nations NY", grid: "FN30AS"),
        Beacon(call: "VE8AT", location: "Canada", grid: "EQ79AX"),
        Beacon(call: "W6WX", location: "USA", grid: "CM97BD"),
        Beacon(call: "KH6RS", location: "Hawaii", grid: "BL10TS"),
        Beacon(call: "ZL6B", location: "New Zealand", grid: "RE78TW"),
        Beacon(call: "VK6RBP", location: "Australia", grid: "OF87AV"),
        Beacon(call: "JA2IGY", location: "Japan", grid: "PM84JK"),
        Beacon(call: "RR9O", location: "Russia", grid: "NO14KX"),
        Beacon(call: "VR2B", location: "Hong Kong", grid: "OL72BG"),
        Beacon(call: "4S7B", location: "Sri Lanka", grid: "NJ06CF"),
        Beacon(call: "ZS6DN", location: "South Africa", grid: "KG44DE"),
        Beacon(call: "5Z4B", location: "Kenya", grid: "KI88MX"),
        Beacon(call: "4X6TU", location: "Israel", grid: "KM72JB"),
        Beacon(call: "OH2B", location: "Finland", grid: "KP20BM"),
        Beacon(call: "CS3B", location: "Madeira", grid: "IM12OR"),
        Beacon(call: "LU4AA", location: "Argentina", grid: "GF05TJ"),
        Beacon(call: "OA4B", location: "Peru", grid: "FH17MW"),
        Beacon(call: "YV5B", location: "Venezuela", grid: "FJ69CC"),
    ]

    /// N1MM Tools „Tune to beacon for this band": the beacon frequency of the band `freqHz` is on (20, 17, 15, 12
    /// or 10 m); `nil` on any other band.
    public static func beaconFrequency(forBandOf freqHz: Int64) -> Int64? {
        guard let band = Band.from(frequencyHz: Int(clamping: freqHz)) else { return nil }
        let bands: [Band] = [.m20, .m17, .m15, .m12, .m10]
        guard let index = bands.firstIndex(of: band) else { return nil }
        return Int64(frequenciesHz[index])
    }

    /// The bearing from `myGrid` to the beacon in whole degrees `0…359`; `nil` when a locator is invalid.
    public static func bearing(from myGrid: String, to beacon: Beacon) -> Int? {
        guard let mine = Maidenhead.centerLatLon(myGrid), let there = Maidenhead.centerLatLon(beacon.grid) else {
            return nil
        }
        return Int(GreatCircle.bearingDeg(mine.lat, mine.lon, there.lat, there.lon).rounded()) % 360
    }

    /// How far the tuned frequency may be from a beacon frequency (the CW passband).
    public static let toleranceHz: Int64 = 1_000

    /// The length of one transmission and of the whole cycle, in seconds.
    public static let slotSeconds: Int64 = 10
    public static let cycleSeconds: Int64 = 180

    /// The index of the beacon frequency `freqHz` is tuned to, `nil` = none.
    public static func frequencyIndex(_ freqHz: Int64) -> Int? {
        // `frequenciesHz` is in the order a beacon visits the bands.
        frequenciesHz.firstIndex { abs(Int64($0) - freqHz) <= toleranceHz }
    }

    /// The beacon transmitting on the frequency `freqHz` is tuned to at `date`; `nil` = not tuned to a beacon
    /// frequency.
    public static func transmitting(freqHz: Int64, at date: Date) -> Beacon? {
        guard let band = frequencyIndex(freqHz) else { return nil }
        let seconds: Int64 = Int64(floor(date.timeIntervalSince1970))
        let inCycle: Int64 = ((seconds % cycleSeconds) + cycleSeconds) % cycleSeconds
        let slot: Int = Int(inCycle / slotSeconds)
        let count: Int = beacons.count
        return beacons[((slot - band) % count + count) % count]
    }

    /// The info strip text: `NCDXF 4U1UN (United Nations NY)`.
    public static func stripText(_ beacon: Beacon) -> String {
        "NCDXF " + beacon.call + " (" + beacon.location + ")"
    }
}
