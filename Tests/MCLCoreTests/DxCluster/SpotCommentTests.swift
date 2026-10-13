import Foundation
import Testing
@testable import MCLCore

/// N1MM's spot comment macros, the special calls list and the `{SPOTME}` function-key macro.
@Suite struct SpotCommentTests {

    typealias Field = ContestDefinition.ExchangeField

    static func field(_ id: String, _ type: ContestDefinition.FieldType) -> Field {
        Field(id: id, type: type, required: true, source: nil, appliesWhen: nil, validation: nil)
    }

    static let received: [Field] = [field("rst", .RST), field("grid", .LOCATOR), field("zone", .CQ_ZONE),
                                    field("state", .STATE)]

    @Test func macrosAreFilledCaseInsensitivelyOnOneLine() {
        let fields = SpotComment.Fields(grid: "JN79", mode: "CW", qth: "PRG", zone: "15")
        #expect(SpotComment.expand("WPX {mode} {GRIDSQUARE} {QTH} z{ZONE}", fields) == "WPX CW JN79 PRG z15")
        #expect(SpotComment.expand("  {GRIDSQUARE}\r\n {QTH}  tnx ", .empty) == "tnx")
        #expect(SpotComment.expand("", fields) == "")
    }

    @Test func theEntryWindowsFieldsFillTheMacros() {
        let values: [String: String] = ["rst": "599", "grid": " jn79fx ", "zone": "15", "state": "ma"]
        let fields = SpotComment.fields(received: Self.received, mode: "CW", value: { values[$0] })
        #expect(fields == SpotComment.Fields(grid: "JN79FX", mode: "CW", qth: "MA", zone: "15"))
        let none = SpotComment.fields(received: [], mode: "SSB", value: { values[$0] })
        #expect(none == SpotComment.Fields(mode: "SSB"))
    }

    @Test func aLoggedQsosExchangeIsMatchedByOrder() {
        var qso = Qso()
        qso.mode = .cw
        qso.exchangeRcvd = "599 JN79 15 ma"
        #expect(SpotComment.fields(received: Self.received, qso: qso)
            == SpotComment.Fields(grid: "JN79", mode: "CW", qth: "MA", zone: "15"))
        qso.exchangeRcvd = "599 JN79"
        #expect(SpotComment.fields(received: Self.received, qso: qso) == SpotComment.Fields(grid: "JN79", mode: "CW"))
        qso.exchangeRcvd = "599 15"
        #expect(SpotComment.fields(received: Self.received, qso: qso) == SpotComment.Fields(mode: "CW"))
    }

    @Test func gridsAreRecognised() {
        #expect(SpotComment.isGrid("JN79"))
        #expect(SpotComment.isGrid("jn79fx"))
        #expect(!SpotComment.isGrid("ZZ79"))
        #expect(!SpotComment.isGrid("599"))
        #expect(!SpotComment.isGrid("JN79FZ"))
    }

    @Test func specialCallsFilesRoundTrip() {
        let text = "Type=FAVORITES SubType=\r\nW1AW\r\n# club\r\nok1abc, OK1ABC; DL1XX\n\nbad call!\n"
        #expect(SpecialCalls.parse(text) == ["W1AW", "OK1ABC", "DL1XX", "BAD"])
        #expect(SpecialCalls.export(["W1AW", "OK1ABC"]) == "Type=FAVORITES SubType=\nW1AW\nOK1ABC\n")
        #expect(SpecialCalls.parse(SpecialCalls.export(["W1AW"])) == ["W1AW"])
    }

    @Test func specialCallsMatchByBase() {
        let bases: Set<String> = SpecialCalls.bases(["W1AW", "OK1ABC/P", " "])
        #expect(bases == ["W1AW", "OK1ABC"])
        #expect(SpecialCalls.matches("W1AW/M", bases: bases))
        #expect(SpecialCalls.matches("DL/W1AW", bases: bases))
        #expect(SpecialCalls.matches("ok1abc", bases: bases))
        #expect(SpecialCalls.matches("W1AW-2", bases: bases))
        #expect(!SpecialCalls.matches("W1AWX", bases: bases))
        #expect(!SpecialCalls.matches("W1AW", bases: []))
    }

    @Test func theBandMapLabelCarriesTheHeart() {
        let label: String = BandmapSpotInfo.label(call: "W1AW", azimuth: nil, skimmers: 0, skimmerMark: "#",
                                                  grayLine: false, qsxHz: nil, isNew: false, special: true)
        #expect(label.hasPrefix("W1AW\u{2665}#"))
    }

    @Test func spotMeIsAControlMacroInEveryMessagePath() {
        let ctx = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "", lastLogged: "", serial: 1, rst: "599",
                                           exchange: "", cutNumbers: false, leadingZeros: false, now: nil)
        let message: CwMessage = CwMessageBuilder.build("CQ {SPOTME} TEST", ctx)
        #expect(message.actions == [.spotMe])
        #expect(message.unknownMacros.isEmpty)
        #expect(VoiceMessagePlanner.isControlMacro("{spotme}"))
        #expect(BandmapButtonCommand.steps("{SPOTME}") == [.refused("{SPOTME}")])
    }

    @Test func theOptionsDefaultToNothingAutomatic() throws {
        let empty = try JSONDecoder().decode(DxClusterConfig.self, from: Data("{}".utf8))
        #expect(empty.spotComment == "")
        #expect(!empty.spotAllSpQsos)
        #expect(empty.specialCalls.isEmpty)
        #expect(empty.specialCallsIncludeBonus)
        var config = DxClusterConfig()
        config.spotComment = "WPX {MODE}"
        config.spotAllSpQsos = true
        config.specialCalls = ["W1AW"]
        config.specialCallsIncludeBonus = false
        #expect(try JSONDecoder().decode(DxClusterConfig.self, from: JSONEncoder().encode(config)) == config)
    }
}
