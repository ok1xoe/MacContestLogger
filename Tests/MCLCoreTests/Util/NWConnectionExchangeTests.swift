import Foundation
import Testing
@testable import MCLCore

/// No Java ancestor — `NWConnection.exchange` is a new helper that the Java original
/// does not have (it uses `DatagramSocket` directly in `SntpClient.query`). This file
/// tests only the bookkeeping of the result (`ExchangeOutcome` — finish may succeed
/// only once, even when the state handler, data receipt and the timeout timer compete), not
/// the real network. The network path of `SNTPClient.query` itself (via `exchange`) is
/// already tested, hermetically over loopback — see `SNTPClientTests.queriesFakeServer`
/// a `.shortResponseThrowsInsteadOfCrashing`.
@Suite struct NWConnectionExchangeTests {
    @Test func firstResultWins() async throws {
        let outcome = ExchangeOutcome()
        let expected = Data([1, 2, 3])
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            outcome.attach(continuation)
            outcome.finish(.success(expected))
            outcome.finish(.failure(.timedOut)) // a late timeout must not do anything any more
        }
        #expect(result == expected)
    }

    @Test func lateResultAfterTimeoutIsIgnored() async {
        let outcome = ExchangeOutcome()
        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                outcome.attach(continuation)
                outcome.finish(.failure(.timedOut))
                outcome.finish(.success(Data([9]))) // a late reply must not do anything any more
            }
            Issue.record("expected the error .timedOut")
        } catch let error as NWConnectionExchangeError {
            #expect(error == .timedOut)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
