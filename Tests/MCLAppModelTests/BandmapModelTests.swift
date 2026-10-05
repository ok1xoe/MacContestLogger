import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The Bandmap's model (`BM:79-360`): the window of the tuned band (reset when the band changes), a
/// click on a spot / into the empty band / on the CQ marker, the wheel (QSY by the step, Ctrl = zoom), the drag zoom,
/// the menu and the band plan option saved without side effects. The rig is inert; nothing transmits.
@MainActor @Suite struct BandmapModelTests {

    static let height: Float = 600
    static let rowH: Float = 14
    static let axisX: Float = 60

    static func spot(_ call: String, _ freqHz: Int, spotter: String = "OK1RR") -> DxSpot {
        DxSpot(spotter: spotter, freqHz: freqHz, dxCall: call, comment: "")
    }

    @Test func aQo100SpotIsMarkedInTheDrawnLabel() async throws {
        let spot = try await SpotApp.make()
        let bandmap: BandmapModel = spot.model.bandmap
        let qo100: DxSpot = Self.spot("A71BX", 10_489_750_000)
        #expect(bandmap.drawnLabel(qo100) == bandmap.label(qo100) + "  QO-100")
        let plain: DxSpot = Self.spot("OK2A", 10_368_100_000)
        #expect(bandmap.drawnLabel(plain) == bandmap.label(plain))
    }

    @Test func aMicrowaveBandOpensOnTheWindowAroundTheTunedFrequency() async throws {
        let spot = try await SpotApp.make()
        let bandmap: BandmapModel = spot.model.bandmap
        spot.model.rig.qsy(10_489_750_000)
        #expect(bandmap.band == .cm3)
        await runMainQueue()
        #expect(bandmap.viewport == BandmapViewport(band: .cm3, tunedHz: 10_489_750_000))
        #expect(bandmap.viewport.spanHz == 2_000_000)
        bandmap.zoomOut()
        #expect(bandmap.viewport.spanHz == 4_000_000)
        bandmap.resetView()
        #expect(bandmap.viewport.spanHz == 2_000_000)
    }

    @Test func theWindowFollowsTheBand() async throws {
        let spot = try await SpotApp.make()
        let bandmap: BandmapModel = spot.model.bandmap
        #expect(bandmap.band == nil)
        spot.model.rig.qsy(14_025_000)
        #expect(bandmap.band == .m20)
        #expect(bandmap.viewport == BandmapViewport(band: .m20))
        #expect(bandmap.tunedText == "14025.00 kHz")
        bandmap.zoomIn()
        let zoomed: BandmapViewport = bandmap.viewport
        #expect(zoomed.spanHz == BandmapViewport(band: .m20).spanHz / 2)
        // Another band: its whole range at once; back on 20 m the window starts over (Kotlin `remember(band)`).
        spot.model.rig.qsy(7_010_000)
        #expect(bandmap.viewport == BandmapViewport(band: .m40))
        await runMainQueue()
        spot.model.rig.qsy(14_025_000)
        await runMainQueue()
        #expect(bandmap.viewport == BandmapViewport(band: .m20))
        // Reopening the window starts over too.
        bandmap.zoomIn()
        bandmap.setSpotFont(20)
        bandmap.windowOpened()
        #expect(bandmap.viewport == BandmapViewport(band: .m20))
        #expect(bandmap.spotFont == 11)
        bandmap.zoomIn()
        bandmap.zoomOut()
        #expect(bandmap.viewport.spanHz == BandmapViewport(band: .m20).spanHz)
        bandmap.zoomIn()
        bandmap.resetView()
        #expect(bandmap.viewport == BandmapViewport(band: .m20))
    }

    /// A click right of the axis on a spot tunes to it; elsewhere it QSYs to the frequency under the cursor; on the
    /// CQ marker (left of the axis) back to the CQ frequency in Run.
    @Test func clicksTuneToSpotsTheBandAndTheCqFrequency() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        model.dxCluster.spots.add(Self.spot("DL1ABC", 14_100_000))
        let spotY: Float = bandmap.viewport.yAt(14_100_000, height: Self.height)
        bandmap.click(x: Self.axisX + 20, y: spotY, height: Self.height, axisX: Self.axisX, rowH: Self.rowH)
        #expect(model.rig.tuning.tunedFreqHz == 14_100_000)
        #expect(model.entry.form.call == "DL1ABC")
        #expect(model.entry.callFromSpot)
        // The entry field follows the band map's QSY (`EP:189-196`): a logged QSO gets this frequency.
        #expect(model.entry.form.freqKHz == "14100.00")

        let emptyY: Float = bandmap.viewport.yAt(14_250_000, height: Self.height)
        let expected: Int64 = bandmap.viewport.freqAt(emptyY, height: Self.height)
        bandmap.click(x: Self.axisX + 20, y: emptyY, height: Self.height, axisX: Self.axisX, rowH: Self.rowH)
        #expect(model.rig.tuning.tunedFreqHz == expected)
        #expect(model.rig.tuning.previousFreqHz == 14_100_000)

        model.operating.onCqSent(14_050_000)
        model.operating.runMode = .searchAndPounce
        let cqY: Float = bandmap.viewport.yAt(14_050_000, height: Self.height)
        bandmap.click(x: 10, y: cqY + 9, height: Self.height, axisX: Self.axisX, rowH: Self.rowH)
        #expect(model.rig.tuning.tunedFreqHz == 14_050_000)
        #expect(model.operating.runMode == .run)
    }

    /// The wheel: up (Compose `dy < 0`) QSYs by `wheelStepHz`, Shift by `wheelStepShiftHz`, down the other way; Ctrl
    /// zooms instead. The window follows the marker.
    @Test func theWheelTunesAndZooms() async throws {
        let spot = try await SpotApp.make { config, _ in
            config.dxCluster.wheelStepHz = 100
            config.dxCluster.wheelStepShiftHz = 1_000
        }
        let model: AppModel = spot.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        bandmap.wheel(dx: 0, dy: -1, ctrl: false, shift: false)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_100)
        bandmap.wheel(dx: 0, dy: 1, ctrl: false, shift: true)
        #expect(model.rig.tuning.tunedFreqHz == 14_024_100)
        // macOS turns Shift+wheel into a horizontal scroll: the dominant axis counts.
        bandmap.wheel(dx: -2, dy: 0, ctrl: false, shift: true)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_100)
        let span: Int64 = bandmap.viewport.spanHz
        bandmap.wheel(dx: 0, dy: -1, ctrl: true, shift: false)
        #expect(bandmap.viewport.spanHz == span / 2)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_100)
        bandmap.wheel(dx: 0, dy: 0, ctrl: true, shift: false)
        #expect(bandmap.viewport.spanHz == span)
    }

    /// A drag longer than 6 px zooms onto the dragged range; a shorter one does nothing.
    @Test func theDragZooms() async throws {
        let spot = try await SpotApp.make()
        let bandmap: BandmapModel = spot.model.bandmap
        spot.model.rig.qsy(14_025_000)
        let before: BandmapViewport = bandmap.viewport
        bandmap.drag(from: 100, to: 106, height: Self.height)
        #expect(bandmap.viewport == before)
        bandmap.drag(from: 300, to: 100, height: Self.height)
        #expect(bandmap.viewport.loHz == before.freqAt(100, height: Self.height))
        #expect(bandmap.viewport.hiHz == before.freqAt(300, height: Self.height))
    }

    /// The menu of a spot: blacklist, remove, QRZ.com / HamQTH (the recording opener), clear all; the band plan
    /// option is written to the config file and the plan shows only while it is on.
    @Test func theMenuAndTheBandPlanOption() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        let buffer: SpotBuffer = model.dxCluster.spots
        buffer.add(Self.spot("DL1ABC", 14_100_000, spotter: "DL0SKM"))
        buffer.add(Self.spot("W1AW", 14_200_000))
        let y: Float = bandmap.viewport.yAt(14_100_000, height: Self.height)
        #expect(bandmap.menuSpot(x: 20, y: y, height: Self.height, axisX: Self.axisX, rowH: Self.rowH) == nil)
        let target: DxSpot = try #require(bandmap.menuSpot(x: 200, y: y, height: Self.height, axisX: Self.axisX,
                                                           rowH: Self.rowH))
        #expect(target.dxCall == "DL1ABC")
        bandmap.openQrz(target)
        bandmap.openHamQth(target)
        await eventually("pages") { spot.opener.urls.count == 2 }
        #expect(spot.opener.urls == ["https://www.qrz.com/db/DL1ABC", "https://www.hamqth.com/DL1ABC"])
        bandmap.blacklistSpotter(target)
        #expect(model.config.config.dxCluster.spotterBlacklist.map(\.value) == ["DL0SKM"])
        #expect(buffer.snapshot().map(\.dxCall) == ["W1AW"])
        bandmap.blacklistCall(Self.spot("W1AW", 14_200_000))
        #expect(model.config.config.dxCluster.callBlacklist.map(\.value) == ["W1AW"])
        buffer.add(Self.spot("K1AA", 14_150_000))
        buffer.add(Self.spot("K2AA", 14_160_000))
        bandmap.remove(Self.spot("K1AA", 0))
        #expect(buffer.snapshot().map(\.dxCall) == ["K2AA"])
        bandmap.clearSpots()
        #expect(buffer.snapshot().isEmpty)

        #expect(bandmap.showPlan)
        #expect(!bandmap.planSegments(analyzer: bandmap.analyzer()).isEmpty)
        bandmap.toggleBandPlan()
        #expect(!bandmap.showPlan)
        #expect(bandmap.planSegments(analyzer: bandmap.analyzer()).isEmpty)
        #expect(await spot.app.savedConfigFlushed().dxCluster.showBandPlan == false)
    }

    /// The colours (outside a contest always „good"), the labels, the band notes and the spot font.
    @Test func coloursLabelsNotesAndFont() async throws {
        let spot = try await SpotApp.make { config, _ in
            var note = BandNote()
            note.band = "20m"
            note.freqKHz = 14_060
            note.text = "QRP"
            var other = BandNote()
            other.band = "40m"
            other.text = "SSB"
            config.bandNotes = [note, other]
        }
        let model: AppModel = spot.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        let dl = Self.spot("DL1ABC", 14_030_000)
        #expect(bandmap.colorKey(dl, analyzer: bandmap.analyzer()) == .good)
        try await spot.app.startCqWwCw()
        #expect(bandmap.colorKey(dl, analyzer: bandmap.analyzer()) == .multiMult)
        await spot.app.logContestQso(call: "DL1ABC", zone: "14")
        await model.logbook.settleMutations()
        #expect(bandmap.colorKey(dl, analyzer: bandmap.analyzer()) == .dupe)
        #expect(bandmap.label(dl) == "DL1ABC")
        #expect(bandmap.notes.map(\.text) == ["QRP"])
        #expect(bandmap.spotFont == 11)
        bandmap.setSpotFont(40)
        #expect(bandmap.spotFont == 28)
        bandmap.setSpotFont(2)
        #expect(bandmap.spotFont == 8)
    }
}
