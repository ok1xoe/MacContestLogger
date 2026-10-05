import Testing
@testable import MCLCore

/// `AudioUsers` against `acquireAudio`/`releaseAudio` (`AS:152-167`) and.
@Suite struct AudioUsersTests {

    @Test func firstUserStartsOthersJoinTheRunningInput() {
        var users = AudioUsers()
        #expect(users.acquire("waterfall", running: false) == .start)
        #expect(users.acquire("cwreader", running: true) == .alreadyRunning)
        #expect(users.users == ["waterfall", "cwreader"])
    }

    @Test func lastUserClosesTheInput() {
        var users = AudioUsers()
        _ = users.acquire("waterfall", running: false)
        _ = users.acquire("recorder", running: true)
        let result1 = users.release("waterfall")
        #expect(!result1)
        let result2 = users.release("recorder")
        #expect(result2)
        // Kotlin closes whenever the set is empty — also for a user that was never registered.
        let result3 = users.release("cwreader")
        #expect(result3)
    }

    /// A failed start does not leave the user registered, so the next `acquire` starts the input again and the
    /// last `release` still closes it.
    @Test func failedStartUnregistersTheUser() {
        var users = AudioUsers()
        #expect(users.acquire("recorder", running: false) == .start)
        users.startFailed("recorder")
        #expect(users.users.isEmpty)
        #expect(users.acquire("waterfall", running: false) == .start)
        let result4 = users.release("waterfall")
        #expect(result4)
    }

    @Test func acquiringTwiceKeepsOneRegistration() {
        var users = AudioUsers()
        _ = users.acquire("waterfall", running: false)
        _ = users.acquire("waterfall", running: true)
        let result5 = users.release("waterfall")
        #expect(result5)
    }
}
