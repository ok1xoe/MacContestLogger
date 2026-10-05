import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `IaruScoringTest` (6). IARU HF Championship: scoring (own
/// zone/continent/HQ) and distinguishing zone vs HQ multipliers from one `exch` field. DXCC fixture =
/// CZ/US/CA/DE, own station OK1XOE (CZ, EU, ITU zone 28).
@Suite struct IaruScoringTests {

    private func session() throws -> ContestSession {
        try SessionFixture.session("@iaru-hf.yaml", myCall: "OK1XOE", myGrid: nil, myItuZone: "28")
    }

    @Test func scoringByZoneContinentAndHq() throws {
        let s = try session()
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("exch", "28")))  // own ITU zone = 1
        _ = try s.log(call: "DL2XYZ", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("exch", "14")))  // other zone, EU = 3
        _ = try s.log(call: "W1AW", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("exch", "8")))     // other zone, NA = 5
        _ = try s.log(call: "DA0HQ", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("exch", "DARC"))) // HQ = 1

        let sc = try s.score()
        #expect(sc.qsoCount == 4)
        #expect(sc.qsoPoints == 10)   // 1 + 3 + 5 + 1
        #expect(sc.multTotal == 4)    // zones {28,14,8}=3 + HQ {DARC}=1
        #expect(sc.total == 40)       // 10 * 4
    }

    @Test func zoneAndHqAreCountedSeparatelyNeverBoth() throws {
        let s = try session()
        // numeric zone → zone mult only; HQ abbreviation → HQ mult only
        _ = try s.log(call: "DL1ABC", band: "40m", mode: "CW", receivedRaw: SessionFixture.raw(("exch", "28")))
        _ = try s.log(call: "DA0HQ", band: "40m", mode: "CW", receivedRaw: SessionFixture.raw(("exch", "DARC")))

        #expect(try s.score().multTotal == 2)   // {28} + {DARC}, no spot gives both
    }

    @Test func spotZoneEstimateReflectsWorkedZone() throws {
        let dxcc = try SessionFixture.dxcc()
        let def = try SessionFixture.definition("@iaru-hf.yaml")
        let s = ContestSession(definition: def, dxcc: dxcc, registry: try SessionFixture.registry(dxcc),
                               myCall: "OK1XOE", myGrid: nil, myItuZone: "28")
        let received = def.exchange?.received

        // Log a station from zone 28 (OK)
        _ = try s.log(call: "OK1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("exch", "28")))

        // Spot of another OK station → estimated ITU zone 28 → zone already worked → no new mult
        let estOk = SpotExchangeEstimator.estimate(received, "OK2XYZ", dxcc)
        let rOk = try s.preview(call: "OK2XYZ", band: "20m", mode: "CW", receivedRaw: estOk)
        #expect(SessionFixture.newMultipliers(rOk) == 0, "spot of an OK station is no longer a multiplier after working zone 28")

        // Spot of a US station → estimate of another ITU zone → new multiplier
        let estUs = SpotExchangeEstimator.estimate(received, "W1AW", dxcc)
        let rUs = try s.preview(call: "W1AW", band: "20m", mode: "CW", receivedRaw: estUs)
        #expect(SessionFixture.newMultipliers(rUs) == 1, "spot of a US station (other ITU zone) is a multiplier")
    }

    /// Registry only (no session); already covered elsewhere, ported for completeness.
    @Test func hqCallsLoadedFromExternalCsv() throws {
        let registry = try SessionFixture.registry(try SessionFixture.dxcc())
        let darc = try #require(try registry.get("iaru_hq").values.first { JavaText.equals("DARC", $0.key) })
        // callsigns were loaded from iaru_hq.csv as the attribute calls
        #expect(try #require(darc.attributes["calls"]).contains("DA0HQ"))
    }

    @Test func spotHqRecognizedByCallsign() throws {
        let dxcc = try SessionFixture.dxcc()
        let def = try SessionFixture.definition("@iaru-hf.yaml")
        let s = ContestSession(definition: def, dxcc: dxcc, registry: try SessionFixture.registry(dxcc),
                               myCall: "OK1XOE", myGrid: nil, myItuZone: "28")
        let received = def.exchange?.received
        // HQ map: DA0HQ → DARC (as ContestController builds it from the iaru_hq set)
        let hq = SessionFixture.raw(("DA0HQ", "DARC"), ("TM0HQ", "REF"))

        // Log the HQ station DARC (exch = DARC)
        _ = try s.log(call: "DA0HQ", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("exch", "DARC")))

        // Spot DA0HQ → estimate DARC → HQ already worked → no new mult
        let estDa = SpotExchangeEstimator.estimate(received, "DA0HQ", dxcc, hqCalls: hq)
        #expect(estDa["exch"] == "DARC")
        let rDa = try s.preview(call: "DA0HQ", band: "20m", mode: "CW", receivedRaw: estDa)
        #expect(SessionFixture.newMultipliers(rDa) == 0, "HQ DARC is no longer a multiplier after the QSO")

        // Spot TM0HQ (REF) → another HQ → new mult
        let estTm = SpotExchangeEstimator.estimate(received, "TM0HQ", dxcc, hqCalls: hq)
        #expect(estTm["exch"] == "REF")
        let rTm = try s.preview(call: "TM0HQ", band: "20m", mode: "CW", receivedRaw: estTm)
        #expect(SessionFixture.newMultipliers(rTm) == 1, "HQ REF is a new multiplier")
    }

    @Test func dupePerBandAndMode() throws {
        let s = try session()
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("exch", "28")))
        // same station, same band, DIFFERENT mode → not a dupe (dupe is PER_BAND_MODE)
        let r = try s.log(call: "DL1ABC", band: "20m", mode: "SSB", receivedRaw: SessionFixture.raw(("exch", "28")))
        #expect(r.dupe == false)
    }
}
