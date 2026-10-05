import Testing
@testable import MCLCore

/// Port of `digital/RecentCallsTest` (4 tests; names translated).
@Suite struct RecentCallsTests {

    @Test func keepsOrderOfFirstOccurrence() {
        let r = RecentCalls(max: 4)
        r.offer("EA1B")
        r.offer("OK1K")
        #expect(r.calls == ["EA1B", "OK1K"])
    }

    @Test func repeatedCallDoesNotMove() {
        let r = RecentCalls(max: 4)
        r.offer("EA1B")
        r.offer("OK1K")
        r.offer("EA1B")
        #expect(r.calls == ["EA1B", "OK1K"], "a click must not escape from under the cursor")
    }

    @Test func oldestDropsOutWhenCapExceeded() {
        let r = RecentCalls(max: 2)
        r.offer("EA1B")
        r.offer("OK1K")
        r.offer("HG7T")
        #expect(r.calls == ["OK1K", "HG7T"])
    }

    @Test func emptyValuesAreIgnored() {
        let r = RecentCalls(max: 4)
        r.offer(nil)
        r.offer("  ")
        #expect(r.calls.isEmpty)
    }
}
