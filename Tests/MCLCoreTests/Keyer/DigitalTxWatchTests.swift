import Testing
@testable import MCLCore

/// `DigitalTxWatch` against `AppState.sendDigitalText` (`AS:1596-1609`) and.
@Suite struct DigitalTxWatchTests {

    /// Drives the watch over manual time with scripted fldigi answers; returns (polls, end, elapsed ms).
    static func drive(answers: (Int) -> String?, tokenCurrent: (Int) -> Bool = { _ in true })
        -> (polls: Int, end: DigitalTxWatch.Step, elapsed: Int64) {
        var watch = DigitalTxWatch()
        var elapsed: Int64 = 0
        var polls = 0
        while true {
            let step = watch.next(tokenCurrent: tokenCurrent(polls))
            switch step {
            case .wait(let ms):
                elapsed += ms
            case .poll:
                watch.record(state: answers(polls))
                polls += 1
            case .finish, .abandon:
                return (polls, step, elapsed)
            }
        }
    }

    @Test func firstNonTxEndsTheWatchWithoutABurst() {
        let result = Self.drive { $0 < 3 ? "TX" : "RX" }
        #expect(result.polls == 4) // three TX, then RX — and no further polls
        #expect(result.end == .finish)
        #expect(result.elapsed == 500 + 3 * 500)
    }

    @Test func notTransmittingAfter500msEndsAtOnce() {
        let result = Self.drive { _ in "RX" }
        #expect(result.polls == 1)
        #expect(result.elapsed == 500)
        #expect(result.end == .finish)
    }

    /// A failed poll counts as `"RX"`; any other text than `TX` too.
    @Test func errorCountsAsRx() {
        #expect(Self.drive { _ in nil }.polls == 1)
        #expect(Self.drive { _ in "TUNE" }.polls == 1)
        #expect(Self.drive { $0 == 0 ? "tx" : "TX" }.polls == 1)
    }

    /// Permanent TX: 240 polls, each followed by 500 ms — two minutes, then the lamp goes out.
    @Test func capIs240Polls() {
        let result = Self.drive { _ in "TX" }
        #expect(result.polls == 240)
        #expect(result.end == .finish)
        #expect(result.elapsed == 500 + 240 * 500)
    }

    /// An aborted or superseded send ends the watch before the next poll, without touching the lamp.
    @Test func staleTokenAbandonsBeforePolling() {
        let result = Self.drive(answers: { _ in "TX" }, tokenCurrent: { $0 < 2 })
        #expect(result.polls == 2)
        #expect(result.end == .abandon)
        #expect(Self.drive(answers: { _ in "TX" }, tokenCurrent: { _ in false }).polls == 0)
    }
}
