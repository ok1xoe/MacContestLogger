import Testing
@testable import MCLCore

/// The Java `scp/NPlusOneTest` (2 tests).
@Suite struct NPlusOneTests {

    @Test func oneEditDistance() {
        #expect(PartialCheck.isOneOff("OK1XOE", "OK1XDE"), "substitution")
        #expect(PartialCheck.isOneOff("OK1XOE", "OK1XOEE"), "insertion")
        #expect(PartialCheck.isOneOff("OK1XOE", "OK1OE"), "deletion")
        #expect(PartialCheck.isOneOff("OK1XOE", "K1XOE"), "deletion at the start")
        #expect(!PartialCheck.isOneOff("OK1XOE", "OK1XOE"), "the same")
        #expect(!PartialCheck.isOneOff("OK1XOE", "OK1XDF"), "two changes")
        #expect(!PartialCheck.isOneOff("OK1XOE", "OK1X"), "two shorter")
    }

    @Test func fromScpDatabase() {
        let db = ScpDatabase.of(["OK1XOE", "OK1XDE", "OK1XO", "OK2XOE", "DL1ABC", "OK1XOEA"])
        #expect(db.nPlusOne("ok1xoe", limit: 10) == ["OK1XDE", "OK1XO", "OK1XOEA", "OK2XOE"])
        #expect(db.nPlusOne("OK", limit: 10) == [], "short text")
        #expect(db.nPlusOne("OK1XOE", limit: 2).count == 2)
    }
}
