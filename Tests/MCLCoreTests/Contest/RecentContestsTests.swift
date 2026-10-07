import Testing
@testable import MCLCore

/// The list behind File → Open recent.
@Suite struct RecentContestsTests {

    @Test func pushMovesToTheFrontWithoutRepeats() {
        #expect(RecentContests.push(["a", "b", "c"], "b") == ["b", "a", "c"])
        #expect(RecentContests.push([], "x") == ["x"])
        #expect(RecentContests.push(["a"], "a") == ["a"])
    }

    @Test func theListKeepsNineContests() {
        var ids: [String] = []
        for number in 1...12 {
            ids = RecentContests.push(ids, "c\(number)")
        }
        #expect(ids.count == 9)
        #expect(ids.first == "c12")
        #expect(ids.last == "c4")
    }

    @Test func pruneKeepsOrderAndDropsUnknownAndRepeated() {
        #expect(RecentContests.prune(["a", "x", "b", "a"], keeping: ["a", "b"]) == ["a", "b"])
    }

    @Test func encodingRoundTripsAndDamageIsEmpty() {
        let ids: [String] = ["one", "t\"wo", "tři"]
        #expect(RecentContests.decode(RecentContests.encode(ids)) == ids)
        #expect(RecentContests.decode(nil).isEmpty)
        #expect(RecentContests.decode("").isEmpty)
        #expect(RecentContests.decode("not json").isEmpty)
        #expect(RecentContests.decode("{\"a\":1}").isEmpty)
        let long: String = RecentContests.encode((1...20).map(String.init))
        #expect(RecentContests.decode(long).count == 9)
    }
}
