import Foundation
import os
import Testing
@testable import MCLAppModel

/// `LogbookHandle.isClosed` is read on the main actor (`copyLog`): it must not wait for a database job, which holds the
/// handle's lock for its whole run.
@Suite(.mainActorSafetyNet) struct LogbookHandleTests {

    @Test func isClosedDoesNotWaitForARunningJob() async throws {
        let handle: LogbookHandle = try LogbookHandle.inMemory()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let released = OSAllocatedUnfairLock(initialState: false)
        let job = Task {
            try await handle.run { _ in
                entered.signal()
                release.wait()
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Thread.detachNewThread {
                entered.wait()
                continuation.resume()
            }
        }
        // The job holds the lock now. A reader that waits for it is released after two seconds, so a regression fails
        // this test instead of hanging it.
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 2)
            released.withLock { $0 = true }
            release.signal()
        }
        let closed: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Thread.detachNewThread {
                continuation.resume(returning: handle.isClosed)
            }
        }
        let waited: Bool = released.withLock { $0 }
        #expect(!closed)
        #expect(!waited, "isClosed waited for the running job")
        release.signal()
        try await job.value
        await handle.close()
        #expect(handle.isClosed)
    }
}
