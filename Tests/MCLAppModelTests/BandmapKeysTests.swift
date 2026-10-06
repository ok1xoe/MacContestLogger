import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The spot keys of the Bandmap window (`BandmapModel.handleKey`): Mark and Remove spot by the user's bindings, the
/// spot under the mouse as the target of Remove. Fake rig and network only.
@MainActor @Suite struct BandmapKeysTests {

    static let height: Float = 600
    static let rowH: Float = 14
    static let axisX: Float = 60
    static let option: UInt = AwtKeyCodes.macOptionFlag

    static func spot(_ call: String, _ freqHz: Int) -> DxSpot {
        DxSpot(spotter: "OK1RR", freqHz: freqHz, dxCall: call, comment: "")
    }

    /// `characters` is what the layout types: Option+letter types a symbol on the US layout, nothing on the Czech one.
    static func key(_ code: UInt16, _ letter: String, flags: UInt = option, characters: String = "",
                    kind: MacKeyEvent.Kind = .keyDown) -> MacKeyEvent {
        MacKeyEvent(kind: kind, keyCode: code, characters: characters, charactersIgnoringModifiers: letter,
                    modifierFlags: flags)
    }

    static let altM: UInt16 = 0x2E
    static let altD: UInt16 = 0x02

    /// 20 m with two spots; the mouse over the one on 14.100.
    func setUp(hover: Bool = true) async throws -> (SpotApp, BandmapModel, SpotBuffer) {
        let spot = try await SpotApp.make()
        let bandmap: BandmapModel = spot.model.bandmap
        spot.model.rig.qsy(14_025_000)
        let buffer: SpotBuffer = spot.model.dxCluster.spots
        buffer.add(Self.spot("DL1ABC", 14_100_000))
        buffer.add(Self.spot("W1AW", 14_200_000))
        if hover {
            let y: Float = bandmap.viewport.yAt(14_100_000, height: Self.height)
            bandmap.pointerMoved(x: 200, y: y, height: Self.height, axisX: Self.axisX, rowH: Self.rowH)
        }
        return (spot, bandmap, buffer)
    }

    @Test func altMMarksTheEntryFrequencyOnTheCzechLayoutToo() async throws {
        let (spot, bandmap, buffer) = try await setUp()
        spot.model.entry.setFrequency("14031.56")
        #expect(bandmap.handleKey(Self.key(Self.altM, "m")))
        #expect(buffer.snapshot().contains(DxSpot(spotter: "MARK", freqHz: 14_031_560, dxCall: "*14031.6",
                                                  comment: "obsazeno", selfSpotted: true)))
        #expect(spot.model.status.message == "Frekvence 14031.6 kHz označena v bandmapě")
        // The release is consumed without a second mark; a US-layout event (a symbol typed) works the same.
        #expect(bandmap.handleKey(Self.key(Self.altM, "m", kind: .keyUp)))
        #expect(bandmap.handleKey(Self.key(Self.altM, "m", characters: "µ")))
        #expect(buffer.snapshot().count == 3)
    }

    @Test func altDRemovesTheSpotUnderTheMouse() async throws {
        let (spot, bandmap, buffer) = try await setUp()
        spot.model.entry.callChanged("W1AW")
        #expect(bandmap.hoveredSpot?.dxCall == "DL1ABC")
        #expect(bandmap.handleKey(Self.key(Self.altD, "d")))
        #expect(buffer.snapshot().map(\.dxCall) == ["W1AW"])
        #expect(spot.model.status.message == "Spot DL1ABC odstraněn")
        #expect(bandmap.handleKey(Self.key(Self.altD, "d", kind: .keyUp)))
        #expect(buffer.snapshot().map(\.dxCall) == ["W1AW"])
    }

    @Test func altDWithoutAHoveredSpotActsAsTheEntry() async throws {
        let (spot, bandmap, buffer) = try await setUp(hover: false)
        spot.model.entry.callChanged("w1aw")
        #expect(bandmap.hoveredSpot == nil)
        #expect(bandmap.handleKey(Self.key(Self.altD, "d")))
        #expect(buffer.snapshot().map(\.dxCall) == ["DL1ABC"])
        // The mouse on the empty map or left of the axis is no spot either.
        bandmap.pointerMoved(x: 20, y: 10, height: Self.height, axisX: Self.axisX, rowH: Self.rowH)
        #expect(bandmap.hoveredSpot == nil)
        bandmap.pointerLeft()
        #expect(bandmap.hoveredSpot == nil)
    }

    @Test func altShiftDBlacklistsTheSpotUnderTheMouse() async throws {
        let (spot, bandmap, buffer) = try await setUp()
        let flags: UInt = Self.option | AwtKeyCodes.macShiftFlag
        #expect(bandmap.handleKey(Self.key(Self.altD, "D", flags: flags)))
        #expect(buffer.snapshot().map(\.dxCall) == ["W1AW"])
        #expect(spot.model.config.config.dxCluster.callBlacklist.map(\.value) == ["DL1ABC"])
        #expect(spot.model.status.message == "Spot DL1ABC odstraněn a dán na blacklist")
    }

    @Test func aRemappedBindingApplies() async throws {
        let (spot, bandmap, buffer) = try await setUp()
        spot.model.config.config.keyBindings = ["remove_spot": "Ctrl+Alt+X", "mark": ""]
        // The old keys are free now.
        #expect(!bandmap.handleKey(Self.key(Self.altD, "d")))
        #expect(!bandmap.handleKey(Self.key(Self.altM, "m")))
        #expect(buffer.snapshot().count == 2)
        let flags: UInt = Self.option | AwtKeyCodes.macControlFlag
        #expect(bandmap.handleKey(Self.key(0x07, "x", flags: flags)))
        #expect(buffer.snapshot().map(\.dxCall) == ["W1AW"])
    }

    @Test func otherKeysAreNotConsumed() async throws {
        let (_, bandmap, buffer) = try await setUp()
        #expect(!bandmap.handleKey(Self.key(0x7E, "", flags: 0, characters: "\u{F700}")))
        #expect(!bandmap.handleKey(Self.key(Self.altD, "d", flags: 0, characters: "d")))
        #expect(!bandmap.handleKey(Self.key(0x2D, "n")))
        #expect(!bandmap.handleKey(MacKeyEvent(kind: .flagsChanged, keyCode: 0x3A, modifierFlags: Self.option)))
        #expect(buffer.snapshot().count == 2)
    }
}
