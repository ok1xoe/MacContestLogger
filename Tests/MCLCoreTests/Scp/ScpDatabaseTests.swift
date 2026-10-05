import Foundation
import Testing
@testable import MCLCore

/// The Java `scp/ScpDatabaseTest` (10 tests). A performance test without a wall-clock bound:
/// it searches over 80,000 callsigns and the result is verified; the time is not asserted.
@Suite struct ScpDatabaseTests {

    private static let db = ScpDatabase.of([
        "OK1XOE", "OK1XX", "OK2ABC", "DL1XOE", "G3XOE", "OK1K", "W1XOE", "OM3XX"])

    @Test func findsCallsContainingTheTypedText() {
        // An inner match is essential: an operator often hears only a piece of a callsign.
        let found = Self.db.find("XOE", limit: 10)
        for call in ["OK1XOE", "DL1XOE", "G3XOE", "W1XOE"] {
            #expect(found.contains(call), "\(found)")
        }
    }

    @Test func prefixMatchesComeBeforeInternalOnes() {
        #expect(Self.db.find("OK1", limit: 10) == ["OK1K", "OK1XX", "OK1XOE"])
    }

    @Test func exactMatchIsAlwaysFirst() {
        let found = ScpDatabase.of(["OK1XX", "OK1X", "AOK1X"]).find("OK1X", limit: 10)
        #expect(found.first == "OK1X")
    }

    @Test func shorterCallsRankBeforeLongerOnesInTheSameClass() {
        #expect(Self.db.find("OK1", limit: 10) == ["OK1K", "OK1XX", "OK1XOE"])
    }

    @Test func limitCapsTheResult() {
        #expect(Self.db.find("XOE", limit: 2).count == 2)
    }

    @Test func searchIsCaseInsensitiveAndIgnoresSpacing() {
        #expect(Self.db.find("OK1", limit: 10) == Self.db.find("  ok1 ", limit: 10))
    }

    @Test func tooShortInputGivesNothing() {
        #expect(Self.db.find("O", limit: 10).isEmpty)
        #expect(Self.db.find("", limit: 10).isEmpty)
        #expect(Self.db.find(nil, limit: 10).isEmpty)
    }

    @Test func loadsFileSkippingCommentsAndBlanks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scp-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("master.scp")
        let lines: [String] = ["# MASTER.SCP verze 2026", "", "ok1xoe", "  DL1ABC  ", "OK1XOE", "#další komentář", "OM3XX"]
        try Data(lines.joined(separator: "\n").utf8).write(to: file)

        let loaded = ScpDatabase.load(file.path)

        #expect(loaded.size == 3)
        #expect(loaded.find("OK1", limit: 10) == ["OK1XOE"])
        #expect(loaded.find("DL1", limit: 10) == ["DL1ABC"])
    }

    @Test func missingFileGivesEmptyDatabaseInsteadOfFailing() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("scp-\(UUID().uuidString)/neexistuje.scp")
        let loaded = ScpDatabase.load(path.path)

        #expect(loaded.size == 0)
        #expect(loaded.find("OK1", limit: 10).isEmpty)
    }

    /// Java measures < 200 ms for a search; here without a wall-clock bound — the result is verified
    /// over 80,000 callsigns, the time is not asserted.
    @Test func searchOverFullSizedDatabaseStaysFast() {
        var calls: [String] = []
        calls.reserveCapacity(80_000)
        for i in 0..<80_000 {
            calls.append("OK\(i % 10)" + String(i, radix: 36).uppercased())
        }
        let big = ScpDatabase.of(calls)
        #expect(big.size == 80_000)
        var found: [String] = []
        for _ in 0..<20 {
            found = big.find("OK1A", limit: 10)
        }
        // Values from Java (the same data, `find("OK1A", 10)` and `nPlusOne("OK1A", 10)`).
        #expect(found == ["OK1A1", "OK1AB", "OK1AL", "OK1AV", "OK1A01", "OK1A0B", "OK1A0L", "OK1A0V", "OK1A15", "OK1A1F"])
        #expect(big.nPlusOne("OK1A", limit: 10)
            == ["OK0A", "OK11", "OK1A1", "OK1AB", "OK1AL", "OK1AV", "OK1B", "OK1L", "OK1V", "OK61A"])
    }
}
