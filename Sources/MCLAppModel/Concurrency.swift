import Dispatch
import Foundation

/// Runs blocking work (file and database I/O, sockets) on a dedicated dispatch queue, **neither** on the main thread
/// **nor** in Swift's cooperative pool, which must never block. The counterpart of Kotlin's `Dispatchers.IO`.
public enum BlockingQueue {

    /// Label of the queue; tests check that the work really ran on it.
    public static let label = "cz.ok1xoe.maccontestlogger.blocking"

    private static let queue = DispatchQueue(label: label, qos: .userInitiated, attributes: .concurrent)

    /// Runs `body` on the blocking queue and returns its result (or rethrows its error).
    public static func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
            queue.async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Hops work from any thread to the main thread (AppKit/SwiftUI), the counterpart of Kotlin's
/// `withContext(Dispatchers.Main)` for core callbacks (CAT poller, MQTT states, network listeners).
public enum MainHop {

    /// Schedules `body` asynchronously on the main actor; never runs it inline, even when called from the main thread.
    public static func post(_ body: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                body()
            }
        }
    }
}
