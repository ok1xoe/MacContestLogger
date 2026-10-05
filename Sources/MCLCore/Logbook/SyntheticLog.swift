import Foundation

/// A seeded synthetic CQ WW CW log for performance measurements (open, replay, sort, search and
/// insert over 20,000 QSOs). Not a feature of the application: `mcl-synthlog` writes it into a database, the
/// measurement tests read it in memory.
///
/// The log looks like a real contest weekend: the six contest bands weighted towards 40 m and 20 m, mixed DXCC
/// prefixes (European, North American, Asian, Oceanian, African and South American calls, some with a fixed call area
/// digit), the CQ zone of the prefix in the received exchange (`599 <zone>`), one QSO every 4–12 seconds within
/// 48 hours, and about 2 % dupes (an earlier call worked again on the same band). The same seed gives the same log.
public enum SyntheticLog {

    /// One prefix of the generator: the letters before the call area digit, the digits it uses and its CQ zone.
    struct Prefix {
        let letters: String
        let digits: String
        let zone: Int
        let weight: Int
    }

    /// Prefixes with a rough contest weight (Europe dominant, as in a European station's CQ WW log).
    static let prefixes: [Prefix] = [
        Prefix(letters: "DL", digits: "0123456789", zone: 14, weight: 60),
        Prefix(letters: "OK", digits: "12", zone: 15, weight: 30),
        Prefix(letters: "OM", digits: "0123456789", zone: 15, weight: 15),
        Prefix(letters: "SP", digits: "0123456789", zone: 15, weight: 30),
        Prefix(letters: "HA", digits: "0123456789", zone: 15, weight: 15),
        Prefix(letters: "S5", digits: "0123456789", zone: 15, weight: 10),
        Prefix(letters: "9A", digits: "0123456789", zone: 15, weight: 10),
        Prefix(letters: "I", digits: "0123456789", zone: 15, weight: 35),
        Prefix(letters: "F", digits: "123456789", zone: 14, weight: 25),
        Prefix(letters: "G", digits: "0123456789", zone: 14, weight: 30),
        Prefix(letters: "EA", digits: "1234567", zone: 14, weight: 25),
        Prefix(letters: "EA", digits: "8", zone: 33, weight: 4),
        Prefix(letters: "CT", digits: "12", zone: 14, weight: 6),
        Prefix(letters: "PA", digits: "0123456789", zone: 14, weight: 15),
        Prefix(letters: "ON", digits: "4567", zone: 14, weight: 10),
        Prefix(letters: "OH", digits: "0123456789", zone: 15, weight: 12),
        Prefix(letters: "SM", digits: "0123456789", zone: 14, weight: 12),
        Prefix(letters: "LA", digits: "0123456789", zone: 14, weight: 8),
        Prefix(letters: "OZ", digits: "0123456789", zone: 14, weight: 8),
        Prefix(letters: "UA", digits: "1346", zone: 16, weight: 30),
        Prefix(letters: "UA", digits: "9", zone: 17, weight: 10),
        Prefix(letters: "UR", digits: "0123456789", zone: 16, weight: 15),
        Prefix(letters: "YO", digits: "2345689", zone: 20, weight: 10),
        Prefix(letters: "LZ", digits: "12345", zone: 20, weight: 10),
        Prefix(letters: "SV", digits: "123456789", zone: 20, weight: 6),
        Prefix(letters: "4X", digits: "1456", zone: 20, weight: 3),
        Prefix(letters: "K", digits: "0123456789", zone: 5, weight: 40),
        Prefix(letters: "W", digits: "0123456789", zone: 4, weight: 40),
        Prefix(letters: "N", digits: "6", zone: 3, weight: 8),
        Prefix(letters: "VE", digits: "1234567", zone: 5, weight: 10),
        Prefix(letters: "KH", digits: "6", zone: 31, weight: 2),
        Prefix(letters: "KL", digits: "7", zone: 1, weight: 2),
        Prefix(letters: "XE", digits: "123", zone: 6, weight: 3),
        Prefix(letters: "PY", digits: "1234567", zone: 11, weight: 8),
        Prefix(letters: "LU", digits: "123456789", zone: 13, weight: 5),
        Prefix(letters: "CE", digits: "1234", zone: 12, weight: 3),
        Prefix(letters: "JA", digits: "0123456789", zone: 25, weight: 15),
        Prefix(letters: "BY", digits: "14", zone: 24, weight: 3),
        Prefix(letters: "HL", digits: "15", zone: 25, weight: 3),
        Prefix(letters: "VU", digits: "23", zone: 22, weight: 2),
        Prefix(letters: "A", digits: "6", zone: 21, weight: 2),
        Prefix(letters: "VK", digits: "234567", zone: 30, weight: 5),
        Prefix(letters: "ZL", digits: "1234", zone: 32, weight: 2),
        Prefix(letters: "ZS", digits: "1256", zone: 38, weight: 3),
        Prefix(letters: "CN", digits: "8", zone: 33, weight: 2),
        Prefix(letters: "5B", digits: "4", zone: 20, weight: 2),
    ]

    /// A CQ WW band with its share of the fresh QSOs (percent) and a CW frequency range (kHz) inside the band.
    struct BandShare {
        let band: Band
        let percent: Int
        let lowKHz: Int
        let highKHz: Int
    }

    static let bands: [BandShare] = [
        BandShare(band: .m160, percent: 5, lowKHz: 1_810, highKHz: 1_850),
        BandShare(band: .m80, percent: 12, lowKHz: 3_500, highKHz: 3_560),
        BandShare(band: .m40, percent: 28, lowKHz: 7_000, highKHz: 7_040),
        BandShare(band: .m20, percent: 30, lowKHz: 14_000, highKHz: 14_060),
        BandShare(band: .m15, percent: 15, lowKHz: 21_000, highKHz: 21_060),
        BandShare(band: .m10, percent: 10, lowKHz: 28_000, highKHz: 28_060),
    ]

    /// Share of dupes in permille.
    static let dupePermille = 20

    /// SplitMix64: a fixed, documented generator, so a seed gives the same log on every platform and Swift version.
    struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed: UInt64 = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }

        /// A value in `0..<bound` (`bound > 0`).
        mutating func below(_ bound: Int) -> Int {
            Int(next() % UInt64(bound))
        }
    }

    /// Generates `count` QSOs of contest `contestId` starting at `start`. The QSOs have no `id` (the logbook assigns
    /// it) but a deterministic `uuid`; `serialSent` counts from 1, `exchangeSent` is `599 <ownZone>`.
    public static func generate(count: Int, seed: UInt64, contestId: String, start: Date,
                                ownZone: Int = 15) -> [Qso] {
        var random = Generator(state: seed)
        let totalWeight: Int = prefixes.reduce(0) { $0 + $1.weight }
        var out: [Qso] = []
        out.reserveCapacity(max(0, count))
        var seconds: Int = 0
        for index in 0..<max(0, count) {
            seconds += 4 + random.below(9)
            let isDupe: Bool = !out.isEmpty && random.below(1_000) < dupePermille
            var qso = Qso()
            if isDupe {
                let earlier: Qso = out[random.below(out.count)]
                qso.call = earlier.call
                qso.freqHz = earlier.freqHz
                qso.exchangeRcvd = earlier.exchangeRcvd
            } else {
                let prefix: Prefix = pickPrefix(&random, totalWeight: totalWeight)
                qso.call = call(prefix, &random)
                qso.freqHz = frequencyHz(&random)
                qso.exchangeRcvd = "599 " + String(prefix.zone)
            }
            qso.timestampUtc = start.addingTimeInterval(TimeInterval(min(seconds, 48 * 3_600 - 1)))
            qso.mode = .cw
            qso.rstSent = "599"
            qso.rstRcvd = "599"
            qso.exchangeSent = "599 " + String(ownZone)
            qso.serialSent = index + 1
            qso.runMode = random.below(10) < 6 ? .run : .searchAndPounce
            qso.contestId = contestId
            qso.uuid = uuid(&random)
            out.append(qso)
        }
        return out
    }

    private static func pickPrefix(_ random: inout Generator, totalWeight: Int) -> Prefix {
        var target: Int = random.below(totalWeight)
        for prefix in prefixes {
            if target < prefix.weight {
                return prefix
            }
            target -= prefix.weight
        }
        return prefixes[prefixes.count - 1]
    }

    private static let letters: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private static func call(_ prefix: Prefix, _ random: inout Generator) -> String {
        let digits: [Character] = Array(prefix.digits)
        var text: String = prefix.letters
        text.append(digits[random.below(digits.count)])
        let suffixLength: Int = 2 + random.below(2)
        for _ in 0..<suffixLength {
            text.append(letters[random.below(letters.count)])
        }
        return text
    }

    private static func frequencyHz(_ random: inout Generator) -> Int {
        var target: Int = random.below(100)
        for entry in bands {
            if target < entry.percent {
                let kHz: Int = entry.lowKHz + random.below(entry.highKHz - entry.lowKHz)
                return kHz * 1_000 + random.below(10) * 100
            }
            target -= entry.percent
        }
        return 14_025_000
    }

    private static func uuid(_ random: inout Generator) -> String {
        let high: UInt64 = random.next()
        let low: UInt64 = random.next()
        var bytes: [UInt8] = []
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: high >> UInt64(shift)))
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: low >> UInt64(shift)))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        var text: String = ""
        for (index, byte) in bytes.enumerated() {
            if index == 4 || index == 6 || index == 8 || index == 10 {
                text += "-"
            }
            let hex = String(byte, radix: 16)
            text += hex.count == 1 ? "0" + hex : hex
        }
        return text
    }
}
