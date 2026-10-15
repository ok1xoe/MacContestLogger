import Foundation
import Testing
@testable import MCLCore

/// WAE QTC (N1MM Config → WAE): the setup map, the QTC window's messages with `{QTC}` and `$`, the RTTY series, the
/// sides, the band map colours and the QTC macros of the F-key messages.
@Suite struct QtcSetupTests {

    @Test func defaultsAreNotStoredAndCountsAreClamped() {
        var setup = QtcSetup(["cwQrv": "QRV", "unknown": "x", "cwConfirm": "TU"])
        #expect(setup.values == ["cwConfirm": "TU"])
        #expect(setup.text(.cwQrv) == "QRV")
        #expect(setup.text(.cwConfirm) == "TU")
        #expect(!setup.flag(.ctrlZSendsAsk))
        setup.set(.ctrlZSendsAsk, flag: true)
        #expect(setup.flag(.ctrlZSendsAsk))
        setup.set(.ctrlZSendsAsk, flag: false)
        setup.set(.cwConfirm, "R")
        #expect(setup.values.isEmpty)
        setup.set(.sendCount, "4")
        #expect(setup.number(.sendCount) == 4)
        setup.set(.sendCount, "40")
        #expect(setup.number(.sendCount) == 10)
        setup.set(.colorMax, "abc")
        #expect(setup.number(.colorMax) == 10)
    }

    @Test func theSetupIsKeptInTheConfiguration() throws {
        var config = AppConfig()
        var setup = config.qtc
        setup.set(.cwAgain, "AGN $ PSE")
        config.qtc = setup
        #expect(config.qtcSetup == ["cwAgain": "AGN $ PSE"])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.qtc.text(.cwAgain) == "AGN $ PSE")
    }

    @Test func qtcAndDollarAreExpanded() {
        #expect(QtcMessages.expand("QTC {qtc} QTC {QTC}", header: "26/10", number: 0) == "QTC 26/10 QTC 26/10")
        #expect(QtcMessages.expand("AGN $ $", header: "", number: 3) == "AGN 3 3")
        #expect(QtcMessages.expand("AGN $", header: "", number: 0) == "AGN ")
        #expect(QtcMessages.expand("{QTCX} {Q", header: "1/1", number: 0) == "{QTCX} {Q")
    }

    @Test func headers() {
        #expect(QtcMessages.receivedHeader("12") == "12/10")
        #expect(QtcMessages.receivedHeader(" 12 / 7 ") == "12/7")
        #expect(QtcMessages.receivedHeader("") == "")
        #expect(QtcMessages.receivedHeader("x") == "x")
        #expect(QtcMessages.header(group: 3, count: 5) == "3/5")
    }

    @Test func messagesFollowTheModeAndSide() {
        let setup = QtcSetup()
        #expect(QtcMessages.kinds(sending: false, family: .cw) == [.ask, .ready, .confirm, .again(0), .receivedDone])
        #expect(QtcMessages.kinds(sending: false, family: .digital) == [.ready, .allAgain, .again(0), .receivedDone])
        #expect(QtcMessages.kinds(sending: true, family: .digital) == [.askReady, .sentDone])
        #expect(QtcMessages.kinds(sending: true, family: .phone) == [.sentDone])
        #expect(QtcMessages.outgoing(.ready, family: .cw, setup: setup, header: "") == .message("QRV"))
        #expect(QtcMessages.outgoing(.again(4), family: .cw, setup: setup, header: "") == .message("AGN 4"))
        #expect(QtcMessages.outgoing(.receivedDone, family: .cw, setup: setup, header: "1/10") == .tuKey)
        #expect(QtcMessages.outgoing(.sentDone, family: .phone, setup: setup, header: "") == .tuKey)
        #expect(QtcMessages.outgoing(.ready, family: .phone, setup: setup, header: "") == .message("qtc-qrv.wav"))
        #expect(QtcMessages.outgoing(.again(2), family: .digital, setup: setup, header: "")
                == .message("QTC 2 AGN QTC 2 AGN"))
        #expect(QtcMessages.outgoing(.askReady, family: .digital, setup: setup, header: "5/10")
                == .message("! QTC 5/10 QRV?"))
        #expect(QtcMessages.outgoing(.confirm, family: .digital, setup: setup, header: "") == nil)
        var tu = QtcSetup()
        tu.set(.cwTu, "TU {QTC} QSL")
        #expect(QtcMessages.outgoing(.receivedDone, family: .cw, setup: tu, header: "7/10") == .message("TU 7/10 QSL"))
        tu.set(.cwQrv, "  ")
        #expect(QtcMessages.outgoing(.ready, family: .cw, setup: tu, header: "") == nil)
    }

    @Test func theDigitalSeriesJoinsHeadingLinesAndEnding() {
        let lines = [QtcPlanner.Line(time: "1234", call: "DL1ABC", serial: 56),
                     QtcPlanner.Line(time: "1301", call: "OK1XOE", serial: 7)]
        #expect(QtcMessages.digitalSeries(header: "3/2", lines: lines, setup: QtcSetup())
                == "QTC 3/2 QTC 3/2{ENTER}1234 DL1ABC 56{ENTER}1301 OK1XOE 7{ENTER}END QTC")
        var setup = QtcSetup()
        setup.set(.rttyHeading, "")
        setup.set(.rttySpacing, " ")
        #expect(QtcMessages.digitalSeries(header: "3/2", lines: lines, setup: setup)
                == "1234 DL1ABC 56 1301 OK1XOE 7 END QTC")
    }

    @Test func sidesAndColours() {
        #expect(QtcRules.role(ownContinent: "EU") == .receive)
        #expect(QtcRules.role(ownContinent: "NA") == .send)
        #expect(QtcRules.role(ownContinent: nil) == .receive)
        #expect(QtcRules.canExchange(ownContinent: "EU", otherContinent: "NA", anyContinent: false))
        #expect(!QtcRules.canExchange(ownContinent: "EU", otherContinent: "EU", anyContinent: false))
        #expect(!QtcRules.canExchange(ownContinent: "EU", otherContinent: "EU", anyContinent: true))
        #expect(QtcRules.canExchange(ownContinent: "NA", otherContinent: "AS", anyContinent: true))
        #expect(!QtcRules.canExchange(ownContinent: "EU", otherContinent: nil, anyContinent: true))
        #expect(QtcRules.color(dupe: true, newMultCount: 0, qtcLeft: true) == .qtc)
        #expect(QtcRules.color(dupe: true, newMultCount: 0, qtcLeft: false) == .dupe)
        #expect(QtcRules.color(dupe: false, newMultCount: 1, qtcLeft: true) == .oneMult)
        #expect(QtcRules.color(dupe: false, newMultCount: 0, qtcLeft: true) == .multiMult)
        #expect(QtcRules.color(dupe: false, newMultCount: 0, qtcLeft: false) == .good)
        let record = QtcRecord(id: 1, contestId: nil, sent: false, partnerCall: " w1aw ", groupNr: 1, groupSize: 1,
                               qsoTime: "1200", qsoCall: "OK1A", qsoSerial: 1, at: Date(timeIntervalSince1970: 0),
                               freqHz: 0, mode: nil)
        #expect(QtcRules.counts([record, record]) == ["W1AW": 2])
    }

    @Test func qtcMacrosOfTheFunctionKeys() {
        var ctx = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "W1AW", lastLogged: "", serial: 1, rst: "599",
                                           exchange: "", cutNumbers: false, leadingZeros: false, now: nil)
        ctx.qtcHeader = "12/10"
        let message = CwMessageBuilder.build("TU {QTC} {DIGQTCR}{DIGQTCS}", ctx)
        #expect(message.plainText() == "TU 12/10")
        #expect(message.actions == [.qtcReceive, .qtcSend])
        #expect(message.unknownMacros.isEmpty)
    }

    @Test func aQtcTemplateIsSentLikeAnFKeyMessage() {
        let base = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "", lastLogged: "", serial: 7, rst: "",
                                            exchange: "", cutNumbers: false, leadingZeros: false, now: nil)
        let set = FunctionKeySet(run: [], sp: [])
        var context = FunctionKeyContext(mode: .cw, digitalReady: false, postContest: false, run: true, call: "W1AW",
                                         rstSent: "", freqHz: 14_025_000, progress: .empty, stationCall: "OK1XOE",
                                         voice: set, cw: set, digital: set, cwBase: base)
        let out = FunctionKeyRouter.sendQtcTemplate("QRV {FOO}", context: context)
        guard case .cw(let message, let index) = out.transmission else {
            Issue.record("no CW transmission")
            return
        }
        #expect(message.plainText() == "QRV")
        #expect(index == -1)
        #expect(out.status == .tr("%s: makra %s zatím neumím — vynechána", .string("QTC"), .string("{FOO}")))
        #expect(out.progress == nil, "a QTC message is no ESM step")
        context.mode = .ssb
        #expect(FunctionKeyRouter.sendQtcTemplate("QRV", context: context).transmission == nil)
        context.mode = .rtty
        #expect(FunctionKeyRouter.sendQtcTemplate("QRV", context: context).status
                == .tr("QTC: pro %s nastav fldigi (Nastavení → Digitální módy)", .string("RTTY")))
        context.digitalReady = true
        if case .digital(let text, _, _) = FunctionKeyRouter.sendQtcTemplate("QRV", context: context).transmission {
            #expect(text == "QRV")
        } else {
            Issue.record("no digital transmission")
        }
    }
}
