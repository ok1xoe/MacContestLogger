import Foundation
import Testing
@testable import MCLCore

/// The proof that the Java parity gates' `Band.javaV111Table` switch does something: the very same inputs, replayed
/// WITHOUT the switch, give a different result than the frozen Java v1.1.1 reference (which knows no band above
/// 70 cm), and the new values are pinned here. The gates replay with the switch on and stay green; nothing is
/// regenerated (a deliberate divergence from Java v1.1.1).
@Suite struct MicrowaveDeltaTests {

    /// Reference `exp.FILES` item `e/001`: a synthetic QSO on 1 296 200 000 Hz (Java: no band).
    private static func exportRows(microwave: Bool) throws -> [(String, [String])] {
        let reference = try JavaIoParityFixture.reference("ui-c-java")
        let item = try #require(reference.first { $0.relative == "exp.FILES" })
        let input = try #require(item.lines.first { $0.hasPrefix("[\"e/001\",\"in\",") })
        let fields: [String] = JavaEngineParityTests.fields(input)
        let environment = try UiParitySections.Environment.load()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("microwave-delta-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let edge = try #require(Bundle.module.url(forResource: "io-edge", withExtension: nil))
        let ctx = UiParityCSections.Ctx(environment, work: work, edge: edge)
        let inputs: [String] = Array(fields.dropFirst(2))
        return try Band.$javaV111Table.withValue(!microwave) {
            try UiParityCSections.exportRow("e/001", inputs, ctx)
        }
    }

    private static func text(_ rows: [(String, [String])], _ suffix: String) throws -> String {
        let row = try #require(rows.first { $0.0.hasSuffix(suffix) })
        return try #require(row.1.last)
    }

    @Test func gateCExportOfThe23cmQsoDiffersFromJava() throws {
        let java = try Self.exportRows(microwave: false)
        let swift = try Self.exportRows(microwave: true)
        #expect(java.map(\.0) == swift.map(\.0))
        for suffix in [".csv", ".txt", "summary.txt", "log.adi"] {
            #expect(try Self.text(java, suffix) != Self.text(swift, suffix), "\(suffix)")
        }
        // Java: no band (empty column, no <BAND>, the "?" row of the summary).
        #expect(try Self.text(java, ".csv").contains(",OK2KKW,,1296200.0,"))
        #expect(try !Self.text(java, "log.adi").contains("<BAND:"))
        #expect(try Self.text(java, "summary.txt").contains("?  "))
        // Swift: the QSO has 23cm.
        #expect(try Self.text(swift, ".csv").contains(",OK2KKW,23cm,1296200.0,"))
        #expect(try Self.text(swift, "log.adi").contains("<BAND:4>23cm"))
        #expect(try !Self.text(swift, "summary.txt").contains("?  "))
    }

    /// The frozen reference itself is the Java behaviour: the switched-on replay reproduces it row by row.
    @Test func switchedOnReplayEqualsTheJavaReference() throws {
        let reference = try JavaIoParityFixture.reference("ui-c-java")
        let item = try #require(reference.first { $0.relative == "exp.FILES" })
        let expected: [String] = item.lines.filter { $0.hasPrefix("[\"e/001/") }
        let rows = try Self.exportRows(microwave: false)
        let produced: [String] = rows.map { JavaIoParityFixture.line($0.0, "out", $0.1) }
        #expect(produced == expected)
    }

    @Test func importOfAr20bReadsTheBandJavaIgnored() throws {
        let url = try IoEdgeFixture.inputURL("AR20b-pasma.adi")
        let java: [Qso] = try Band.$javaV111Table.withValue(true) { try AdifReader().readFile(url) }
        let swift: [Qso] = try AdifReader().readFile(url)
        #expect(java.count == swift.count)
        #expect(java[9].band == nil)       // BAND=23cm: Java v1.1.1 has no such band
        #expect(swift[9].band == .cm23)
    }

    @Test func antennaCoverageReachesTheNewBand() {
        let entry = AntennaEntry(code: 1, name: "A", bands: "6m;2m;70cm;23cm", sector: "")
        let java: [String] = Band.javaV111Cases.filter { AntennaSelector.covers(entry, $0) }.map(\.adif)
        let swift: [String] = Band.allCases.filter { AntennaSelector.covers(entry, $0) }.map(\.adif)
        #expect(java == ["6m", "2m", "70cm"])
        #expect(swift == ["6m", "2m", "70cm", "23cm"])
    }
}
