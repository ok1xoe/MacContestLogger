import Foundation
import Testing
@testable import MCLCore

/// Edges of the `hamqth/` package measured on Java v1.1.1 (a probe over the Java classes; full coverage is in the sections
/// `hamqth.*` of the maintainer-only generator).
@Suite struct HamQthMeasuredTests {

    // MARK: - XML by regex: first occurrence, case-sensitive, entities and CDATA raw

    @Test(arguments: [
        ("<grid></grid><grid>JO70</grid>", nil),
        ("<grid> &amp; </grid>", "&amp;"),
        ("<grid><![CDATA[JO70]]></grid>", "<![CDATA[JO70]]>"),
        ("<GRID>JO70</GRID>", nil),
        ("<grid a=\"1\">JO70</grid>", nil),
        ("<grid>\n JO70\u{00A0}</grid>", "JO70\u{00A0}"),
        ("<grid><grid>JO70</grid></grid>", "<grid>JO70"),
        ("<grid>a\nb</grid>", "a\nb"),
    ] as [(String, String?)])
    func gridTagLikeJavaRegex(xml: String, expected: String?) {
        #expect(HamQthClient.parseGrid(xml) == expected)
    }

    @Test func qrzTagsAreCaseSensitive() {
        #expect(QrzClient.parseKey("<key>x</key>") == nil)
    }

    @Test func maskReplacesEveryPasswordParameter() {
        #expect(HamQthLog.mask("https://h/x.php?u=a&P=secret&p=x#y") == "https://h/x.php?u=a&P=***&p=***")
        #expect(HamQthLog.mask("https://h/x.php?id=1&pp=2&p=") == "https://h/x.php?id=1&pp=2&p=***")
        #expect(HamQthLog.mask(nil) == "")
    }

    // MARK: - CSV grid database

    @Test func csvReadsCarriageReturnLines() {
        let db = GridDatabase.fromCsv(Data("W1AW;FN31\rOK1XOE;JO70".utf8))
        #expect(db.grid("W1AW") == "FN31")
        #expect(db.grid("OK1XOE") == "JO70")
        #expect(db.size == 2)
    }

    @Test func bomIsStrippedOnlyOnFirstLine() {
        let db = GridDatabase.fromCsv(Data("x;y\n\u{FEFF}W1AW;FN31".utf8))
        #expect(db.grid("W1AW") == nil)
        #expect(db.grid("\u{FEFF}W1AW") == "FN31")
        #expect(db.grid("X") == "y")
        #expect(db.size == 2)
    }

    @Test func firstOccurrenceWinsAndHeaderOnlyOnFirstLine() {
        let first = GridDatabase.fromCsv(Data("OK1XOE;JO70\nok1xoe;JN99".utf8))
        #expect(first.grid("OK1XOE") == "JO70")
        #expect(first.size == 1)
        let spaced = GridDatabase.fromCsv(Data(" znacka;x\nZNACKA;y".utf8))
        #expect(spaced.grid("ZNACKA") == "x")
        #expect(spaced.size == 1)
        let prefixed = GridDatabase.fromCsv(Data("znacka123;x\nA;b".utf8))
        #expect(prefixed.grid("ZNACKA123") == nil)
        #expect(prefixed.size == 1)
    }

    @Test func encodedSurrogateIsOneReplacementLikeJava() {
        var bytes = Data("W1AW;FN".utf8)
        bytes.append(contentsOf: [0xED, 0xA0, 0x80])
        bytes.append(contentsOf: Data("31".utf8))
        #expect(GridDatabase.fromCsv(bytes).grid("W1AW") == "FN\u{FFFD}31")
    }

    @Test func fieldMapSkipsShortGridsAndUnknownCalls() throws {
        let dxcc = try DxccResolver.fromData(DxccTestFixture.data())
        let csv = "OK1XOE;jo70\nW1AW;J\nZZ9ZZ;KP20\nDL1ABC;a\u{1F600}\n"
        let map = GridFieldMap.build(Data(csv.utf8), dxcc)
        #expect(map.known("JO"))
        #expect(map.matches(" jo ", entityCode: 503))
        #expect(!map.known("J"))
        #expect(!map.known("KP"))
        // Java: field "A\uD83D" (a lone half of a pair); Swift does not carry it → "A\u{FFFD}" (a deliberate
        // divergence from Java v1.1.1). A key that the valid field does not ask for.
        #expect(map.known("A\u{FFFD}"))
        #expect(map.matches("A\u{FFFD}", entityCode: 230))
    }

    @Test func fieldMapFromMissingDirIsEmpty() throws {
        let dxcc = try DxccResolver.fromData(DxccTestFixture.data())
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-hamqth-" + UUID().uuidString)
        #expect(!GridFieldMap.fromDir(missing, dxcc).known("JO"))
        #expect(!GridFieldMap.fromDir(nil, dxcc).known("JO"))
        #expect(GridDatabase.fromDir(missing).size == 0)
    }

    @Test func fromDirReadsMultipliersFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-hamqth-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let multipliers = dir.appendingPathComponent("multipliers")
        try FileManager.default.createDirectory(at: multipliers, withIntermediateDirectories: true)
        let file = multipliers.appendingPathComponent("ww_digi_grid.csv")
        try Data("znacka;lokator;pocet\nOK1XOE;JO70;5\n".utf8).write(to: file)
        let dxcc = try DxccResolver.fromData(DxccTestFixture.data())
        #expect(GridDatabase.fromDir(dir).grid("ok1xoe") == "JO70")
        #expect(GridFieldMap.fromDir(dir, dxcc).matches("JO", entityCode: 503))
        #expect(!GridFieldMap.fromDir(dir, nil).known("JO"))
    }

    // MARK: - GridComment with a field map (section hamqth.GRIDF)

    private func gridfMap() throws -> GridFieldMap {
        let dxcc = try DxccResolver.fromData(DxccTestFixture.data())
        var csv = "znacka;lokator;pocet\nOK1XOE;JO70;5\nOK2ABC;JN79;1\nDL1ABC;JO60;2\nDL2XYZ;JN48;1\n"
        csv += "W1AW;FN31;9\nK5ABC;EM12;3\nVE3XYZ;FN03;1\nW6XYZ;DM04;2\nN0CALL;JO70;1\n"
        return GridFieldMap.build(Data(csv.utf8), dxcc)
    }

    @Test func gridCommentUsesFieldMap() throws {
        let map = try gridfMap()
        let czech = DxccEntity(entityCode: 503, name: "E", countryCode: "OK", continents: ["EU"], cq: [1], itu: [1],
                               lat: 49.8, lon: 15.5, primaryPrefix: "OK")
        let box = LogLines()
        let grid = GridComment.extractGrid("EM12/JO70<><ES>AA00", czech, fieldMap: map, log: { box.append($0) })
        #expect(grid == "JO70")
        #expect(box.lines == [
            "  kandidát EM12: pole EM nepatří OK (dle dat) \u{2192} zamítnut",
            "  kandidát JO70: pole JO patří OK (dle dat) \u{2192} PŘIJAT",
        ])
    }

    // MARK: - prefill

    @Test func prefillKeepsJavaMapSemantics() {
        typealias Field = ContestDefinition.ExchangeField
        let rec = HamQthRecord(grid: "jo70", name: "\u{2003}", cqZone: "\u{00A0}", ituZone: " 28 ")
        let fields: [Field] = [
            Field(id: nil, type: .LOCATOR, required: true, source: nil, appliesWhen: nil, validation: nil),
            Field(id: "Name", type: nil, required: true, source: nil, appliesWhen: nil, validation: nil),
            Field(id: "z", type: .ITU_ZONE, required: true, source: nil, appliesWhen: nil, validation: nil),
            Field(id: "z", type: .CQ_ZONE, required: true, source: nil, appliesWhen: nil, validation: nil),
            Field(id: "x", type: .LOCATOR, required: true, source: nil, appliesWhen: nil, validation: nil),
        ]
        let map = CallbookPrefill.prefill(rec, fields)
        #expect(map.keys == [nil, "z", "x"])
        #expect(map[nil] == "JO70")
        #expect(map["z"] == "\u{00A0}")
        #expect(map["x"] == "JO70")
        #expect(CallbookPrefill.describe(rec) == "JO70 \u{00B7} CQ \u{00A0} \u{00B7} ITU  28 ")
    }
}

/// Collector of log lines from a callback that does not require `@Sendable` (called synchronously).
private final class LogLines {
    private(set) var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }
}
