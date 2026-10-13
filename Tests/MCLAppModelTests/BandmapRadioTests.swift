import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The band map's radio and navigation (N1MM): the header's radio and TX frequency, the red TX arrow (a click turns
/// split off), the receiver's filter, the lowest frequency at the bottom, the disabled wheel, the zoom keys and
/// „Go to Bottom/Top Of Band". Rigs are `FakeRigctld` on loopback; nothing transmits.
@MainActor @Suite struct BandmapRadioTests {

    static let height: Float = 600
    static let rowH: Float = 14
    static let axisX: Float = 60

    @Test func theHeaderTheTxArrowAndTheFilterFollowTheRig() async throws {
        let fake = try FakeRigctld(freqHz: 14_025_000, mode: "CW")
        fake.setSplit(true, txHz: 14_030_000)
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port, label: "1 — Fake Rig")
        }
        let bandmap: BandmapModel = rigApp.model.bandmap
        let language: LanguageModel = rigApp.model.language
        #expect(bandmap.radioName(language) == "VFO A")
        #expect(bandmap.splitTxHz == nil)
        #expect(bandmap.txText == nil)
        await rigApp.connect()
        await rigApp.settle()
        #expect(bandmap.radioName(language) == "VFO A · Fake Rig")
        #expect(bandmap.splitTxHz == 14_030_000)
        #expect(bandmap.txText == "TX 14030.00 kHz")
        // The fake reports a 500 Hz passband in CW: centred on the RX frequency.
        #expect(bandmap.passbandRange == 14_024_750...14_025_250)

        // Zoomed in so the two arrows are apart (on the whole band 5 kHz is about 8 points).
        bandmap.zoomIn()
        bandmap.zoomIn()
        bandmap.zoomIn()
        let txY: Float = bandmap.viewport.yAt(14_030_000, height: Self.height)
        let rxY: Float = bandmap.viewport.yAt(14_025_000, height: Self.height)
        #expect(bandmap.markerTooltip(x: 30, y: txY, height: Self.height, axisX: Self.axisX) == "TX 14030.00 kHz")
        #expect(bandmap.markerTooltip(x: 30, y: rxY, height: Self.height, axisX: Self.axisX) == "RX 14025.00 kHz")
        #expect(bandmap.markerTooltip(x: 80, y: rxY, height: Self.height, axisX: Self.axisX) == nil)

        // A click on the red arrow turns split off; the RX frequency stays.
        bandmap.click(x: 30, y: txY, height: Self.height, axisX: Self.axisX, rowH: Self.rowH)
        await rigApp.settle()
        #expect(fake.writes == ["S 0 VFOA"])
        #expect(rigApp.rig.tuning.tunedFreqHz == 14_025_000)
        #expect(rigApp.status == "Split vypnut")
    }

    @Test func theModelSuffixDropsTheHamlibNumber() {
        #expect(BandmapModel.modelSuffix("3073 — Icom IC-7300") == " · Icom IC-7300")
        #expect(BandmapModel.modelSuffix("Elecraft K3") == " · Elecraft K3")
        #expect(BandmapModel.modelSuffix("  ") == "")
    }

    @Test func theLowestFrequencyAtTheBottomIsSavedAndFlipsTheWindow() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        #expect(!bandmap.lowestAtBottom)
        #expect(!bandmap.viewport.lowestAtBottom)
        bandmap.toggleLowestAtBottom()
        #expect(bandmap.viewport.lowestAtBottom)
        #expect(await spot.app.savedConfigFlushed().dxCluster.bandmapLowestAtBottom)
        // A spot is still hit and tuned to at its (flipped) position; the zoom keeps the orientation.
        model.dxCluster.spots.add(DxSpot(spotter: "OK1RR", freqHz: 14_010_000, dxCall: "DL1ABC", comment: ""))
        let y: Float = bandmap.viewport.yAt(14_010_000, height: Self.height)
        #expect(y > bandmap.viewport.yAt(14_300_000, height: Self.height))
        bandmap.click(x: Self.axisX + 20, y: y, height: Self.height, axisX: Self.axisX, rowH: Self.rowH)
        #expect(model.rig.tuning.tunedFreqHz == 14_010_000)
        bandmap.zoomIn()
        #expect(bandmap.viewport.lowestAtBottom)
        bandmap.toggleLowestAtBottom()
        #expect(!bandmap.viewport.lowestAtBottom)
    }

    @Test func theDisabledWheelNeitherTunesNorZooms() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        bandmap.toggleWheelDisabled()
        #expect(bandmap.wheelDisabled)
        let before: BandmapViewport = bandmap.viewport
        bandmap.wheel(dx: 0, dy: -1, ctrl: false, shift: false)
        bandmap.wheel(dx: 0, dy: -1, ctrl: true, shift: false)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_000)
        #expect(bandmap.viewport == before)
        #expect(await spot.app.savedConfigFlushed().dxCluster.bandmapWheelDisabled)
        bandmap.toggleWheelDisabled()
        bandmap.wheel(dx: 0, dy: -1, ctrl: false, shift: false)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_100)
    }

    @Test func zoomKeysZoomTheBandMap() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        let whole: Int64 = bandmap.viewport.spanHz
        let command: UInt = 1 << 20
        #expect(bandmap.handleKey(BandmapRadioViewTestsKeys.key(24, "=", flags: command)))
        #expect(bandmap.viewport.spanHz == whole / 2)
        #expect(bandmap.handleKey(BandmapRadioViewTestsKeys.key(24, "=", flags: command, kind: .keyUp)))
        #expect(bandmap.viewport.spanHz == whole / 2)
        #expect(bandmap.handleKey(BandmapRadioViewTestsKeys.key(78, "-")))
        #expect(bandmap.viewport.spanHz == whole)
        #expect(bandmap.handleKey(BandmapRadioViewTestsKeys.key(69, "+")))
        #expect(bandmap.handleKey(BandmapRadioViewTestsKeys.key(27, "-", flags: command)))
        #expect(bandmap.viewport.spanHz == whole)
        #expect(!bandmap.handleKey(BandmapRadioViewTestsKeys.key(24, "=")))
    }

    @Test func goToBottomAndTopOfTheBandPlanSegment() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        let bounds: ClosedRange<Int64> = BandmapViewport.bounds(.m20)
        let segments: [BandPlan.Segment] = bandmap.analyzer().bandPlanSegments(lo: bounds.lowerBound,
                                                                              hi: bounds.upperBound)
        let cw: ClosedRange<Int64> = BandmapViewport.subBand(tunedHz: 14_025_000, segments: segments, bounds: bounds)
        #expect(cw != bounds)
        #expect(cw.contains(14_025_000))
        bandmap.goToTopOfBand()
        #expect(model.rig.tuning.tunedFreqHz == cw.upperBound)
        model.rig.qsy(14_025_000)
        bandmap.goToBottomOfBand()
        #expect(model.rig.tuning.tunedFreqHz == cw.lowerBound)
        #expect(model.rig.tuning.previousFreqHz == 14_025_000)
    }
}

/// Key events for the band map's key handling.
enum BandmapRadioViewTestsKeys {
    static func key(_ code: UInt16, _ chars: String, flags: UInt = 0,
                    kind: MacKeyEvent.Kind = .keyDown) -> MacKeyEvent {
        MacKeyEvent(kind: kind, keyCode: code, characters: chars, charactersIgnoringModifiers: chars,
                    modifierFlags: flags)
    }
}
