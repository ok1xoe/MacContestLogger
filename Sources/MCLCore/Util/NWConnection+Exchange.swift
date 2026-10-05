import Foundation
import Network

/// Errors of a network exchange via `NWConnection.exchange`.
public enum NWConnectionExchangeError: Error, Equatable, Sendable {
    /// The response did not arrive within `timeoutMs`.
    case timedOut
    /// The connection failed (description from `NWError`).
    case connectionFailed(String)
    /// The connection was cancelled before the response arrived.
    case cancelled
}

extension NWConnection {
    /// Establishes a connection, sends `request` and waits for a response of exactly `expecting` bytes,
    /// or fails with `.timedOut` if the exchange does not complete within `timeoutMs`.
    ///
    /// Used in `SNTPClient.query`. The network exchange is tested hermetically over
    /// loopback (`SNTPClientTests.queriesFakeServer`, `.shortResponseThrowsInsteadOfCrashing`);
    /// the result bookkeeping (`ExchangeOutcome`) additionally separately in `NWConnectionExchangeTests`.
    func exchange(request: Data, expecting: Int, timeoutMs: Int) async throws -> Data {
        let outcome = ExchangeOutcome()

        return try await withCheckedThrowingContinuation { continuation in
            outcome.attach(continuation)

            self.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.send(content: request, completion: .contentProcessed { error in
                        if let error {
                            outcome.finish(.failure(.connectionFailed(String(describing: error))))
                            return
                        }
                        self.receive(minimumIncompleteLength: expecting, maximumLength: expecting) { data, _, _, error in
                            if let error {
                                outcome.finish(.failure(.connectionFailed(String(describing: error))))
                            } else if let data {
                                outcome.finish(.success(data))
                            } else {
                                outcome.finish(.failure(.connectionFailed("prázdná odpověď")))
                            }
                        }
                    })
                case .failed(let error):
                    outcome.finish(.failure(.connectionFailed(String(describing: error))))
                case .cancelled:
                    outcome.finish(.failure(.cancelled))
                default:
                    break
                }
            }

            self.start(queue: outcome.queue)

            outcome.queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
                outcome.finish(.failure(.timedOut))
            }
        }
    }
}

/// Ensures that the continuation from `withCheckedThrowingContinuation` is completed
/// exactly once, even if the state handler, data receive and the timeout
/// timer compete for it — all run on `queue`, but could finish in any order.
///
/// Internal helper of `NWConnection.exchange` — without `private`, so that its bookkeeping
/// (finish may succeed only once) can be tested without a real network (see
/// `NWConnectionExchangeTests`).
final class ExchangeOutcome: @unchecked Sendable {
    let queue = DispatchQueue(label: "cz.ok1xoe.maccontestlogger.sntp.exchange")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?

    func attach(_ continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func finish(_ result: Result<Data, NWConnectionExchangeError>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        switch result {
        case .success(let data):
            pending.resume(returning: data)
        case .failure(let error):
            pending.resume(throwing: error)
        }
    }
}
