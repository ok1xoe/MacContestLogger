import Dispatch
import Foundation
import Testing
@testable import MCLAppModel

/// Conversion of Kotlin `SwingDispatcherTest`: work posted from a foreign thread really runs on the main thread
/// (the Kotlin regression: a CAT callback without a usable Main dispatcher).
@Suite struct MainHopTests {
    @Test func mainDispatcherIsAvailable() async {
        let ranOnMain: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let thread = Thread {
                MainHop.post {
                    continuation.resume(returning: Thread.isMainThread)
                }
            }
            thread.start()
        }
        #expect(ranOnMain, "MainHop must run work on the main thread")
    }
}

/// Blocking work runs on its own queue — neither on the main thread nor in the cooperative pool.
@Suite struct BlockingQueueTests {
    private static func currentQueueLabel() -> String {
        String(cString: __dispatch_queue_get_label(nil))
    }

    @Test func workRunsOnTheBlockingQueue() async throws {
        let observed: (label: String, main: Bool) = try await BlockingQueue.run {
            (BlockingQueueTests.currentQueueLabel(), Thread.isMainThread)
        }
        #expect(observed.label == BlockingQueue.label)
        #expect(!observed.main)
    }

    @Test func errorsPropagateToTheCaller() async {
        struct Failure: Error, Equatable {}
        await #expect(throws: Failure.self) {
            _ = try await BlockingQueue.run { () throws -> Int in throw Failure() }
        }
    }

    @Test func blockingDoesNotStarveTheCooperativePool() async throws {
        // More blocked jobs than cores: if they ran in the cooperative pool, the releasing task below could not run
        // and the test would hang (under `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` the pool has a single thread).
        let gate = DispatchSemaphore(value: 0)
        let count: Int = ProcessInfo.processInfo.activeProcessorCount + 2
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<count {
                group.addTask {
                    try await BlockingQueue.run {
                        gate.wait()
                        gate.signal()
                    }
                }
            }
            group.addTask {
                gate.signal()
            }
            try await group.waitForAll()
        }
    }
}
