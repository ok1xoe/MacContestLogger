import Foundation
import Testing
@testable import MCLCore

/// The ARRL VHF contests with the 222 and 902 MHz bands: January / June / September VHF (grid squares per band)
/// and the 222 MHz and Up Distance Contest (distance times band factor), scored from the published definitions.
@Suite struct ArrlVhfContestsTests {

    static let at = Date(timeIntervalSince1970: 1_781_380_800)   // 2026-06-13 20:00 UTC

    static func session(_ id: String, myGrid: String) throws -> ContestSession {
        let dxcc = try SessionFixture.dxcc()
        let root = PublishedContestDataTests.root
        let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(root.appendingPathComponent("multipliers"))
        let definition = try ContestDefinitionLoader.loadFile(root.appendingPathComponent("contests/\(id).yaml"))
        return ContestSession(definition: definition, dxcc: dxcc, registry: registry, myCall: "K1TTT", myGrid: myGrid)
    }

    /// Every band a published definition names (its band list and its `bandIn` conditions) is a band the program
    /// knows: a misspelt band would silently score nothing.
    @Test func publishedDefinitionsNameOnlyKnownBands() throws {
        let contests = PublishedContestDataTests.root.appendingPathComponent("contests")
        for definition in try ContestCatalog.fromDir(contests) {
            var names: [String] = (definition.bands ?? []).compactMap { $0 }
            for case let rule? in definition.scoring?.qsoPoints?.rules ?? [] {
                names += (rule.when?.bandIn ?? []).compactMap { $0 }
            }
            for case let factor? in definition.scoring?.qsoPoints?.factors ?? [] {
                names += (factor.when?.bandIn ?? []).compactMap { $0 }
            }
            for name in names {
                #expect(Band.from(adif: name) != nil, "\(definition.id ?? "?"): \(name)")
            }
        }
    }

    /// One QSO with the same grid on every band group: 50, 144, 222, 432, 902, 1296 MHz, 2.3 and 24 GHz.
    static let bands: [String] = ["6m", "2m", "1.25m", "70cm", "33cm", "23cm", "13cm", "1.25cm"]

    @Test(arguments: [("arrl-vhf-jan", 1 + 1 + 2 + 2 + 4 + 4 + 8 + 8), ("arrl-vhf-jun", 1 + 1 + 2 + 2 + 3 + 3 + 4 + 4),
                      ("arrl-vhf-sep", 1 + 1 + 2 + 2 + 3 + 3 + 4 + 4)])
    func vhfContestsScoreEveryBand(id: String, points: Int) throws {
        let session = try Self.session(id, myGrid: "FN32")
        #expect(session.definition.bands?.contains("1.25m") == true && session.definition.bands?.contains("33cm") == true)
        for band in Self.bands {
            _ = try session.log(call: "W1AW", band: band, mode: "SSB", receivedRaw: SessionFixture.raw(("grid", "FN31")),
                                at: Self.at)
        }
        // A rover in another grid is a new station and a new multiplier on 222 MHz.
        _ = try session.log(call: "K1RZ/R", band: "1.25m", mode: "SSB", receivedRaw: SessionFixture.raw(("grid", "FN41")),
                            at: Self.at)
        _ = try session.log(call: "K1RZ/R", band: "1.25m", mode: "SSB", receivedRaw: SessionFixture.raw(("grid", "FN42")),
                            at: Self.at)
        let score = try session.score()
        #expect(score.qsoPoints == Int64(points + 2 + 2), "\(id)")
        #expect(score.multTotal == Int32(Self.bands.count + 2), "\(id)")
        #expect(score.total == Int64((points + 4) * (Self.bands.count + 2)), "\(id)")
    }

    /// The scoring example of the official rules (W9JJ in EN44XA): 294 + 30 + 346 + 347 + 1 388 + 2 = 2 407.
    @Test func distanceContestMatchesTheRulesExample() throws {
        let session = try Self.session("arrl-222", myGrid: "EN44XA")
        let qsos: [(String, String, String, Int)] = [
            ("K9JK/R", "EN44BC", "23cm", 294), ("W9XA/R", "EN43XX", "3cm", 30), ("K8QYZ/R", "EN74DE", "70cm", 346),
            ("K8QYZ/R", "EN73AA", "70cm", 347), ("K8QYZ/R", "EN73AA", "33cm", 1_388), ("W9FZ/R", "EN44XA", "23cm", 2),
        ]
        for (call, grid, band, points) in qsos {
            let qso = try session.log(call: call, band: band, mode: "CW", receivedRaw: SessionFixture.raw(("grid", grid)),
                                      at: Self.at)
            #expect(qso.points == Int32(points), "\(call) \(grid) \(band)")
        }
        let score = try session.score()
        #expect(score.total == 2_407)
        #expect(score.multTotal == 0)
    }

    /// The band factors of the 222 MHz and Up contest: 222 ×2, 902 ×4, 3.4/5.7 GHz ×10, 24 GHz and up ×20; the same
    /// locator counts 1 km.
    @Test func distanceContestBandFactors() throws {
        let session = try Self.session("arrl-222", myGrid: "FN31PR")
        let factors: [(String, Int)] = [("1.25m", 2), ("70cm", 1), ("33cm", 4), ("23cm", 2), ("13cm", 6), ("9cm", 10),
                                        ("6cm", 10), ("3cm", 6), ("1.25cm", 20), ("6mm", 20), ("4mm", 20), ("2.5mm", 20),
                                        ("2mm", 20), ("1mm", 20)]
        for (band, factor) in factors {
            let qso = try session.log(call: "W1AW", band: band, mode: "CW",
                                      receivedRaw: SessionFixture.raw(("grid", "FN31PR")), at: Self.at)
            #expect(qso.points == Int32(factor), "\(band)")
        }
        // Once per band from a locator.
        let dupe = try session.log(call: "W1AW", band: "33cm", mode: "SSB",
                                   receivedRaw: SessionFixture.raw(("grid", "FN31PR")), at: Self.at)
        #expect(dupe.points == 0)
    }
}
