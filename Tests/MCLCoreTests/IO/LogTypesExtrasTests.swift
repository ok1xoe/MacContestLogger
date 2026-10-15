import Foundation
import Testing
@testable import MCLCore

/// N1MM log extras: QSOs by grid, the grid / country check and big grid, ADIF fields of a definition (DXSATELLIT) and
/// the generic text output in a contest's layout.
@Suite struct LogTypesExtrasTests {

    private static func qso(_ call: String, _ exchange: String, hour: Int = 12) -> Qso {
        var qso = Qso()
        qso.call = call
        qso.exchangeRcvd = exchange
        qso.uuid = call.lowercased()
        qso.freqHz = 145_300_000
        qso.mode = .fm
        qso.rstSent = "59"
        qso.rstRcvd = "57"
        qso.serialSent = 7
        qso.exchangeSent = "59 JN79"
        qso.timestampUtc = Date(timeIntervalSince1970: 1_790_000_000 + Double(hour) * 3600)
        return qso
    }

    @Test func gridSearchFindsTheReceivedLocator() {
        let qsos = [Self.qso("OK1ABC", "59 JN79AB"), Self.qso("DL1ABC", "59 JO62"), Self.qso("G4ABC", "59 IO91")]
        #expect(QsoSearch.filter(qsos, "grid:jn79").map(\.call) == ["OK1ABC"])
        #expect(QsoSearch.filter(qsos, "loc:JO").map(\.call) == ["DL1ABC"])
        #expect(QsoSearch.filter(qsos, "grid:JN79AB").map(\.call) == ["OK1ABC"])
        #expect(QsoSearch.locators(Self.qso("X", "59 001 jn79 ZZ99")) == ["JN79"])
        #expect(QsoSearch.isLocator("JN79AB") && !QsoSearch.isLocator("JN7") && !QsoSearch.isLocator("SS12"))
    }

    @Test func gridCountryCheckAndBigGrid() throws {
        let dxcc = try SessionFixture.dxcc()
        let map = GridFieldMap.build(Data("OK1ABC;JN79;1\nOK1XYZ;JO70;1\nDL1ABC;JO62;1\n".utf8), dxcc)
        let ok = try #require(dxcc.resolve("OK1XOE"))
        let dl = try #require(dxcc.resolve("DL1XYZ"))
        #expect(GridCountry.plausible("JN79", entity: ok, fieldMap: map))
        #expect(GridCountry.plausible("JO62", entity: dl, fieldMap: map))
        #expect(!GridCountry.plausible("JN79", entity: dl, fieldMap: map))
        // An unknown field and no coordinates in the fixture: nothing to check against.
        #expect(GridCountry.plausible("FN31", entity: ok, fieldMap: map))
        #expect(GridCountry.bigGrid(entity: dl, fieldMap: map) == "JO")
        #expect(GridCountry.bigGrid(entity: ok, fieldMap: map) == nil)
        #expect(GridCountry.bigGrid(entity: ok, fieldMap: nil) == nil)
        #expect(map.fields(entityCode: ok.entityCode) == ["JN", "JO"])
    }

    @Test func satelliteDefinitionWritesAdifFields() throws {
        let definition = try ContestDefinitionLoader.loadFile(
            PublishedContestDataTests.root.appendingPathComponent("contests/dx-satellite.yaml"))
        let dxcc = try SessionFixture.dxcc()
        let registry = try MultiplierSetRegistry(dxcc: dxcc)
            .loadDir(PublishedContestDataTests.root.appendingPathComponent("multipliers"))
        let session = ContestSession(definition: definition, dxcc: dxcc, registry: registry, myCall: "OK1XOE")
        let qsos = [Self.qso("OK1ABC", "57 AO-91 JN79"), Self.qso("DL1ABC", "57 RS-44")]
        let extra = AdifExtraFields.compute(definition, session: session, qsos: qsos)
        #expect(extra["ok1abc"] == [AdifExtraFields.Field(name: "PROP_MODE", value: "SAT"),
                                    AdifExtraFields.Field(name: "SAT_NAME", value: "AO-91"),
                                    AdifExtraFields.Field(name: "GRIDSQUARE", value: "JN79")])
        #expect(extra["dl1abc"]?.count == 2)
        var writer = AdifWriter()
        writer.extraFields = extra
        let adif: String = writer.toAdif(qsos)
        #expect(adif.contains("<PROP_MODE:3>SAT <SAT_NAME:5>AO-91 <GRIDSQUARE:4>JN79"))
        #expect(AdifExtraFields.compute(nil, session: session, qsos: qsos).isEmpty)
    }

    @Test func textExportFollowsTheTemplate() {
        let qsos = [Self.qso("DL1ABC", "57 JO62", hour: 13), Self.qso("OK1ABC", "59 JN79", hour: 12)]
        let received: (Qso) -> JavaLinkedMap<String> = { qso in
            let parts = qso.exchangeRcvd.split(separator: " ").map(String.init)
            return JavaLinkedMap([("rst", parts[0]), ("loc", parts[1])])
        }
        let text: String = FormattedTextExport.text(qsos, template: "{time} {call:8}|{loc:-6}|{nrs:3}{mycall}",
                                                    myCall: "OK1XOE", received: received)
        #expect(text == "0213 OK1ABC  |  JN79|7  OK1XOE\n0313 DL1ABC  |  JO62|7  OK1XOE\n")
        let fallback: String = FormattedTextExport.text([qsos[1]], template: "  ", myCall: "", received: received)
        #expect(fallback.hasPrefix("2026-09-22 0213  145300 FM    OK1ABC        59  59 JN79        57  59 JN79"))
        #expect(FormattedTextExport.line(qsos[0], layout: "{call:3}{unknown}{", myCall: "", received: JavaLinkedMap())
                    == "DL1{")
    }

    @Test func waeRttyLetsEverybodyWorkEverybody() throws {
        let definition = try ContestDefinitionLoader.loadFile(
            PublishedContestDataTests.root.appendingPathComponent("contests/wae-rtty.yaml"))
        let dxcc = try SessionFixture.dxcc()
        let registry = try MultiplierSetRegistry(dxcc: dxcc)
            .loadDir(PublishedContestDataTests.root.appendingPathComponent("multipliers"))
        let session = ContestSession(definition: definition, dxcc: dxcc, registry: registry, myCall: "OK1XOE")
        session.setQtcCount(3)
        for (call, band) in [("DL1ABC", "80m"), ("W1AW", "20m")] {
            _ = try session.log(call: call, band: band, mode: "RTTY",
                                receivedRaw: SessionFixture.raw(("rst", "599"), ("nr", "1")),
                                at: Date(timeIntervalSince1970: 1_795_867_500))
        }
        let score = try session.score()
        #expect(score.qsoPoints == 2)
        // DL on 80 m x4 + W on 20 m x2; (2 QSOs + 3 QTCs) x 6.
        #expect(score.multTotal == 6)
        #expect(score.total == 30)
    }
}
