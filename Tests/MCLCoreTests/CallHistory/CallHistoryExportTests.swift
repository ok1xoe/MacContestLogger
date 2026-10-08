import Foundation
import Testing
@testable import MCLCore

/// CSV export and clearing of a loaded call history.
@Suite struct CallHistoryExportTests {

    private static let sample = CallHistory.parse([
        "!!Order!!,Call,Name,State,CQZone",
        "W1AW,Hiram,CT,5",
        "OK1XOE,Tomas,,15",
    ])

    @Test func csvHasTheHeaderSortedCallsAndQuoting() {
        // A comma or a quote cannot come from an N1MM file (it splits on commas), but can come from an update.
        var updates = JavaLinkedMap<JavaLinkedMap<String>>()
        var values = JavaLinkedMap<String>()
        values.put("name", "Smith \"Bob\"")
        updates.put("K1ABC", values)
        let history = CallHistory.parse(["!!Order!!,Call,Name,State", "W1AW,Hiram,CT", "K1ZZ,,MA"])
            .withUpdates(updates)
        let text: String = history.csvText()
        let lines: [String] = text.components(separatedBy: "\r\n")
        #expect(lines[0] == "Call,Name,State")
        #expect(lines[1] == "K1ABC,\"Smith \"\"Bob\"\"\",")
        #expect(lines[2] == "K1ZZ,,MA")
        #expect(lines[3] == "W1AW,Hiram,CT")
        #expect(lines[4] == "")
        #expect(text.hasSuffix("\r\n"))
    }

    @Test func csvListsEveryCallWithTheColumnsInOrder() {
        let lines: [String] = Self.sample.csvText().components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines == ["Call,Name,State,CQZone", "OK1XOE,Tomas,,15", "W1AW,Hiram,CT,5"])
    }

    @Test func fieldsWithCommasAndLineBreaksAreQuoted() {
        var updates = JavaLinkedMap<JavaLinkedMap<String>>()
        var values = JavaLinkedMap<String>()
        values.put("misc", "one\ntwo")
        updates.put("K1ABC", values)
        let history = CallHistory.empty.withUpdates(updates)
        let text: String = history.csvText()
        #expect(text.contains("\"one\ntwo\""))
    }

    @Test func emptiedKeepsTheColumnsAndNoCalls() {
        let emptied = Self.sample.emptied()
        #expect(emptied.size == 0)
        #expect(emptied.columns == Self.sample.columns)
        let lines: [String] = emptied.toLines()
        #expect(lines.count == 2)
        #expect(lines[1] == "!!Order!!,Call,Name,State,CQZone")
        let parsed = CallHistory.parse(lines)
        #expect(parsed.size == 0)
        #expect(parsed.columns == Self.sample.columns)
    }

    @Test func theN1mmExportReadsBackAsTheSameHistory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcl-ch-export-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("out.txt")
        try Self.sample.save(file.path)
        let back = CallHistory.load(file.path)
        #expect(back.size == Self.sample.size)
        #expect(back.columns == Self.sample.columns)
        #expect(back.toLines() == Self.sample.toLines())
    }
}
