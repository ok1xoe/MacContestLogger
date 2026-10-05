import Foundation

/// Runs a blocking `body` on its own thread (`Thread`) and passes the result through a continuation — blocking
/// I/O in tests must not hold a thread of the shared Swift pool (verified under
/// `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`).
func onOwnThread<T: Sendable>(_ name: String = "test-io", _ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
        let thread = Thread {
            do {
                continuation.resume(returning: try body())
            } catch {
                continuation.resume(throwing: error)
            }
        }
        thread.name = name
        thread.start()
    }
}

/// The same without errors.
func onOwnThread<T: Sendable>(_ name: String = "test-io", _ body: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
        let thread = Thread {
            continuation.resume(returning: body())
        }
        thread.name = name
        thread.start()
    }
}
