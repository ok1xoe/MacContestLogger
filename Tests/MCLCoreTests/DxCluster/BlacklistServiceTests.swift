import Testing
@testable import MCLCore

/// Port of `dxcluster/BlacklistServiceTest` (12).
@Suite struct BlacklistServiceTests {

    private static let now = "2026-07-14T10:00:00Z"

    @Test func addCreatesEntryWithTimeAndNote() {
        var list: [BlacklistEntry] = []
        #expect(BlacklistService.add(&list, "ok1abc", note: "ruší", nowUtc: Self.now))
        #expect(list.count == 1)
        #expect(list[0].value == "OK1ABC")
        #expect(list[0].addedAtUtc == Self.now)
        #expect(list[0].note == "ruší")
    }

    @Test func addIsCaseInsensitiveDedup() {
        var list: [BlacklistEntry] = []
        #expect(BlacklistService.add(&list, "OK1ABC", note: "", nowUtc: Self.now))
        #expect(!BlacklistService.add(&list, "ok1abc", note: "znovu", nowUtc: Self.now))
        #expect(list.count == 1)
    }

    @Test func addBlankIsIgnored() {
        var list: [BlacklistEntry] = []
        #expect(!BlacklistService.add(&list, "  ", note: "", nowUtc: Self.now))
        #expect(list.isEmpty)
    }

    @Test func removeByValueCaseInsensitive() {
        var list: [BlacklistEntry] = []
        BlacklistService.add(&list, "OK1ABC", note: "", nowUtc: Self.now)
        #expect(BlacklistService.remove(&list, "ok1abc"))
        #expect(list.isEmpty)
        #expect(!BlacklistService.remove(&list, "nope"))
    }

    @Test func updateValueRenames() {
        var list: [BlacklistEntry] = []
        BlacklistService.add(&list, "OK1ABC", note: "pozn", nowUtc: Self.now)
        #expect(BlacklistService.updateValue(&list, "OK1ABC", "ok2xyz"))
        #expect(list[0].value == "OK2XYZ")
        #expect(list[0].note == "pozn") // the note and time stay
        #expect(list[0].addedAtUtc == Self.now)
    }

    @Test func updateValueRejectsCollision() {
        var list: [BlacklistEntry] = []
        BlacklistService.add(&list, "OK1ABC", note: "", nowUtc: Self.now)
        BlacklistService.add(&list, "OK2XYZ", note: "", nowUtc: Self.now)
        #expect(!BlacklistService.updateValue(&list, "OK1ABC", "ok2xyz"))
        #expect(list.count == 2)
        #expect(list[0].value == "OK1ABC")
    }

    @Test func setNoteUpdatesNote() {
        var list: [BlacklistEntry] = []
        BlacklistService.add(&list, "OK1ABC", note: "", nowUtc: Self.now)
        #expect(BlacklistService.setNote(&list, "ok1abc", "pirát"))
        #expect(list[0].note == "pirát")
        #expect(!BlacklistService.setNote(&list, "nope", "x"))
    }

    @Test func valuesReturnsUppercaseSet() {
        var list: [BlacklistEntry] = []
        BlacklistService.add(&list, "ok1abc", note: "", nowUtc: Self.now)
        BlacklistService.add(&list, "w1aw", note: "", nowUtc: Self.now)
        let v = BlacklistService.values(list)
        #expect(Set(v) == ["OK1ABC", "W1AW"])
    }

    @Test func syncKeepsNotesAddsAndRemoves() throws {
        var list: [BlacklistEntry] = []
        BlacklistService.add(&list, "OK1ABC", note: "otravuje", nowUtc: Self.now)
        BlacklistService.add(&list, "W1AW", note: "", nowUtc: Self.now)

        // The Settings dialog knows only bare callsigns: OK1ABC stays, W1AW gone, N1MM new.
        #expect(BlacklistService.sync(&list, ["ok1abc", "n1mm"], nowUtc: Self.now))
        #expect(Set(BlacklistService.values(list)) == ["OK1ABC", "N1MM"])
        let ok = try #require(list.first { $0.value == "OK1ABC" })
        #expect(ok.note == "otravuje", "the note from the Blacklist window must not be lost by an overwrite from Settings")
    }

    @Test func syncWithoutChangeReportsNothing() {
        var list: [BlacklistEntry] = []
        BlacklistService.add(&list, "OK1ABC", note: "otravuje", nowUtc: Self.now)
        #expect(!BlacklistService.sync(&list, ["OK1ABC"], nowUtc: Self.now))
        #expect(!BlacklistService.sync(&list, [" ok1abc "], nowUtc: Self.now), "letter case and spaces are not a change")
    }

    @Test func syncWithEmptyListClearsEverything() {
        var list: [BlacklistEntry] = []
        BlacklistService.add(&list, "OK1ABC", note: "", nowUtc: Self.now)
        #expect(BlacklistService.sync(&list, [], nowUtc: Self.now))
        #expect(BlacklistService.values(list).isEmpty)
    }

    @Test func migrateFromLegacyStrings() throws {
        var existing: [BlacklistEntry] = []
        BlacklistService.add(&existing, "OK1ABC", note: "má poznámku", nowUtc: Self.now)
        let merged = BlacklistService.migrate(["ok1abc", "W1AW", "n1mm"], existing, nowUtc: Self.now)
        // OK1ABC already exists (do not overwrite the note), W1AW and N1MM new without a note/time
        #expect(merged.count == 3)
        let ok = try #require(merged.first { $0.value == "OK1ABC" })
        #expect(ok.note == "má poznámku")
        let w = try #require(merged.first { $0.value == "W1AW" })
        #expect(w.note == "")
        #expect(w.addedAtUtc == "")
    }
}
