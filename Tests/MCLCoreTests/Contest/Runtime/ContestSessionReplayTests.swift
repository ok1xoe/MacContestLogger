import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `ContestSessionReplayTest` (4): replay of previously logged QSOs from the flat
/// `exchangeRcvd` (as the station stores it) must restore the same score the live
/// session gave while logging (incl. dupe = 0 points).
@Suite struct ContestSessionReplayTests {

    private func session() throws -> ContestSession {
        try SessionFixture.session("@cq-ww-cw.yaml", myCall: "OK1XOE")
    }

    /// Builds the flat exchangeRcvd the same way as EntryPanel (non-empty values in field order).
    private static func flatRcvd(_ s: ContestSession, _ call: String, _ rcvd: [String: String]) throws -> String? {
        var parts: [String] = []
        for field in try s.activeReceivedFields(call: call) {
            if let id = field.id, let v = rcvd[id], !JavaText.isBlank(v) {
                parts.append(v)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private static func raw(_ rcvd: [String: String]) -> JavaLinkedMap<String> {
        JavaLinkedMap(rcvd.sorted { $0.key < $1.key }.map { (Optional($0.key), Optional($0.value)) })
    }

    @Test func replayRebuildsSameScore() throws {
        let qsos: [(call: String, band: String, mode: String, rcvd: [String: String], nr: Int?)] = [
            ("DL1ABC", "20m", "CW", ["rst": "599", "zone": "14"], nil),
            ("W1AW", "20m", "CW", ["rst": "599", "zone": "5"], nil),
            ("DL1ABC", "20m", "CW", ["rst": "599", "zone": "14"], nil),   // dupe
        ]

        // Live session A
        let a = try session()
        for q in qsos {
            _ = try a.log(call: q.call, band: q.band, mode: q.mode, receivedRaw: Self.raw(q.rcvd))
        }

        // Replay into a fresh session B via replayLogged (from the flat exchangeRcvd)
        let b = try session()
        for q in qsos {
            let flat = try Self.flatRcvd(b, q.call, q.rcvd)
            _ = try b.replayLogged(call: q.call, band: q.band, mode: q.mode, exchangeRcvdFlat: flat, serialRcvd: q.nr)
        }

        let sa = try a.score()
        let sb = try b.score()
        #expect(sa.total == sb.total)
        #expect(sa.multTotal == sb.multTotal)
        #expect(sa.qsoCount == sb.qsoCount)
    }

    @Test func qsoWithoutBandDoesNotCountIntoTheLiveScore() throws {
        // Without a connected rig the band may be unknown. Logbook replay skips such a QSO,
        // so the live session must not count it either — otherwise the score during operation
        // differs from the one that applies after reopening the contest.
        let s = try session()
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: Self.raw(["rst": "599", "zone": "14"]))
        let before = try s.score()

        let r = try s.log(call: "OK2TEST", band: "", mode: "CW", receivedRaw: Self.raw(["rst": "599", "zone": "15"]))

        #expect(!r.counted)
        #expect(r.points == 0)
        #expect(r.multipliers.isEmpty)
        let after = try s.score()
        #expect(before.qsoCount == after.qsoCount)
        #expect(before.multTotal == after.multTotal)
        #expect(before.total == after.total)
    }

    @Test func qsoInAModeTheContestDoesNotHaveDoesNotCount() throws {
        // CQ WW CW has modes: [CW]. FT8 QSOs arrive here through reception from WSJT-X.
        let s = try session()
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: Self.raw(["rst": "599", "zone": "14"]))
        let before = try s.score()

        let r = try s.log(call: "OK5WSJ", band: "20m", mode: "FT8", receivedRaw: Self.raw(["rst": "599", "zone": "16"]))

        #expect(!r.counted)
        #expect(before.qsoCount == (try s.score().qsoCount))
        #expect(before.total == (try s.score().total))
    }

    @Test func liveScoreMatchesReplayEvenWithABandlessQso() throws {
        let qsos: [(call: String, band: String, rcvd: [String: String])] = [
            ("DL1ABC", "20m", ["rst": "599", "zone": "14"]),
            ("OK2TEST", "", ["rst": "599", "zone": "15"]),   // no band
            ("W1AW", "20m", ["rst": "599", "zone": "5"]),
        ]

        let live = try session()
        for q in qsos {
            _ = try live.log(call: q.call, band: q.band, mode: "CW", receivedRaw: Self.raw(q.rcvd))
        }

        let replay = try session()
        for q in qsos {
            let flat = try Self.flatRcvd(replay, q.call, q.rcvd)
            _ = try replay.replayLogged(call: q.call, band: q.band, mode: "CW", exchangeRcvdFlat: flat, serialRcvd: nil)
        }

        #expect(try live.score().total == replay.score().total)
        #expect(try live.score().multTotal == replay.score().multTotal)
        #expect(try live.score().qsoCount == replay.score().qsoCount)
        #expect(try live.score().qsoCount == 2)   // a QSO without a band is counted in neither
    }
}
