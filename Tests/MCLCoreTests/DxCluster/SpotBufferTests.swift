import Foundation
import Testing
@testable import MCLCore

/// Port of `dxcluster/SpotBufferTest` (14).
@Suite struct SpotBufferTests {

    private func buffer(_ minutes: Int, _ clock: DxTestClock) -> SpotBuffer {
        SpotBuffer(maxAgeMinutes: minutes, clock: clock.source)
    }

    @Test func storesSpot() {
        let buf = buffer(15, DxTestClock("2026-07-09T10:00:00Z"))
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: "CQ"))
        #expect(buf.snapshot().count == 1)
        #expect(buf.snapshot()[0].dxCall == "OH2AS")
    }

    @Test func removeDeletesSpot() {
        let buf = buffer(15, DxTestClock("2026-07-09T10:00:00Z"))
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: "CQ"))
        buf.remove("oh2as")
        #expect(buf.snapshot().isEmpty)
    }

    @Test func clearEmptiesBuffer() {
        let buf = buffer(15, DxTestClock("2026-07-09T10:00:00Z"))
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: "CQ"))
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 7_005_000, dxCall: "W1AW", comment: ""))
        buf.clear()
        #expect(buf.snapshot().isEmpty)
    }

    @Test func blacklistedCallIsNotAdded() {
        let buf = buffer(15, DxTestClock("2026-07-09T10:00:00Z"))
        buf.setBlacklist(calls: ["OH2AS"], spotters: [])
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: "CQ"))
        #expect(buf.snapshot().isEmpty)
    }

    @Test func blacklistedSpotterIsNotAdded() {
        let buf = buffer(15, DxTestClock("2026-07-09T10:00:00Z"))
        buf.setBlacklist(calls: [], spotters: ["OK1ABC"])
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: "CQ"))
        #expect(buf.snapshot().isEmpty)
    }

    @Test func setBlacklistPurgesExistingSpots() {
        let buf = buffer(15, DxTestClock("2026-07-09T10:00:00Z"))
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: "CQ"))
        buf.add(DxSpot(spotter: "W1AW", freqHz: 7_005_000, dxCall: "DL1XYZ", comment: ""))
        buf.setBlacklist(calls: ["OH2AS"], spotters: [])
        #expect(buf.snapshot().count == 1)
        #expect(buf.snapshot()[0].dxCall == "DL1XYZ")
    }

    @Test func nearestWithinReturnsSpotInsideTolerance() {
        let buf = buffer(15, DxTestClock("2026-07-09T10:00:00Z"))
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: "CQ"))
        // 50 Hz from 14025000, tolerance 100 → found
        #expect(buf.nearestWithin(14_025_050, toleranceHz: 100)?.dxCall == "OH2AS")
    }

    @Test func nearestWithinEmptyOutsideTolerance() {
        let buf = buffer(15, DxTestClock("2026-07-09T10:00:00Z"))
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: "CQ"))
        // 300 Hz from the spot, tolerance 100 → nothing
        #expect(buf.nearestWithin(14_025_300, toleranceHz: 100) == nil)
    }

    @Test func nearestWithinPicksClosestOfSeveral() {
        let buf = buffer(15, DxTestClock("2026-07-09T10:00:00Z"))
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "AA1AA", comment: ""))
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_120, dxCall: "BB2BB", comment: ""))
        // query 14025100: BB2BB is 20 Hz, AA1AA 100 Hz → BB2BB
        #expect(buf.nearestWithin(14_025_100, toleranceHz: 200)?.dxCall == "BB2BB")
    }

    @Test func respotUpdatesFreqAndKeepsSingleEntry() {
        let clk = DxTestClock("2026-07-09T10:00:00Z")
        let buf = buffer(15, clk)
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: "CQ"))
        clk.set("2026-07-09T10:10:00Z")
        buf.add(DxSpot(spotter: "W1AW", freqHz: 14_030_000, dxCall: "OH2AS", comment: ""))
        #expect(buf.snapshot().count == 1)
        #expect(buf.snapshot()[0].freqHz == 14_030_000)
    }

    @Test func expiresAfterMaxAgeFromLastTouch() {
        let clk = DxTestClock("2026-07-09T10:00:00Z")
        let buf = buffer(15, clk)
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: "CQ"))
        clk.set("2026-07-09T10:14:59Z")
        #expect(buf.snapshot().count == 1)
        clk.set("2026-07-09T10:15:01Z")
        #expect(buf.snapshot().isEmpty)
    }

    @Test func changingMaxAgeAffectsExpiry() {
        let clk = DxTestClock("2026-07-09T10:00:00Z")
        let buf = buffer(15, clk)
        buf.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: "CQ"))
        clk.set("2026-07-09T10:20:00Z")
        #expect(buf.snapshot().isEmpty)
        buf.setMaxAgeMinutes(30)
        #expect(buf.snapshot().count == 1)
    }

    @Test func findsSpotForACallTogetherWithItsAge() throws {
        // The info window shows a spot of a partially typed callsign including its age: "[VE3KI @ 3 min]".
        let t0 = dxInstant("2026-08-19T12:00:00Z")
        let now = DxTestClock("2026-08-19T12:00:00Z")
        let buffer = buffer(30, now)
        buffer.add(DxSpot(spotter: "VE3KI", freqHz: 14_090_070, dxCall: "MI0BPB", comment: "cq"))

        now.set(t0.addingTimeInterval(180))
        let found = try #require(buffer.find("mi0bpb"))

        #expect(found.spot.spotter == "VE3KI")
        #expect(found.ageMinutes(now.now) == 3)
    }

    @Test func findsNothingForUnspottedOrExpiredCall() {
        let t0 = dxInstant("2026-08-19T12:00:00Z")
        let now = DxTestClock("2026-08-19T12:00:00Z")
        let buffer = buffer(10, now)
        buffer.add(DxSpot(spotter: "VE3KI", freqHz: 14_090_070, dxCall: "MI0BPB", comment: "cq"))

        #expect(buffer.find("OK1XOE") == nil)

        now.set(t0.addingTimeInterval(11 * 60))
        #expect(buffer.find("MI0BPB") == nil, "a spot older than the limit no longer counts")
    }
}
