import Foundation
import Testing
@testable import MCLCore

/// `ExportJobs` and the export names against the Kotlin `AppState.exportEdi` (`AS:4055-4074`) and `exportOther`
/// (`AS:4038-4052`) of v1.1.1.
@Suite struct ExportJobsTests {

    private static func station(call: String = "OK1XOE", grid: String = "JO70FC") -> StationConfig {
        var st = StationConfig()
        st.call = call
        st.gridSquare = grid
        st.power = "100"
        st.antenna = "yagi"
        return st
    }

    private static func vhfLog() -> [Qso] {
        var log = ExportsFixture.ediTestLog()
        var uhf = ExportsFixture.edi(20, "OK1AAA", .ssb, "59 1 JN79AA", 4)
        uhf.freqHz = 432_100_000
        uhf.band = .cm70
        log.insert(uhf, at: 0)
        var deleted = ExportsFixture.edi(21, "OK1DEL", .ssb, "59 1 JO80AA", 5)
        deleted.band = .m6
        deleted.deleted = true
        log.append(deleted)
        return log.map { q in
            var q = q
            if q.band == nil { q.band = .m2 }
            return q
        }
    }

    // MARK: - EDI checks, in Kotlin order

    @Test func ediChecksInKotlinOrder() throws {
        let def = try ExportsFixture.iaruVhf()
        let fields: (String) -> [ContestDefinition.ExchangeField] = { _ in ExportsFixture.received(def) }
        let noContest = ExportJobs.edi(definition: nil, station: Self.station(grid: ""), setup: nil, qsos: [],
                                       fields: fields)
        #expect(Self.failure(noContest) == IoTexts.ediNoContest)
        // `trim()` before the length check: " JO70F " is 5.
        let short = ExportJobs.edi(definition: def, station: Self.station(grid: " JO70F "), setup: nil, qsos: [],
                                   fields: fields)
        #expect(Self.failure(short) == IoTexts.ediNoLocator)
        var onlyDeleted = ExportsFixture.edi(0, "DL1ABC", .ssb, "59 5 JO62QM", 1)
        onlyDeleted.band = .m2
        onlyDeleted.deleted = true
        var noBand = ExportsFixture.edi(1, "DL1ABC", .ssb, "59 5 JO62QM", 1)
        noBand.band = nil
        let empty = ExportJobs.edi(definition: def, station: Self.station(grid: " JO70FC "), setup: nil,
                                   qsos: [onlyDeleted, noBand], fields: fields)
        #expect(Self.failure(empty) == IoTexts.ediEmpty)
    }

    /// One file per band sorted by `lowHz` (deleted QSOs' bands left out), named `<call with _>_<adif>.edi`,
    /// each the exporter's text for that band with the trimmed locator, ISO-8859-1.
    @Test func ediWritesOneFilePerBand() throws {
        let def = try ExportsFixture.iaruVhf()
        let fields: (String) -> [ContestDefinition.ExchangeField] = { _ in ExportsFixture.received(def) }
        let station = Self.station(call: "OK1XOE/P", grid: " JO70FC ")
        let log = Self.vhfLog()
        let files = try Self.success(ExportJobs.edi(definition: def, station: station, setup: nil, qsos: log,
                                                    fields: fields))
        #expect(files.map(\.name) == ["OK1XOE_P_2m.edi", "OK1XOE_P_70cm.edi"])
        let header = EdiExporter.Header(section: "SINGLE", power: "100", antenna: "yagi", operators: "OK1XOE/P",
                                        remarks: "")
        let expected = EdiExporter.export(def, station, header, log, .m2, "JO70FC", fields)
        #expect(files[0].bytes == Data(expected.utf8))
    }

    @Test func ediHeaderFromSetup() {
        let st = Self.station()
        #expect(ExportJobs.ediHeader(station: st, setup: nil)
            == EdiExporter.Header(section: "SINGLE", power: "100", antenna: "yagi", operators: "OK1XOE", remarks: ""))
        var setup = ContestSetup()
        setup.category = ["OPERATOR": "MULTI-ONE"]
        setup.operators = "OK1AA OK1BB"
        setup.soapbox = "73"
        #expect(ExportJobs.ediHeader(station: st, setup: setup)
            == EdiExporter.Header(section: "MULTI", power: "100", antenna: "yagi", operators: "OK1AA OK1BB",
                                  remarks: "73"))
        setup.category = ["OPERATOR": "multi-one"]
        setup.operators = " \u{3000}"
        let blank = ExportJobs.ediHeader(station: st, setup: setup)
        #expect(blank.section == "SINGLE")
        #expect(blank.operators == "OK1XOE")
        setup.category = [:]
        #expect(ExportJobs.ediHeader(station: st, setup: setup).section == "SINGLE")
    }

    /// Java `Files.writeString(…, ISO_8859_1)` throws on a character above U+00FF and the band drops out silently.
    @Test func ediLeavesOutBandsThatAreNotLatin1() throws {
        let def = try ExportsFixture.iaruVhf()
        let fields: (String) -> [ContestDefinition.ExchangeField] = { _ in ExportsFixture.received(def) }
        var station = Self.station()
        station.name = "Tomáš"
        let files = try Self.success(ExportJobs.edi(definition: def, station: station, setup: nil,
                                                    qsos: Self.vhfLog(), fields: fields))
        #expect(files.isEmpty)
        #expect(ExportJobs.latin1("Tomá") == Data([0x54, 0x6F, 0x6D, 0xE1]))
        #expect(ExportJobs.latin1("š") == nil)
    }

    @Test func ediBandsAreDistinctAndSorted() {
        var qsos: [Qso] = []
        for band in [Band.cm70, .m2, .m6, .m2] {
            var q = Qso()
            q.band = band
            qsos.append(q)
        }
        #expect(ExportJobs.ediBands(qsos) == [.m6, .m2, .cm70])
    }

    // MARK: - names

    @Test func exportNames() {
        #expect(ExportNames.ediFileName(call: "ok1xoe/p", band: .m2) == "ok1xoe_p_2m.edi")
        #expect(ExportNames.ediFileName(call: "", band: .m6) == "_6m.edi")
        #expect(ExportNames.otherBase(call: "OK1XOE/P") == "OK1XOE_P")
        #expect(ExportNames.otherBase(call: " ") == "log")
        #expect(ExportNames.otherBase(call: "") == "log")
        #expect(ExportNames.otherBase(call: " X ") == " X ")
    }

    // MARK: - other exports

    @Test func otherBuildsThreeUtf8Files() throws {
        let log = ExportsFixture.testLog()
        let files = try ExportJobs.other(contestName: "CQ WW", call: "OK1XOE/P", score: nil, qsos: log)
        #expect(files.map(\.name) == ["OK1XOE_P.csv", "OK1XOE_P.txt", "OK1XOE_P-summary.txt"])
        #expect(files[0].bytes == Data(LogExports.csv(log).utf8))
        #expect(files[1].bytes == Data(LogExports.text("CQ WW — OK1XOE/P", log).utf8))
        #expect(files[2].bytes == Data(try LogExports.summary("CQ WW", "OK1XOE/P", nil, log).utf8))
    }

    @Test func writeSkipsFilesThatFail() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-jobs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("b.txt"),
                                                withIntermediateDirectories: true)
        let files = [ExportFile(name: "a.csv", bytes: Data("a".utf8)), ExportFile(name: "b.txt", bytes: Data()),
                     ExportFile(name: "c.txt", bytes: Data("č".utf8))]
        #expect(ExportJobs.write(files, to: dir) == ["a.csv", "c.txt"])
        #expect(try Data(contentsOf: dir.appendingPathComponent("c.txt")) == Data([0xC4, 0x8D]))
    }

    @Test func statusTexts() {
        #expect(IoTexts.ediNoContest.czech == "EDI: není aktivní závod")
        #expect(IoTexts.ediNoLocator.czech == "EDI: doplň 6místný lokátor stanice (Nastavení → Stanice)")
        #expect(IoTexts.ediEmpty.czech == "EDI: deník je prázdný")
        #expect(IoTexts.ediWritten(names: ["A_2m.edi", "A_70cm.edi"], dir: "/x").czech
            == "EDI: zapsáno A_2m.edi, A_70cm.edi do /x")
        let other = IoTexts.otherWritten(names: ["a.csv", "a.txt"], dir: "/x")
        #expect(other == .verbatim("Export: a.csv, a.txt do /x"))
        #expect(IoTexts.defaultLogName == "Deník")
    }

    // MARK: - helpers

    private static func failure(_ result: Result<[ExportFile], ContestMessage>) -> ContestMessage? {
        if case .failure(let message) = result { return message }
        return nil
    }

    private static func success(_ result: Result<[ExportFile], ContestMessage>) throws -> [ExportFile] {
        try result.get()
    }
}
