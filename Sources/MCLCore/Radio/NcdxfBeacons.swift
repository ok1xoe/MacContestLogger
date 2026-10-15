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
    }

    /// The beacons in transmit order (the published schedule).
    public static let beacons: [Beacon] = [
        Beacon(call: "4U1UN", location: "United Nations NY"), Beacon(call: "VE8AT", location: "Canada"),
        Beacon(call: "W6WX", location: "USA"), Beacon(call: "KH6RS", location: "Hawaii"),
        Beacon(call: "ZL6B", location: "New Zealand"), Beacon(call: "VK6RBP", location: "Australia"),
        Beacon(call: "JA2IGY", location: "Japan"), Beacon(call: "RR9O", location: "Russia"),
        Beacon(call: "VR2B", location: "Hong Kong"), Beacon(call: "4S7B", location: "Sri Lanka"),
        Beacon(call: "ZS6DN", location: "South Africa"), Beacon(call: "5Z4B", location: "Kenya"),
        Beacon(call: "4X6TU", location: "Israel"), Beacon(call: "OH2B", location: "Finland"),
        Beacon(call: "CS3B", location: "Madeira"), Beacon(call: "LU4AA", location: "Argentina"),
        Beacon(call: "OA4B", location: "Peru"), Beacon(call: "YV5B", location: "Venezuela"),
    ]

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
