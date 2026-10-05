import Foundation
import Testing
@testable import MCLCore

/// Review 3 focus: replay of a large log (10,000 QSOs) in a reasonable time. The log is
/// synthetic like in the Java probe `ProbeTiming` (20 prefixes, 5 bands, CW, zone 1–40,
/// a QSO every 15 s). The time is printed; the limit is only a safeguard against an order-of-magnitude slowdown (debug,
/// concurrently running tests), not a measurement.
@Suite(.serialized) struct ReplayPerformanceTests {

    static let prefixes = ["DL", "W", "K", "OK", "OM", "G", "F", "I", "EA", "JA",
                           "VE", "UA", "SP", "HA", "LZ", "YO", "PY", "LU", "VK", "ZS"]
    static let freqs = [3_510_000, 7_010_000, 14_010_000, 21_010_000, 28_010_000]

    /// Deterministic log (own LCG, independent of `SystemRandomNumberGenerator`).
    static func log(_ n: Int, freqs: [Int] = freqs, exchange: (Int) -> String) -> [Qso] {
        var seed: UInt64 = 42
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var out: [Qso] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            var q = Qso()
            q.id = Int64(i)
            q.timestampUtc = Date(timeIntervalSince1970: TimeInterval(1_795_824_000 + 15 * i))
            q.call = prefixes[next(prefixes.count)] + String(next(10))
                + String([letters[next(26)], letters[next(26)], letters[next(26)]])
            q.freqHz = freqs[next(freqs.count)]
            q.mode = .cw
            q.exchangeRcvd = exchange(next(1_000))
            out.append(q)
        }
        return out
    }

    static func measure(_ definition: String, myGrid: String? = nil, myItuZone: String? = nil,
                        freqs: [Int] = freqs,
                        exchange: @escaping (Int) -> String) throws -> (Duration, ContestReplay.Outcome) {
        let qsos = log(10_000, freqs: freqs, exchange: exchange)
        let session = try SessionFixture.session(definition, myCall: "OK1XOE", myGrid: myGrid,
                                                 myItuZone: myItuZone)
        let clock = ContinuousClock()
        var outcome: ContestReplay.Outcome?
        let elapsed = clock.measure { outcome = ContestReplay.replay(session, qsos) }
        return (elapsed, try #require(outcome))
    }

    @Test func tenThousandQsoCqWwCw() throws {
        let (elapsed, out) = try Self.measure("@cq-ww-cw.yaml") { "599 \(1 + $0 % 40)" }
        print("ContestReplay cq-ww-cw 10 000 QSO: \(elapsed)")
        #expect(out.replayed == 10_000)
        #expect(out.skipped == 0)
        #expect(elapsed < .seconds(30))
    }

    @Test func tenThousandQsoIaruHf() throws {
        let (elapsed, out) = try Self.measure("@iaru-hf.yaml", myItuZone: "28") {
            $0 % 10 == 0 ? "599 DARC" : "599 \(1 + $0 % 75)"
        }
        print("ContestReplay iaru-hf 10 000 QSO: \(elapsed)")
        #expect(out.replayed == 10_000)
        #expect(out.skipped == 0)
        #expect(elapsed < .seconds(30))
    }

    /// Scoring per km (`perKm`) and regex validation of the locator; locators from an 18 × 10 field grid.
    @Test func tenThousandQsoIaruR1Vhf() throws {
        let letters = Array("ABCDEFGHIJKLMNOPQR")
        let (elapsed, out) = try Self.measure("@iaru-r1-vhf.yaml", myGrid: "JO70FD",
                                              freqs: [144_300_000]) { n in
            let field = String([letters[n % 18], letters[(n / 18) % 18]])
            return "599 \(1 + n) " + field + String(n % 10) + String((n / 10) % 10) + "AA"
        }
        print("ContestReplay iaru-r1-vhf 10 000 QSO: \(elapsed)")
        #expect(out.replayed == 10_000)
        #expect(out.skipped == 0)
        #expect(elapsed < .seconds(30))
    }
}
