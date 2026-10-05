import Foundation
import Testing
@testable import MCLCore

/// `QsoAssembly` per the source `ui/EntryPanel.kt:468-567` (`logQso`) and `ui/AppState.kt:2722-2733`,
/// `:3822-3823`. Outside the gate — an exhaustive case table.
@Suite struct QsoAssemblyTests {

    private static let at = Date(timeIntervalSince1970: 1_795_867_500)

    private static func cqwwFields() throws -> [ContestDefinition.ExchangeField] {
        EntryFixtures.received(try EntryFixtures.definition(EntryFixtures.cqww))
    }

    private static func serialFields() throws -> [ContestDefinition.ExchangeField] {
        EntryFixtures.received(try EntryFixtures.definition(EntryFixtures.serial))
    }

    private static func form(_ pairs: [(String?, String?)], mode: Mode = .cw) -> EntryForm {
        var form = EntryForm()
        form.call = " ok1abc "
        form.freqKHz = "14025,5"
        form.mode = mode
        form.rstSent = "599"
        form.contestExchange = JavaLinkedMap(pairs)
        return form
    }

    private static func contest(_ form: EntryForm, _ fields: [ContestDefinition.ExchangeField],
                                serial: Int = 42, sentFlat: String? = "599 15", note: String? = nil,
                                at: Date? = nil) -> Qso {
        QsoAssembly.contest(form: form, fields: fields, rstFieldIds: EntryForm.rstFieldIds(fields), serial: serial,
                            runMode: .searchAndPounce, sentFlat: sentFlat, note: note, at: at)
    }

    // MARK: - contest QSO

    @Test func contestQsoCarriesFormAndContestValues() throws {
        let qso = Self.contest(Self.form([("rst", "599"), ("zone", "15")]), try Self.cqwwFields(),
                               note: "note", at: Self.at)
        #expect(qso.call == "OK1ABC")
        #expect(qso.freqHz == 14_025_500)
        #expect(qso.band == .m20)
        #expect(qso.mode == .cw)
        #expect(qso.runMode == .searchAndPounce)
        #expect(qso.exchangeRcvd == "599 15")
        #expect(qso.rstSent == "599")
        #expect(qso.rstRcvd == "599")
        #expect(qso.serialSent == 42)
        #expect(qso.serialRcvd == nil)
        #expect(qso.exchangeSent == "599 15")
        #expect(qso.comment == "note")
        #expect(qso.timestampUtc == Self.at)
        #expect(qso.id == nil)
    }

    @Test func contestExchangeKeepsValuesUntrimmedInFieldOrder() throws {
        let fields = try Self.cqwwFields()
        #expect(Self.contest(Self.form([("zone", " 15 "), ("rst", "599")]), fields).exchangeRcvd == "599  15 ")
        #expect(Self.contest(Self.form([("rst", "599"), ("zone", "")]), fields).exchangeRcvd == "599")
        #expect(Self.contest(Self.form([("rst", "599"), ("zone", "\u{00A0}")]), fields).exchangeRcvd == "599")
        #expect(Self.contest(Self.form([("rst", "  "), ("zone", nil)]), fields).exchangeRcvd == "")
        #expect(Self.contest(Self.form([]), fields).exchangeRcvd == "")
        // Keys outside the active fields are not part of the exchange.
        #expect(Self.contest(Self.form([("rst", "599"), ("extra", "X")]), fields).exchangeRcvd == "599")
    }

    @Test func contestRstRcvdFromFirstRstFieldTrimmed() throws {
        let fields = try Self.cqwwFields()
        #expect(Self.contest(Self.form([("rst", " 57 ")]), fields).rstRcvd == "57")
        #expect(Self.contest(Self.form([("rst", "\u{00A0}57")]), fields).rstRcvd == "57")
        #expect(Self.contest(Self.form([("rst", "   ")]), fields).rstRcvd == "")
        #expect(Self.contest(Self.form([]), fields).rstRcvd == "")
        // The report field is active but missing from the entered exchange (Kotlin `cexch[it.id]` is null).
        #expect(Self.contest(Self.form([("zone", "15")]), fields).rstRcvd == "")
        // No RST field → no received report.
        let noRst = fields.filter { $0.type != .RST }
        #expect(Self.contest(Self.form([("rst", "57")]), noRst).rstRcvd == "")
    }

    @Test func contestRstSentBlankIsNilOtherwiseUntrimmed() throws {
        let fields = try Self.cqwwFields()
        var form = Self.form([("rst", "599")])
        form.rstSent = "  "
        #expect(Self.contest(form, fields).rstSent == "")
        form.rstSent = " 579"
        #expect(Self.contest(form, fields).rstSent == " 579")
    }

    @Test(arguments: [
        ("12", 12), ("+12", 12), ("-3", -3), (" 12 ", 12), ("\u{00A0}7", 7), ("007", 7),
        ("1 2", nil), ("12a", nil), ("", nil), ("+", nil), ("2147483647", 2_147_483_647),
        ("2147483648", nil), ("-2147483648", -2_147_483_648), ("\u{0661}\u{0662}", 12),
    ] as [(String, Int?)])
    func contestSerialRcvdFromNrField(_ nr: String, _ expected: Int?) throws {
        let qso = Self.contest(Self.form([("rst", "599"), ("nr", nr), ("name", "TOM")]), try Self.serialFields())
        #expect(qso.serialRcvd == expected)
    }

    @Test func contestSerialRcvdReadsNrEvenWhenNotAnActiveField() throws {
        let qso = Self.contest(Self.form([("rst", "599"), ("zone", "15"), ("nr", "9")]), try Self.cqwwFields())
        #expect(qso.serialRcvd == 9)
        #expect(qso.exchangeRcvd == "599 15")
    }

    @Test func contestNilNoteAndSentFlatAreEmpty() throws {
        let qso = Self.contest(Self.form([("rst", "599")]), try Self.cqwwFields(), sentFlat: nil, note: nil)
        #expect(qso.comment == "")
        #expect(qso.exchangeSent == "")
        #expect(qso.timestampUtc == nil)
    }

    @Test func badFrequencyGivesZero() throws {
        var form = Self.form([("rst", "599")])
        form.freqKHz = "abc"
        let qso = Self.contest(form, try Self.cqwwFields())
        #expect(qso.freqHz == 0)
        #expect(qso.band == nil)
    }

    // MARK: - county line / rover

    @Test func loggingQthsCountyLineInRoverContest() {
        #expect(QsoAssembly.loggingQths(countyLine: ["DAD", "JEF", "MON"], usesRoverQth: true, roverQth: "ESX")
                == ["DAD", "JEF", "MON"])
        #expect(QsoAssembly.loggingQths(countyLine: ["DAD"], usesRoverQth: true, roverQth: "ESX") == ["DAD"])
    }

    @Test func loggingQthsWithoutCountyLineUsesTrimmedRoverQth() {
        #expect(QsoAssembly.loggingQths(countyLine: [], usesRoverQth: true, roverQth: " ESX ") == ["ESX"])
        #expect(QsoAssembly.loggingQths(countyLine: [], usesRoverQth: true, roverQth: "  ") == [nil])
        #expect(QsoAssembly.loggingQths(countyLine: [], usesRoverQth: true, roverQth: "") == [nil])
    }

    @Test func loggingQthsOutsideRoverContestIgnoresCountyLine() {
        #expect(QsoAssembly.loggingQths(countyLine: ["DAD", "JEF"], usesRoverQth: false, roverQth: "ESX") == [nil])
        #expect(QsoAssembly.loggingQths(countyLine: [], usesRoverQth: false, roverQth: "ESX") == [nil])
    }

    @Test func roverQthForDupe() {
        #expect(QsoAssembly.roverQthForDupe(roverQth: "\u{00A0}ESX ", usesRoverQth: true) == "ESX")
        #expect(QsoAssembly.roverQthForDupe(roverQth: "ESX", usesRoverQth: false) == nil)
        #expect(QsoAssembly.roverQthForDupe(roverQth: " ", usesRoverQth: true) == nil)
    }

    @Test func countyLineGivesOneQsoPerCountyWithSameSerial() throws {
        let definition = try EntryFixtures.definition(EntryFixtures.qsoParty)
        let fields = EntryFixtures.received(definition)
        let form = Self.form([("rst", "599"), ("cnty", "ESX")])
        let copies = QsoAssembly.contestQsos(
            form: form, fields: fields, rstFieldIds: EntryForm.rstFieldIds(fields), serial: 17, runMode: .run,
            countyLine: ["DAD", "JEF", "MON"], usesRoverQth: true, roverQth: "ESX", note: nil, at: Self.at
        ) { qth in
            SentExchange.flat(definition: definition, setup: nil, mode: form.mode, serial: 17, rstSent: form.rstSent,
                              ownQth: qth)
        }
        #expect(copies.map(\.qth) == ["DAD", "JEF", "MON"])
        #expect(copies.map(\.qso.serialSent) == [17, 17, 17])
        #expect(copies.map(\.qso.exchangeSent) == ["599 DAD", "599 JEF", "599 MON"])
        #expect(copies.map(\.qso.exchangeRcvd) == ["599 ESX", "599 ESX", "599 ESX"])
        #expect(copies.allSatisfy { $0.qso.timestampUtc == Self.at && $0.qso.call == "OK1ABC" })
    }

    @Test func singleCountyAndRoverGiveOneQso() throws {
        let definition = try EntryFixtures.definition(EntryFixtures.qsoParty)
        let fields = EntryFixtures.received(definition)
        let form = Self.form([("rst", "599"), ("cnty", "ESX")])
        let sent: (String?) -> String? = { qth in
            SentExchange.flat(definition: definition, setup: nil, mode: form.mode, serial: 3, rstSent: "",
                              ownQth: qth)
        }
        let one = QsoAssembly.contestQsos(form: form, fields: fields, rstFieldIds: ["rst"], serial: 3, runMode: .run,
                                          countyLine: ["DAD"], usesRoverQth: true, roverQth: "", note: nil, at: nil,
                                          sentFlat: sent)
        #expect(one.map(\.qso.exchangeSent) == ["599 DAD"])
        let rover = QsoAssembly.contestQsos(form: form, fields: fields, rstFieldIds: ["rst"], serial: 3,
                                            runMode: .run, countyLine: [], usesRoverQth: true, roverQth: " ESX ",
                                            note: nil, at: nil, sentFlat: sent)
        #expect(rover.map(\.qth) == ["ESX"])
        #expect(rover.map(\.qso.exchangeSent) == ["599 ESX"])
    }

    @Test func roverWithoutRoverContestLogsOneQsoWithoutQth() throws {
        let definition = try EntryFixtures.definition(EntryFixtures.cqww)
        let fields = EntryFixtures.received(definition)
        let form = Self.form([("rst", "599"), ("zone", "15")])
        let copies = QsoAssembly.contestQsos(
            form: form, fields: fields, rstFieldIds: ["rst"], serial: 5, runMode: .run,
            countyLine: ["DAD", "JEF"], usesRoverQth: false, roverQth: "ESX", note: "n", at: nil
        ) { qth in
            SentExchange.flat(definition: definition, setup: EntryFixtures.setup(["zone": "15"]), mode: form.mode,
                              serial: 5, rstSent: form.rstSent, ownQth: qth)
        }
        #expect(copies.count == 1)
        #expect(copies[0].qth == nil)
        #expect(copies[0].qso.exchangeSent == "599 15")
        #expect(copies[0].qso.comment == "n")
    }

    @Test func multiModeContestFollowsFormMode() throws {
        let definition = try EntryFixtures.definition(EntryFixtures.serial)
        let fields = EntryFixtures.received(definition)
        var form = EntryForm()
        form.call = "W1AW"
        form.freqKHz = "7060"
        form.mode = .ssb
        form.applyContestRst(.ssb, rstFieldIds: EntryForm.rstFieldIds(fields))
        form.editContestField("nr", "12")
        form.editContestField("name", "joe")
        let flat = SentExchange.flat(definition: definition, setup: EntryFixtures.setup(["name": "TOM"]), mode: form.mode,
                                     serial: 8, rstSent: form.rstSent, ownQth: nil)
        let ssb = QsoAssembly.contest(form: form, fields: fields, rstFieldIds: EntryForm.rstFieldIds(fields), serial: 8,
                                      runMode: .run, sentFlat: flat, note: nil, at: nil)
        #expect(ssb.mode == .ssb)
        #expect(ssb.band == .m40)
        #expect(ssb.rstSent == "59")
        #expect(ssb.rstRcvd == "59")
        #expect(ssb.exchangeRcvd == "59 12 JOE")
        #expect(ssb.serialRcvd == 12)
        #expect(ssb.exchangeSent == "59 8 TOM -")

        form.mode = .cw
        form.applyContestRst(.cw, rstFieldIds: EntryForm.rstFieldIds(fields))
        let cwFlat = SentExchange.flat(definition: definition, setup: EntryFixtures.setup(["name": "TOM"]),
                                       mode: form.mode, serial: 8, rstSent: form.rstSent, ownQth: nil)
        let cw = QsoAssembly.contest(form: form, fields: fields, rstFieldIds: EntryForm.rstFieldIds(fields), serial: 8,
                                     runMode: .run, sentFlat: cwFlat, note: nil, at: nil)
        #expect(cw.exchangeRcvd == "599 12 JOE")
        #expect(cw.exchangeSent == "599 8 TOM -")
    }

    // MARK: - free QSO (EntryPanel.kt:551-563)

    @Test func freeQsoTakesGenericFields() {
        var form = EntryForm()
        form.call = "dl1abc"
        form.freqKHz = "3500"
        form.mode = .cw
        form.rstSent = "579"
        form.rstRcvd = " 559"
        form.exch = " 12 "
        let qso = QsoAssembly.free(form: form, serial: 9, runMode: .run, note: "pending", at: Self.at)
        #expect(qso.call == "DL1ABC")
        #expect(qso.freqHz == 3_500_000)
        #expect(qso.band == .m80)
        #expect(qso.rstSent == "579")
        #expect(qso.rstRcvd == " 559")
        #expect(qso.exchangeRcvd == " 12 ")
        #expect(qso.serialSent == 9)
        #expect(qso.serialRcvd == 12)
        #expect(qso.exchangeSent == "")
        #expect(qso.comment == "pending")
        #expect(qso.timestampUtc == Self.at)
        #expect(qso.runMode == .run)
    }

    @Test(arguments: [
        ("", nil), ("  ", nil), ("+5", 5), ("ABC", nil), ("1 2", nil), ("\u{00A0}33\u{00A0}", 33),
        ("-0", 0), ("99999999999", nil),
    ] as [(String, Int?)])
    func freeSerialRcvdFromExch(_ exch: String, _ expected: Int?) {
        var form = EntryForm()
        form.call = "W1AW"
        form.exch = exch
        #expect(QsoAssembly.free(form: form, serial: 1, runMode: .run, note: nil, at: nil).serialRcvd == expected)
    }

    @Test func freeBlankFieldsAreEmpty() {
        var form = EntryForm()
        form.call = "W1AW"
        form.rstSent = " "
        form.rstRcvd = "\u{2003}"
        form.exch = "\t"
        let qso = QsoAssembly.free(form: form, serial: 1, runMode: .searchAndPounce, note: nil, at: nil)
        #expect(qso.rstSent == "")
        #expect(qso.rstRcvd == "")
        #expect(qso.exchangeRcvd == "")
        #expect(qso.comment == "")
        #expect(qso.freqHz == 0)
    }

    // MARK: - operating rules (EntryPanel.kt:495-506, AppState.kt:2722-2733)

    @Test func operatingGateSkipsWhenForcedPostContestOrOff() {
        #expect(QsoAssembly.operatingGate(force: true, postContest: false, enforcement: .block) { "v" } == .proceed)
        #expect(QsoAssembly.operatingGate(force: false, postContest: true, enforcement: .block) { "v" } == .proceed)
        var called = false
        let off = QsoAssembly.operatingGate(force: false, postContest: false, enforcement: .off) {
            called = true
            return "v"
        }
        #expect(off == .proceed)
        #expect(!called)
    }

    @Test func operatingGateWarnsOrBlocks() {
        #expect(QsoAssembly.operatingGate(force: false, postContest: false, enforcement: .warn) { nil } == .proceed)
        #expect(QsoAssembly.operatingGate(force: false, postContest: false, enforcement: .warn) { "v" } == .warn("v"))
        #expect(QsoAssembly.operatingGate(force: false, postContest: false, enforcement: .block) { "v" } == .block("v"))
    }

    @Test func operatingStationTypeIsNoneOffNetwork() {
        #expect(QsoAssembly.operatingStationType(networked: false, configured: .mult) == OperatingGuard.StationType.none)
        #expect(QsoAssembly.operatingStationType(networked: true, configured: .mult) == .mult)
        #expect(QsoAssembly.operatingStationType(networked: true, configured: .run) == .run)
    }
}
