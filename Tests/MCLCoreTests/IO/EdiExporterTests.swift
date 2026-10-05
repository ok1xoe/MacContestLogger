import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `io/EdiExporterTest` (1 test) + full match with Java over logs
/// `ExportsFixture` (reference `ExportsMeasured`, maintainer-only probe).
@Suite struct EdiExporterTests {

    /// Java `reg1testHeaderAndRecords`.
    @Test func reg1testHeaderAndRecords() throws {
        let def = try ExportsFixture.iaruVhf()
        var st = StationConfig()
        st.call = "OK1XOE"
        let header = EdiExporter.Header(section: "SINGLE", power: "100", antenna: "yagi", operators: "OK1XOE",
                                        remarks: "")
        let edi = EdiExporter.export(def, st, header, ExportsFixture.ediTestLog(), .m2, "JO70FC") { _ in
            ExportsFixture.received(def)
        }

        #expect(edi.hasPrefix("[REG1TEST;1]\r\n"))
        #expect(edi.contains("PBand=144 MHz\r\n"))
        #expect(edi.contains("CQSOs=2;1\r\n"))
        #expect(edi.contains("CWWLs=2;0;1\r\n"))
        #expect(edi.contains("CDXCs=2;0;1\r\n"))
        #expect(edi.contains("CODXC=DL1ABC;JO62QM;279\r\n"))
        #expect(edi.contains("[QSORecords;3]\r\n"))
        let lines = edi.components(separatedBy: "\r\n")
        let first = try #require(lines.first { $0.hasPrefix("260801;1400;DL1ABC") })
        let f = first.components(separatedBy: ";")
        #expect(f[3] == "1", "SSB = 1")
        #expect(f[5] == "001")
        #expect(f[7] == "005")
        #expect(f[9] == "JO62QM")
        #expect(f[12] == "N", "new big square")
        #expect(lines.contains { $0.hasPrefix("260801;1409;DL1ABC") && $0.hasSuffix(";D") }, "dupe")
        #expect(ExportsFixture.bytes(edi) == ExportsFixture.bytes(ExportsMeasured.ediTest.joined()))
    }

    /// `š` in the name and address (the output is a `String`, the encoding is up to the caller —),
    /// dupe (also in lowercase), X-QSO, own locator = 1 point, an invalid `XX00` = 0 points,
    /// but a new square, a 4-character locator, a number over 4 digits, a negative number, a fallback
    /// locator lookup (empty fields for `YU1A`), another band, deleted, without time, the same time.
    @Test func edgeLogMatchesJava() throws {
        let def = try ExportsFixture.iaruVhf()
        let (station, header) = Self.edgeStation()
        let log = ExportsFixture.ediEdgeLog()
        let fields: (String) -> [ContestDefinition.ExchangeField] = { call in
            call == "YU1A" ? [] : ExportsFixture.received(def)
        }
        let m2 = EdiExporter.export(def, station, header, log, .m2, "jo70fc", fields)
        #expect(ExportsFixture.bytes(m2) == ExportsFixture.bytes(ExportsMeasured.ediEdge.joined()))
        let cm70 = EdiExporter.export(def, station, header, log, .cm70, "JO70FC", fields)
        #expect(ExportsFixture.bytes(cm70) == ExportsFixture.bytes(ExportsMeasured.ediEdge70cm.joined()))
    }

    /// A band without QSOs, a header from `null` values, without an own locator.
    @Test func bandWithoutQsoMatchesJava() throws {
        let def = try ExportsFixture.iaruVhf()
        let (station, _) = Self.edgeStation()
        let header = EdiExporter.Header(section: nil, power: nil, antenna: nil, operators: nil, remarks: "   ")
        let edi = EdiExporter.export(def, station, header, ExportsFixture.ediEdgeLog(), .m6, nil) { _ in
            ExportsFixture.received(def)
        }
        #expect(ExportsFixture.bytes(edi) == ExportsFixture.bytes(ExportsMeasured.ediEmptyBand.joined()))
    }

    /// An exception from `receivedFields` (in Swift `ContestSession.activeReceivedFields` throws) passes
    /// out as in Java.
    @Test func receivedFieldsErrorPropagates() throws {
        let def = try ExportsFixture.iaruVhf()
        let header = EdiExporter.Header(section: nil, power: nil, antenna: nil, operators: nil, remarks: nil)
        #expect(throws: CocoaError.self) {
            _ = try EdiExporter.export(def, StationConfig(), header, ExportsFixture.ediTestLog(), .m2, "JO70FC") { _ in
                throw CocoaError(.featureUnsupported)
            }
        }
    }

    /// Points are `ceil(km)`: the raw fixture distances are far from a whole km, so the Darwin libm × HotSpot
    /// difference does not change the points. Java values
    /// pinned; raw km with a tolerance of 1e-8, `ceil` exactly.
    @Test func fixtureDistancesMatchJava() throws {
        for line in ExportsMeasured.distancesFromJO70FC {
            let parts = JavaText.trim(line).components(separatedBy: " ")
            let java = try #require(JavaDouble.parseDouble(parts[1]))
            let swift = Maidenhead.distanceKm("JO70FC", parts[0])
            #expect(abs(swift - java) <= 1e-8, "\(parts[0])")
            #expect(swift.rounded(.up) == java.rounded(.up), "\(parts[0])")
            if java > 0 {
                let fraction = java - java.rounded(.down)
                #expect(fraction > 1e-6 && fraction < 1 - 1e-6, "\(parts[0]) close to a whole km")
            }
        }
    }

    @Test func bandNamesMatchJava() {
        let names = Band.javaV111Cases.map { $0.adif + "=" + EdiExporter.bandName($0) + "\n" }
        #expect(ExportsFixture.bytes(names.joined()) == ExportsFixture.bytes(ExportsMeasured.bandNames.joined()))
    }

    /// `modeCode`: 1 SSB, 2 CW, 5 AM, 6 FM, 7 RTTY, 0 others and `null`.
    @Test func modeCodes() {
        let codes = Mode.allCases.map { EdiExporter.modeCode($0) }
        #expect(codes == [2, 1, 6, 5, 7, 0, 0, 0, 0, 0])
        #expect(EdiExporter.modeCode(nil) == 0)
    }

    private static func edgeStation() -> (StationConfig, EdiExporter.Header) {
        var st = StationConfig()
        st.call = "ok1xoe"
        st.name = "Tomáš Šťastný"
        st.address1 = "Na Výsluní 1"
        st.city = "Praha"
        st.country = "Czech Republic"
        st.club = "OK1KHL"
        st.email = "ok1xoe@example.org"
        let header = EdiExporter.Header(section: "SINGLE-OP", power: "100", antenna: "yagi 11el",
                                        operators: "OK1XOE OK1ABC", remarks: "  Poznámka š  ")
        return (st, header)
    }
}

/// Port of the Java `io/LogPrinterTest` (1 test) + `paginate` edges measured in Java.
/// `print` (an AWT dialog) is the app layer's.
@Suite struct LogPrinterTests {

    /// Java `paginatesWithRepeatedHeader`.
    @Test func paginatesWithRepeatedHeader() {
        var lines = ["TITLE", "-----", "cols"]
        for i in 1...10 {
            lines.append("qso " + String(i))
        }
        let pages = LogPrinter.paginate(lines, headerLines: 3, linesPerPage: 7) // 4 QSOs per page
        #expect(pages.count == 3)
        #expect(pages[0] == ["TITLE", "-----", "cols", "qso 1", "qso 2", "qso 3", "qso 4"])
        #expect(pages[2][2] == "cols")
        #expect(Array(pages[2][3..<5]) == ["qso 9", "qso 10"])
        let empty = LogPrinter.paginate(["TITLE", "-----", "cols"], headerLines: 3, linesPerPage: 7)
        #expect(empty.count == 1, "an empty log = one page")
    }

    /// An exact multiple of a page, `linesPerPage ≤ headerLines`, a header longer than the input, `[]`,
    /// without a header, a negative line count.
    @Test func edgesMatchJava() {
        var lines = ["TITLE", "-----", "cols"]
        for i in 1...8 {
            lines.append("qso " + String(i))
        }
        var out = "# exact 3/7\n" + ExportsFixture.pages(lines, 3, 7)
        out += "# perPage<=header 3/3\n" + ExportsFixture.pages(lines, 3, 3)
        out += "# header>size 20/7\n" + ExportsFixture.pages(["a", "b"], 20, 7)
        out += "# empty 3/7\n" + ExportsFixture.pages([], 3, 7)
        out += "# no header 0/5\n" + ExportsFixture.pages(lines, 0, 5)
        out += "# negative 0/-1\n" + ExportsFixture.pages(["a", "b"], 0, -1)
        #expect(ExportsFixture.bytes(out) == ExportsFixture.bytes(ExportsMeasured.paginate.joined()))
    }
}
