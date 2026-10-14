import Foundation
import Testing
@testable import MCLCore

/// The N1MM text and action macros added beside the Java set: the last QSO, names, station, frequency, locator
/// geometry, time and date, `{VARYMSGn}` and the parameterized `{COMMENT}`.
@Suite struct N1mmTextMacroTests {

    private typealias Ctx = CwMessageBuilder.Context

    /// 2026-10-14 17:36:55 UTC.
    private static let moment = Date(timeIntervalSince1970: 1_791_999_415)

    private static func ctx() -> Ctx {
        var ctx = Ctx(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "K1A", serial: 7, rst: "599", exchange: "15",
                      cutNumbers: false, leadingZeros: false,
                      station: CwMessageBuilder.StationData(name: "TOM", grid: "JO70EB", cqZone: "15", ituZone: "28",
                                                            state: "", operator: "OK1XOE"),
                      now: moment)
        ctx.timeZone = TimeZone(identifier: "Europe/Prague")!
        ctx.locale = Locale(identifier: "en_US_POSIX")
        return ctx
    }

    private static func text(_ template: String, _ edit: (inout Ctx) -> Void = { _ in }) -> String {
        var context = ctx()
        edit(&context)
        return CwMessageBuilder.build(template, context).plainText()
    }

    @Test func lastQsoMacros() {
        let sent = Self.text("{LASTCALL} {PREVNR} {LASTEXCH} {PREVTIME}") { ctx in
            ctx.lastSerial = "41"
            ctx.lastExchange = "15"
            ctx.lastTime = Self.moment.addingTimeInterval(-3_600)
        }
        #expect(sent == "K1A 41 15 1636")
        // Nothing logged yet: the macros are empty, never unknown.
        let empty = CwMessageBuilder.build("{PREVNR}{LASTEXCH}{PREVTIME}", Self.ctx())
        #expect(empty.unknownMacros.isEmpty)
        #expect(empty.isEmpty)
    }

    @Test func nameMacrosPreferTheNameField() {
        #expect(Self.text("tu {NAME}") { $0.hisName = "PETE" } == "TU PETE")
        #expect(Self.text("tu {NAME}") { ctx in
            ctx.hisName = "PETE"
            ctx.entryName = "BOB"
        } == "TU BOB")
        #expect(Self.text("{CHNAME}") { ctx in
            ctx.hisName = "PETE"
            ctx.entryName = "BOB"
        } == "PETE")
        #expect(CwMessageBuilder.build("{NAMEANDSPACE}5NN", { var c = Self.ctx(); c.hisName = "PETE"; return c }())
            .parts == [.text("PETE 5NN")])
        #expect(CwMessageBuilder.build("{NAMEANDSPACE}5NN", Self.ctx()).parts == [.text("5NN")])
    }

    @Test func stationAndClusterMacros() {
        #expect(Self.text("{GRID} {CLUSTER}") { $0.clusterCall = "OK1XOE-2" } == "JO70EB OK1XOE-2")
    }

    @Test func frequencyMacrosUseRForTheDecimalPointInCw() {
        #expect(Self.text("{FREQ}") { $0.freqHz = 14_025_340 } == "14025.3")
        #expect(Self.text("{FREQ}") { ctx in
            ctx.freqHz = 14_025_340
            ctx.frequencyR = true
        } == "14025R3")
        #expect(Self.text("{FREQ}") { $0.freqHz = 14_025_000 } == "14025")
        #expect(Self.text("{FREQROUND}") { $0.freqHz = 14_025_600 } == "14026")
        #expect(Self.text("{FREQ}{FREQROUND}") == "")
        #expect(Self.text("{LRMHZ} {RRMHZ}") { ctx in
            ctx.leftMHz = "28"
            ctx.rightMHz = "14"
        } == "28 14")
    }

    @Test func locatorMacros() {
        let sent = Self.text("{GRIDSQUARE} {GRIDBEARING} {REVGRIDBEARING} {KMGRIDDISTANCE}") { $0.hisGrid = "jo60lb" }
        let mine = Maidenhead.centerLatLon("JO70EB")!
        let his = Maidenhead.centerLatLon("JO60LB")!
        let bearing = Int(GreatCircle.bearingDeg(mine.lat, mine.lon, his.lat, his.lon).rounded())
        let km = Int(Maidenhead.distanceKm("JO70EB", "JO60LB").rounded())
        #expect(sent == "JO60LB \(bearing) \((bearing + 180) % 360) \(km)")
        #expect(bearing > 200 && bearing < 300)
        // An invalid or missing locator gives nothing.
        #expect(Self.text("{GRIDBEARING}{KMGRIDDISTANCE}") { $0.hisGrid = "XX" } == "")
    }

    @Test func timeAndDateMacros() {
        #expect(Self.text("{TIME2} {TIME}") == "1736 1736")
        // Characters a keyer cannot send (`:`) are dropped like any other.
        #expect(Self.text("{TIMEGMT}") == "173655")
        #expect(Self.text("{TIME1}") == "193655")
        #expect(Self.text("{DATE1}") == "14.10.26")
        #expect(Self.text("{DAYTIME}") == "2610141936")
        #expect(Self.text("{TIMESTAMP}") == "2026-10-14 1736")
        #expect(Self.text("{DATE}") == "10/14/26")
        #expect(!Self.text("{DATEGMT}").isEmpty)
        #expect(Self.text("{TIME1}{DATE}") { $0.now = nil } == "")
    }

    @Test func actionMacros() {
        let message = CwMessageBuilder.build("{CQ}{QSYCQ}{EXCHSENT}{CTRLHOME}{FORCELOG}{FORCELOGNOTE}{SPACE}", Self.ctx())
        #expect(message.actions == [.cq, .cqFrequency, .exchangeSent, .ctrlHome, .forceLog, .forceLogNote, .space])
        #expect(message.unknownMacros.isEmpty)
    }

    @Test func commentIsAParameterizedCommand() {
        let message = CwMessageBuilder.build("tu {COMMENT Pse QSY 3.5} *", Self.ctx())
        #expect(message.commands == [.comment("Pse QSY 3.5")])
        #expect(message.plainText() == "TU OK1XOE")
        // Without a text it is unknown.
        #expect(CwMessageBuilder.build("{COMMENT}", Self.ctx()).unknownMacros == ["{COMMENT}"])
    }

    // MARK: - VARYMSG

    @Test func varyMessageAlternatesEveryNthSend() {
        let template = "{VARYMSG1 &CQ * *&CQ CQ * *&3&} TEST"
        var sent: [String] = []
        for count in 0..<6 {
            let message = CwMessageBuilder.build(template, { var c = Self.ctx(); c.varyCounts = [count, 0]; return c }())
            sent.append(message.plainText())
            #expect(message.varyUsed == [1])
        }
        #expect(sent == ["CQ OK1XOE OK1XOE TEST", "CQ OK1XOE OK1XOE TEST", "CQ CQ OK1XOE OK1XOE TEST",
                         "CQ OK1XOE OK1XOE TEST", "CQ OK1XOE OK1XOE TEST", "CQ CQ OK1XOE OK1XOE TEST"])
    }

    @Test func varyMessageZeroAndOne() {
        #expect(VaryMessage.expand("{VARYMSG2&a&b&0&}", counts: [0, 5]).text == "a")
        #expect(VaryMessage.expand("{varymsg2&a&b&1&}", counts: [0, 5]).text == "b")
        let both = VaryMessage.expand("x{VARYMSG1&a&b&2&}y{VARYMSG2 &c&d&2& }z", counts: [1, 0])
        #expect(both.text == "xbycz")
        #expect(both.used == [1, 2])
        // Malformed: left alone (reported as an unknown macro by the builder).
        #expect(VaryMessage.expand("{VARYMSG3&a&b&1&}", counts: []).text == "{VARYMSG3&a&b&1&}")
        #expect(VaryMessage.expand("{VARYMSG1&a&b&x&}", counts: []).used.isEmpty)
    }

    @Test func varyMessageMayHoldOtherMacros() {
        var ctx = Self.ctx()
        ctx.varyCounts = [1, 0]
        let message = CwMessageBuilder.build("{VARYMSG1&TU&TU {LOG}&2&}", ctx)
        #expect(message.plainText() == "TU")
        #expect(message.actions == [.log])
    }

    // MARK: - router

    @Test func routerCarriesCommandsAndVaryUseAndTheFrequency() {
        var keys = [FunctionKeyMessage](repeating: FunctionKeyMessage(label: "", text: ""), count: 12)
        keys[0] = FunctionKeyMessage(label: "CQ", text: "{VARYMSG1&CQ&CQ CQ&2&} {FREQ} {COMMENT run}")
        let set = FunctionKeySet(run: keys, sp: keys)
        let context = FunctionKeyContext(
            mode: .cw, digitalReady: false, postContest: false, run: true, call: "", rstSent: "599",
            freqHz: 7_012_500, progress: .empty, stationCall: "OK1XOE", voice: set, cw: set, digital: set,
            cwBase: Self.ctx())
        let out = FunctionKeyRouter.send([0], context: context)
        #expect(out.commands == [.comment("run")])
        #expect(out.varyUsed == [1])
        guard case .cw(let message, _) = out.transmission else {
            Issue.record("no CW transmission")
            return
        }
        #expect(message.plainText() == "CQ 7012R5")
    }
}
