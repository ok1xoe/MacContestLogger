import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `NewContestsTest` (4): catalog of new contests and their scoring through a session.
@Suite struct NewContestsTests {

    let dxcc: DxccResolver
    let registry: MultiplierSetRegistry
    let defs: [ContestDefinition]

    init() throws {
        dxcc = try SessionFixture.dxcc()
        registry = try SessionFixture.registry(dxcc)
        defs = try ContestCatalog.fromDir(try SessionFixture.contestData().appendingPathComponent("contests"))
    }

    private func session(_ id: String, _ grid: String?) throws -> ContestSession {
        let d = try #require(defs.first { JavaText.equals(id, $0.id) })
        return ContestSession(definition: d, dxcc: dxcc, registry: registry, myCall: "OK1XOE", myGrid: grid)
    }

    /// Catalog only (no session); already covered elsewhere, ported for completeness.
    @Test func catalogHasNewContests() {
        let ids = defs.compactMap(\.id)
        let expected = ["arrl-dx-cw", "arrl-dx-ssb", "sp-dx", "rdxc", "ok-om-dx-ssb",
                        "iaru-r1-vhf", "iaru-r1-uhf", "marconi-memorial", "wae-cw", "wae-ssb"]
        for id in expected {
            #expect(ids.contains(id), "\(ids)")
        }
    }

    @Test func arrlDxCountsStatesPerBand() throws {
        let s = try session("arrl-dx-cw", nil)
        let r = try s.log(call: "W1AW", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599"), ("state", "CT")))
        #expect(r.points == 3)
        _ = try s.log(call: "K1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599"), ("state", "CT")))
        _ = try s.log(call: "K1ABC", band: "40m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599"), ("state", "CT")))
        #expect(try s.score().multTotal == 2, "CT na 20 m a 40 m")
        #expect(try s.score().total == 9 * 2)
    }

    @Test func waeWeightsBandsAndCountsQtc() throws {
        let s = try session("wae-cw", nil)
        _ = try s.log(call: "W1AW", band: "80m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599"), ("nr", "1")))
        _ = try s.log(call: "W1AW", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599"), ("nr", "2")))
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599"), ("nr", "3"))) // EU–EU: 0 points, no multiplier
        #expect(try s.score().multTotal == 4 + 2, "USA na 80 m ×4 + na 20 m ×2")
        #expect(try s.score().qsoPoints == 2)
        s.setQtcCount(5)
        #expect(try s.score().total == (2 + 5) * 6)
    }

    @Test func vhfScoresKilometres() throws {
        let s = try session("iaru-r1-vhf", "JO70FC")
        let r = try s.log(call: "DL1ABC", band: "2m", mode: "SSB",
                          receivedRaw: SessionFixture.raw(("rst", "59"), ("nr", "1"), ("loc", "JO62QM")))
        #expect(r.points > 250 && r.points < 300, "Prague–Berlin ~280 km: \(r.points)")
        #expect(Int64(r.points) == (try s.score().total))
    }
}
