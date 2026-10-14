import Foundation
import Testing
@testable import MCLCore

/// The full N1MM packets (Swift-only): `contactinfo` with the whole tag list, `RadioInfo` with the second radio,
/// split and transmit state, `dynamicresults` with the class, QTH and breakdown — and the v1.1.1 packets unchanged
/// without extras.
@Suite(.ioSafetyNet) struct BroadcastFullPacketTests {

    private static func contact(extras: BroadcastXml.ContactExtras?) -> BroadcastXml.ContactData {
        var c = BroadcastXml.ContactData(
            contestName: "CQ-WW-CW", contestNr: 7, timestamp: Date(timeIntervalSince1970: 1_790_000_000),
            myCall: "OK1XOE", rxFreqHz: 14_025_000, txFreqHz: 14_025_000, mode: "CW", call: "W1AW", continent: "NA",
            snt: "599", sntNr: nil, rcv: "599", rcvNr: nil, points: 3, isMultiplier: true, id: "abc",
            stationName: "OK1XOE")
        c.extras = extras
        return c
    }

    @Test func withoutExtrasThePacketIsTheOldOne() {
        let old = BroadcastXml.contactInfo(Self.contact(extras: nil))
        #expect(!old.contains("<gridsquare>"))
        #expect(old.contains("<countryprefix></countryprefix>"))
        let r = BroadcastXml.RadioData(stationName: "s", freqHz: 7_000_000, mode: "CW", opCall: "o", isRunning: false)
        #expect(!BroadcastXml.radioInfo(r).contains("<RadioName>"))
        let s = BroadcastXml.ScoreData(contest: "c", call: "x", ops: "o", score: 1, timestamp: nil)
        #expect(!BroadcastXml.dynamicResults(s).contains("<breakdown>"))
    }

    @Test func fullContactCarriesN1mmFieldsInOrder() throws {
        var x = BroadcastXml.ContactExtras()
        x.countryPrefix = "K"
        x.wpxPrefix = "W1"
        x.gridSquare = "FN31"
        x.zone = "5"
        x.section = "CT"
        x.name = "HIRAM"
        x.power = "100"
        x.exchange1 = "5"
        x.operator = "OK1XOE"
        x.isRunQso = true
        x.radioNr = 2
        x.sentExchange = "15"
        let xml = BroadcastXml.contactInfo(Self.contact(extras: x))
        for tag in ["<countryprefix>K</countryprefix>", "<wpxprefix>W1</wpxprefix>", "<gridsquare>FN31</gridsquare>",
                    "<zone>5</zone>", "<section>CT</section>", "<name>HIRAM</name>", "<power>100</power>",
                    "<exchange1>5</exchange1>", "<operator>OK1XOE</operator>", "<IsRunQSO>1</IsRunQSO>",
                    "<radionr>2</radionr>", "<run1run2>2</run1run2>", "<SentExchange>15</SentExchange>",
                    "<IsOriginal>True</IsOriginal>", "<ismultiplier1>1</ismultiplier1>"] {
            #expect(xml.contains(tag), "\(tag)")
        }
        // N1MM's order: operator before mode, SentExchange last.
        let op = try #require(xml.range(of: "<operator>"))
        let mode = try #require(xml.range(of: "<mode>"))
        #expect(op.lowerBound < mode.lowerBound)
        #expect(xml.hasSuffix("<SentExchange>15</SentExchange></contactinfo>"))

        let replace = BroadcastXml.contactReplace(Self.contact(extras: x), oldCall: "W1AX", oldTs: nil)
        #expect(replace.hasPrefix("<contactreplace>"))
        #expect(replace.contains("<oldcall>W1AX</oldcall>"))
        x.isOriginal = false
        #expect(BroadcastXml.contactInfo(Self.contact(extras: x)).contains("<IsOriginal>False</IsOriginal>"))
    }

    @Test func lookupInfoUsesTheContactTagList() {
        let xml = BroadcastXml.lookupInfo(Self.contact(extras: nil))
        #expect(xml.hasPrefix("<lookupinfo><app>MacContestLogger</app>"))
        #expect(xml.contains("<call>W1AW</call>"))
        #expect(xml.hasSuffix("</lookupinfo>"))
    }

    @Test func fullRadioInfoHasSplitTransmitAndRadioNumber() {
        var r = BroadcastXml.RadioData(stationName: "OK1XOE", freqHz: 14_025_000, mode: "CW", opCall: "OK1XOE",
                                       isRunning: true)
        r.auxAntennaCode = 3
        r.auxAntennaName = "Beam"
        let rig = RigState(freqHz: 14_025_000, mode: .cw, rawMode: "CW", passband: 500, split: true,
                           txFreqHz: 14_026_000)
        r.extras = BroadcastMapping.radioExtras(radioNr: 2, rig: rig, stationCall: "OK1XOE", antenna: 4,
                                                focusRadioNr: 1, activeRadioNr: 1, isStereo: true,
                                                isTransmitting: true, radioName: "Yaesu FT-991")
        let xml = BroadcastXml.radioInfo(r)
        for tag in ["<RadioNr>2</RadioNr>", "<Freq>1402500</Freq>", "<TXFreq>1402600</TXFreq>",
                    "<mycall>OK1XOE</mycall>", "<Antenna>4</Antenna>", "<FocusRadioNr>1</FocusRadioNr>",
                    "<IsStereo>True</IsStereo>", "<IsSplit>True</IsSplit>", "<ActiveRadioNr>1</ActiveRadioNr>",
                    "<IsTransmitting>True</IsTransmitting>", "<RadioName>Yaesu FT-991</RadioName>",
                    "<AuxAntSelected>3</AuxAntSelected>", "<AuxAntSelectedName>Beam</AuxAntSelectedName>",
                    "<IsConnected>True</IsConnected>", "<FunctionKeyCaption></FunctionKeyCaption>"] {
            #expect(xml.contains(tag), "\(tag)")
        }
        let simplex = RigState(freqHz: 7_000_000, mode: .cw, rawMode: "CW", passband: 500)
        let x = BroadcastMapping.radioExtras(radioNr: 1, rig: simplex, stationCall: "", antenna: nil, focusRadioNr: 1,
                                             activeRadioNr: 1, isStereo: false, isTransmitting: false, radioName: "")
        #expect(x.txFreqHz == 7_000_000)
        #expect(x.antenna == -1)
        #expect(!x.isSplit)
        #expect(BroadcastMapping.radioName(modelLabel: "1035 — Yaesu FT-991") == "Yaesu FT-991")
        #expect(BroadcastMapping.radioName(modelLabel: "Dummy") == "Dummy")
    }

    @Test func fullDynamicResultsHasClassQthAndBreakdown() {
        var s = BroadcastXml.ScoreData(contest: "CQ-WW-CW", call: "OK1XOE", ops: "OK1XOE", score: 42,
                                       timestamp: Date(timeIntervalSince1970: 0))
        var x = BroadcastXml.ScoreExtras()
        x.category = ["POWER": "LOW", "OPERATOR": "SINGLE-OP"]
        x.club = "OK DX"
        x.cqZone = "15"
        x.grid = "JO70"
        x.breakdown = [.init(kind: "qso", band: "20", mode: "CW", value: 2),
                       .init(kind: "qso", band: "total", mode: "ALL", value: 2)]
        s.extras = x
        let xml = BroadcastXml.dynamicResults(s)
        #expect(xml.contains("<class power=\"LOW\" assisted=\"\" transmitter=\"\" ops=\"SINGLE-OP\""))
        #expect(xml.contains("<club>OK DX</club>"))
        #expect(xml.contains("<qth><dxcccountry></dxcccountry><cqzone>15</cqzone>"))
        #expect(xml.contains("<grid6>JO70</grid6></qth>"))
        #expect(xml.contains("<breakdown><qso band=\"20\" mode=\"CW\">2</qso><qso band=\"total\" mode=\"ALL\">2</qso></breakdown>"))
        #expect(xml.hasSuffix("<score>42</score><timestamp>1970-01-01 00:00:00</timestamp></dynamicresults>"))
    }

    private static func qso(_ call: String, _ band: Band, _ mode: Mode, points: Int, exchange: String = "") -> Qso {
        var q = Qso()
        q.call = call
        q.band = band
        q.mode = mode
        q.points = points
        q.exchangeRcvd = exchange
        return q
    }

    @Test func breakdownCountsPerBandAndModeThenTotals() {
        var deleted = Self.qso("X", .m20, .cw, points: 9)
        deleted.deleted = true
        let qsos = [Self.qso("A", .m20, .cw, points: 3), Self.qso("B", .m40, .ssb, points: 1),
                    Self.qso("C", .m20, .cw, points: 2), Self.qso("D", .m20, .ft8, points: 1), deleted]
        let score = ScoreState(qsoCount: 4, qsoPoints: 7, multTotal: 3, multByGroup: JavaLinkedMap<Int32>(),
                               bonusPoints: 0, qtcPoints: 0, total: 21)
        let rows = BroadcastMapping.scoreBreakdown(qsos, score: score)
        let text = rows.map { "\($0.kind) \($0.band) \($0.mode) \($0.value)" }
        #expect(text == ["qso 40 PH 1", "point 40 PH 1", "qso 20 CW 2", "point 20 CW 5", "qso 20 DIG 1",
                         "point 20 DIG 1", "qso total ALL 4", "point total ALL 7", "mult total ALL 3"])
    }

    @Test func contactExtrasSplitTheExchangeByMeaning() {
        func field(_ id: String, _ type: ContestDefinition.FieldType) -> ContestDefinition.ExchangeField {
            ContestDefinition.ExchangeField(id: id, type: type, required: true, source: .MANUAL, appliesWhen: nil,
                                            validation: nil)
        }
        var q = Self.qso("OK1ABC", .m20, .cw, points: 1, exchange: "15 JO70 PRAHA - 100")
        q.operator = "OK1XOE"
        q.runMode = .searchAndPounce
        q.exchangeSent = " 15 "
        let fields = [field("zone", .INTEGER), field("loc", .LOCATOR), field("qth", .DISTRICT),
                      field("name", .TEXT), field("pwr", .TEXT)]
        let x = BroadcastMapping.contactExtras(q, receivedFields: fields, countryPrefix: "OK", radioNr: 0)
        #expect(x.zone == "15")
        #expect(x.gridSquare == "JO70")
        #expect(x.qth == "PRAHA")
        #expect(x.name == "")
        #expect(x.power == "100")
        #expect(x.wpxPrefix == "OK1")
        #expect(x.countryPrefix == "OK")
        #expect(x.exchange1 == "15 JO70 PRAHA - 100")
        #expect(x.sentExchange == "15")
        #expect(!x.isRunQso)
        #expect(x.radioNr == 1)
        #expect(x.operator == "OK1XOE")
    }

    /// SO2R: the second radio's packet has its own change key, so a change on one radio never hides the other.
    @Test func secondRadioIsSentWithItsOwnKey() {
        var cfg = BroadcastConfig()
        cfg.radioEnabled = true
        cfg.radioTargets = "127.0.0.1:12060"
        let fake = BroadcastServiceTests.FakeBroadcaster()
        @Sendable func radio(_ hz: Int64, nr: Int) -> BroadcastXml.RadioData {
            var r = BroadcastXml.RadioData(stationName: "s", freqHz: hz, mode: "CW", opCall: "o", isRunning: false)
            var x = BroadcastXml.RadioExtras()
            x.radioNr = nr
            r.extras = x
            return r
        }
        let rig2 = OSBox(radio(7_000_000, nr: 2))
        let rig1: BroadcastXml.RadioData = radio(14_000_000, nr: 1)
        let s = BroadcastService(config: cfg, broadcaster: fake, radioProvider: { rig1 },
                                 scoreProvider: { nil },
                                 appInfoProvider: { BroadcastXml.AppInfoData(dbName: nil, contestNr: 0, contestName: nil,
                                                                             stationName: nil, myCall: nil) },
                                 radio2Provider: { rig2.value })
        s.radioStep(ticks: 0)
        #expect(fake.sent.count == 2)
        #expect(fake.sent[1].0.contains("<RadioNr>2</RadioNr>"))
        s.radioStep(ticks: 1)
        #expect(fake.sent.count == 2)
        rig2.value = radio(7_001_000, nr: 2)
        s.radioStep(ticks: 2)
        #expect(fake.sent.count == 3)
        #expect(fake.sent[2].0.contains("<Freq>700100</Freq>"))
    }
}

/// A value the test changes while a provider reads it.
private final class OSBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) {
        stored = value
    }

    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
