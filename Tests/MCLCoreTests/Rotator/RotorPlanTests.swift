import Foundation
import Testing
@testable import MCLCore

/// The rotor setup (N1MM Rotor program: named rotors, calibration, limits, presets, network rotors), the antenna
/// table's rotor columns (offset, bidirectional, stacks) and the heading typed in the call field.
@Suite struct RotorPlanTests {

    // MARK: - typed heading and grids

    @Test func aNumberInTheCallFieldIsAHeading() {
        #expect(RotorPlan.typedHeading("270") == 270)
        #expect(RotorPlan.typedHeading(" 45 ") == 45)
        #expect(RotorPlan.typedHeading("0") == 0)
        #expect(RotorPlan.typedHeading("360") == 360)
        #expect(RotorPlan.typedHeading("361") == nil)
        #expect(RotorPlan.typedHeading("1234") == nil)
        #expect(RotorPlan.typedHeading("OK1XOE") == nil)
        #expect(RotorPlan.typedHeading("9A1") == nil)
        #expect(RotorPlan.typedHeading("") == nil)
        #expect(RotorPlan.typedHeading("٤٥") == nil)
    }

    @Test func theBearingBetweenGrids() {
        // JO70 → JN79: south; JO70 → IO91 (London): west.
        let southEast: Int = try! #require(RotorPlan.gridBearing(from: "JO70", to: "JN79"))
        #expect((175...185).contains(southEast))
        let west: Int = try! #require(RotorPlan.gridBearing(from: "JO70FB", to: "IO91WM"))
        #expect((270...290).contains(west))
        #expect(RotorPlan.gridBearing(from: "JO70", to: "JO70") == nil)
        #expect(RotorPlan.gridBearing(from: "JO70", to: "599") == nil)
        #expect(RotorPlan.gridBearing(from: "", to: "JN79") == nil)
        #expect(RotorPlan.gridBearing(from: "JO70", to: nil) == nil)
    }

    // MARK: - offset and bidirectional

    @Test func theOffsetIsTakenOff() {
        #expect(RotorPlan.rotorHeading(bearing: 90, offset: 0, bidirectional: false, current: nil) == 90)
        #expect(RotorPlan.rotorHeading(bearing: 90, offset: 30, bidirectional: false, current: nil) == 60)
        #expect(RotorPlan.rotorHeading(bearing: 10, offset: 30, bidirectional: false, current: nil) == 340)
        #expect(RotorPlan.rotorHeading(bearing: 350, offset: -20, bidirectional: false, current: 0) == 10)
    }

    @Test func aBidirectionalAntennaUsesTheNearerEnd() {
        // Pointing at 20°, a bearing of 200° is the back end: no turn.
        #expect(RotorPlan.rotorHeading(bearing: 200, offset: 0, bidirectional: true, current: 20) == 20)
        // At 100°, a bearing of 300° → 120° (20° away) rather than 300° (160° away).
        #expect(RotorPlan.rotorHeading(bearing: 300, offset: 0, bidirectional: true, current: 100) == 120)
        // At 100°, a bearing of 150° stays the front.
        #expect(RotorPlan.rotorHeading(bearing: 150, offset: 0, bidirectional: true, current: 100) == 150)
        // Unknown position: the front.
        #expect(RotorPlan.rotorHeading(bearing: 300, offset: 0, bidirectional: true, current: nil) == 300)
        // Not bidirectional: always the front.
        #expect(RotorPlan.rotorHeading(bearing: 200, offset: 0, bidirectional: false, current: 20) == 200)
    }

    // MARK: - calibration and limits

    @Test func withoutLimitsTheCommandIsTheNormalisedHeading() {
        let rotor = RotorEntry(name: "R")
        #expect(RotorPlan.command(heading: 330, rotor: rotor, currentRaw: 10) == (330, false))
        #expect(RotorPlan.command(heading: 0, rotor: rotor, currentRaw: 350) == (0, false))
        let calibrated = RotorEntry(name: "R", calibration: 5)
        #expect(RotorPlan.command(heading: 2, rotor: calibrated, currentRaw: nil) == (357, false))
        #expect(RotorPlan.reported(raw: 357, calibration: 5) == 2)
        #expect(RotorPlan.reported(raw: 200.5, calibration: 0) == 200.5)
    }

    @Test func anOverlapRotorTakesTheNearerTurn() {
        let rotor = RotorEntry(name: "R", minAzimuth: 0, maxAzimuth: 450)
        // At 400° (= 40° in the overlap), 60° is reached at 420°.
        #expect(RotorPlan.command(heading: 60, rotor: rotor, currentRaw: 400) == (420, false))
        #expect(RotorPlan.command(heading: 60, rotor: rotor, currentRaw: 10) == (60, false))
        #expect(RotorPlan.command(heading: 200, rotor: rotor, currentRaw: 400) == (200, false))
        #expect(RotorPlan.command(heading: 60, rotor: rotor, currentRaw: nil) == (60, false))
    }

    @Test func aSouthStopRotorGetsNegativeCommands() {
        let rotor = RotorEntry(name: "R", minAzimuth: -180, maxAzimuth: 180)
        #expect(RotorPlan.command(heading: 270, rotor: rotor, currentRaw: nil) == (-90, false))
        #expect(RotorPlan.command(heading: 90, rotor: rotor, currentRaw: nil) == (90, false))
    }

    @Test func aLimitedRotorGoesToTheNearerLimit() {
        let rotor = RotorEntry(name: "R", minAzimuth: 30, maxAzimuth: 300)
        #expect(RotorPlan.command(heading: 10, rotor: rotor, currentRaw: nil) == (30, true))
        #expect(RotorPlan.command(heading: 320, rotor: rotor, currentRaw: nil) == (300, true))
        #expect(RotorPlan.command(heading: 200, rotor: rotor, currentRaw: nil) == (200, false))
    }

    // MARK: - setup

    @Test func theSetupKeepsOnlyWhatDiffers() {
        var setup = RotorSetup()
        #expect(setup.values.isEmpty)
        #expect(setup.networkPort == 13_010)
        #expect(!setup.networkEnabled && !setup.autoAntenna)
        #expect(setup.presets == Array(repeating: nil, count: 10))
        setup.rotors = [RotorEntry(name: "Tribander", host: "127.0.0.1", port: 4600, calibration: -3, minAzimuth: 0,
                                   maxAzimuth: 450),
                        RotorEntry(name: "  "), RotorEntry(name: "40m")]
        setup.presets = [0, 45, nil, 400, 360]
        setup.networkEnabled = true
        setup.networkPort = 13_010
        setup.autoAntenna = true
        let back = RotorSetup(setup.values)
        #expect(back == setup)
        #expect(back.rotors == [RotorEntry(name: "Tribander", host: "127.0.0.1", port: 4600, calibration: -3,
                                           minAzimuth: 0, maxAzimuth: 450),
                                RotorEntry(name: "40m")])
        #expect(back.presets == [0, 45, nil, nil, 360, nil, nil, nil, nil, nil])
        #expect(back.values["networkPort"] == nil)
        #expect(back.networkEnabled && back.autoAntenna)
        setup.networkEnabled = false
        setup.autoAntenna = false
        #expect(setup.values["networkEnabled"] == nil && setup.values["autoAntenna"] == nil)
        // Unknown keys and bad values are dropped.
        let odd = RotorSetup(["x": "1", "preset11": "5", "rotor17": "R", "networkPort": "70000",
                              "networkEnabled": "yes", "rotor1": "R\tH\tbad\tx\t300\t100"])
        #expect(odd.values.keys.sorted() == ["rotor1"])
        #expect(odd.rotors == [RotorEntry(name: "R", host: "H")])
    }

    @Test func theSetupSheetDraft() {
        var setup = RotorSetup()
        setup.autoAntenna = true
        var draft = RotorSetupDraft(setup)
        draft.addRotor()
        draft.rotors[0].name = " Stack "
        draft.rotors[0].host = "127.0.0.1"
        draft.rotors[0].calibration = "4"
        draft.addRotor()
        draft.rotors[1].name = "stack"
        draft.addRotor()
        draft.presets[0] = "90"
        draft.presets[1] = "abc"
        draft.networkEnabled = true
        draft.networkPort = "13100"
        let out: RotorSetup = draft.applied()
        #expect(out.rotors == [RotorEntry(name: "Stack", host: "127.0.0.1", calibration: 4)])
        #expect(out.presets.prefix(2) == [90, nil])
        #expect(out.networkEnabled && out.networkPort == 13_100 && out.autoAntenna)
        #expect(RotorSetupDraft(out).applied() == out)
    }

    // MARK: - the antenna table

    @Test func theAntennaRotorColumnsAreWrittenOnlyWhenSet() throws {
        let plain = AntennaEntry(code: 1, name: "Yagi", bands: "20m", sector: "")
        let plainJson = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!plainJson.contains("rotors") && !plainJson.contains("offset") && !plainJson.contains("bidirectional"))
        let full = AntennaEntry(code: 2, name: "Stack", bands: "20m", sector: "", rotors: "Top, Bottom", offset: -15,
                                bidirectional: true)
        let data: Data = try JSONEncoder().encode(full)
        #expect(try JSONDecoder().decode(AntennaEntry.self, from: data) == full)
        #expect(full.rotorNames == ["Top", "Bottom"])
        let old = try JSONDecoder().decode(AntennaEntry.self,
                                           from: Data(#"{"code":3,"name":"A","bands":"40m","sector":"0-90"}"#.utf8))
        #expect(old == AntennaEntry(code: 3, name: "A", bands: "40m", sector: "0-90"))
        #expect(old.rotorNames.isEmpty)
    }

    @Test func theAntennaDraftCarriesTheRotorColumns() {
        var draft = AntennaDraft(AntennaEntry(code: 1, name: "Yagi", bands: "20m", sector: ""))
        #expect(draft.offset.isEmpty && draft.rotors.isEmpty && !draft.bidirectional)
        draft.rotors = " Top ,, Bottom "
        draft.offset = " -20 "
        draft.bidirectional = true
        #expect(draft.toEntry() == AntennaEntry(code: 1, name: "Yagi", bands: "20m", sector: "", rotors: "Top, Bottom",
                                                offset: -20, bidirectional: true))
        draft.offset = "400"
        #expect(draft.toEntry().offset == 0)
    }

    @Test func aBidirectionalAntennaCoversItsBackSector() {
        let fixed = AntennaEntry(code: 1, name: "Fixed EU/W", bands: "20m", sector: "30-90", bidirectional: true)
        let other = AntennaEntry(code: 2, name: "Vertical", bands: "20m", sector: "")
        #expect(AntennaSelector.select([other, fixed], band: .m20, azimuth: 60) == 1)
        #expect(AntennaSelector.select([other, fixed], band: .m20, azimuth: 240) == 1)
        #expect(AntennaSelector.select([other, fixed], band: .m20, azimuth: 150) == 0)
        var oneWay = fixed
        oneWay.bidirectional = false
        #expect(AntennaSelector.select([other, oneWay], band: .m20, azimuth: 240) == 0)
    }

    @Test func theUdpMessageCarriesTheAntennaColumns() {
        #expect(N1mmRotorUdp.turnMessage(rotor: "Stack", azimuth: 90, bandMhz: 14, offset: -15, bidirectional: true)
            == "<N1MMRotor><rotor>Stack</rotor><goazi>90.0</goazi><offset>-15</offset><bidirectional>1</bidirectional>"
            + "<freqband>14</freqband></N1MMRotor>")
    }

    // MARK: - network rotors

    @Test func theNetworkBroadcastIsParsed() {
        #expect(RotorNetwork.parse("Tribander @ 2250")! == ("Tribander", 225.0))
        #expect(RotorNetwork.parse("40m Yagi @ 3605\r\n")! == ("40m Yagi", 0.5))
        #expect(RotorNetwork.parse("A @ B @ 900")! == ("A @ B", 90.0))
        #expect(RotorNetwork.parse("Tribander 2250") == nil)
        #expect(RotorNetwork.parse(" @ 2250") == nil)
        #expect(RotorNetwork.parse("R @ x") == nil)
        #expect(RotorNetwork.parse("<N1MMRotor><stop>R</stop></N1MMRotor>") == nil)
    }

    @Test(.ioSafetyNet) func theListenerReceivesOnLoopback() async throws {
        let received = Inbox<String>()
        let listener = try RotorNetworkListener(bindHost: "127.0.0.1", port: 0) { name, heading in
            received.offer(name + "=" + String(heading))
        }
        defer { listener.close() }
        listener.start()
        let tx = UdpTestSocket()
        tx.send(Array("noise".utf8), toPort: listener.boundPort)
        tx.send(Array("Stack @ 1355".utf8), toPort: listener.boundPort)
        #expect(await onOwnThread { received.take() } == "Stack=135.5")
        #expect(received.count == 0)
    }
}
