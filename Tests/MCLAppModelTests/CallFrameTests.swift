import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM's band map spot interaction: the call-frame above the call field (single click, tuning near a spot, the space
/// bar), the double click, the tuning tolerance per mode, „Always use packet spot mode", the spot marks and tooltip,
/// and „Find a Callsign". No rig is connected: the tuning is the shared state only and nothing transmits.
@MainActor @Suite struct CallFrameTests {

    static let height: Float = 600
    static let rowH: Float = 14
    static let axisX: Float = 60

    static func spot(_ call: String, _ freqHz: Int, spotter: String = "OK1RR", comment: String = "") -> DxSpot {
        DxSpot(spotter: spotter, freqHz: freqHz, dxCall: call, comment: comment)
    }

    static func click(_ bandmap: BandmapModel, _ hz: Int64, double: Bool = false) {
        let y: Float = bandmap.viewport.yAt(hz, height: height)
        if double {
            bandmap.doubleClick(x: axisX + 20, y: y, height: height, axisX: axisX, rowH: rowH)
        } else {
            bandmap.click(x: axisX + 20, y: y, height: height, axisX: axisX, rowH: rowH)
        }
    }

    /// A single click tunes and shows the call in the call-frame only; the space bar in the empty call field takes it
    /// (a call from a spot); a double click fills the field at once, replacing a typed call.
    @Test func aClickShowsTheCallFrameAndTheSpaceBarTakesIt() async throws {
        let app = try await SpotApp.make()
        let model: AppModel = app.model
        let entry: EntryModel = model.entry
        model.rig.qsy(14_025_000)
        model.dxCluster.spots.add(Self.spot("DL1ABC", 14_100_000))
        await runMainQueue()
        #expect(entry.callFrameCall == nil)
        Self.click(model.bandmap, 14_100_000)
        await runMainQueue()
        #expect(model.rig.tuning.tunedFreqHz == 14_100_000)
        #expect(entry.form.call.isEmpty)
        #expect(entry.callFrameCall == "DL1ABC")
        entry.jumpToExchange()
        #expect(entry.form.call == "DL1ABC")
        #expect(entry.callFromSpot)
        // The field holds the call now: the call-frame does not repeat it, and the space bar keeps the field.
        #expect(entry.callFrameCall == nil)
        #expect(entry.callFrameSpot?.dxCall == "DL1ABC")

        entry.callChanged("OK1AB")
        model.dxCluster.spots.add(Self.spot("W1AW", 14_200_000))
        Self.click(model.bandmap, 14_200_000, double: true)
        await runMainQueue()
        #expect(entry.form.call == "W1AW")
        #expect(entry.callFromSpot)
    }

    /// A click on the frequency scale (left of the axis) tunes to the frequency under the cursor.
    @Test func aClickOnTheScaleTunes() async throws {
        let app = try await SpotApp.make()
        let bandmap: BandmapModel = app.model.bandmap
        app.model.rig.qsy(14_025_000)
        let y: Float = bandmap.viewport.yAt(14_300_000, height: Self.height)
        let expected: Int64 = bandmap.viewport.freqAt(y, height: Self.height)
        bandmap.click(x: 10, y: y, height: Self.height, axisX: Self.axisX, rowH: Self.rowH)
        #expect(app.model.rig.tuning.tunedFreqHz == expected)
    }

    /// With a typed call in the field the space bar only moves on: the call-frame never replaces it.
    @Test func theSpaceBarKeepsATypedCall() async throws {
        let app = try await SpotApp.make()
        let entry: EntryModel = app.model.entry
        app.model.rig.qsy(14_025_000)
        app.model.dxCluster.spots.add(Self.spot("DL1ABC", 14_025_100))
        await runMainQueue()
        entry.callChanged("OK2XYZ")
        #expect(entry.callFrameCall == "DL1ABC")
        entry.jumpToExchange()
        #expect(entry.form.call == "OK2XYZ")
    }

    /// The call-frame reaches as far as the tuning tolerance of the window's mode; tuning near a spot shows it in the
    /// call-frame and no longer fills the empty field (v1.1.1's prefill is off with the call-frame).
    @Test func theToleranceFollowsTheMode() async throws {
        let app = try await SpotApp.make { config, _ in
            config.dxCluster.tuningToleranceCwHz = 100
            config.dxCluster.tuningToleranceSsbHz = 500
        }
        let model: AppModel = app.model
        let entry: EntryModel = model.entry
        entry.setMode(.cw)
        model.dxCluster.spots.add(Self.spot("K1ZZ", 14_200_000))
        model.rig.qsy(14_200_300)
        await runMainQueue()
        #expect(entry.callFrameCall == nil)
        #expect(model.bandmap.tuningToleranceHz == 100)
        entry.setMode(.ssb)
        #expect(entry.callFrameCall == "K1ZZ")
        #expect(model.bandmap.tuningToleranceHz == 500)
        #expect(entry.form.call.isEmpty)
        model.config.config.dxCluster.callFrame = false
        #expect(entry.callFrameCall == nil)
        #expect(model.bandmap.tuningToleranceHz == nil)
    }

    /// „Always use packet spot mode": a click on a spot sets the spot's mode in the entry window; off, the mode stays.
    @Test func packetSpotModeSetsTheMode() async throws {
        let app = try await SpotApp.make { config, _ in config.dxCluster.spotModeOnTune = true }
        let model: AppModel = app.model
        model.rig.qsy(14_025_000)
        model.entry.setMode(.cw)
        model.dxCluster.spots.add(Self.spot("JA1XYZ", 14_074_000, comment: "FT8 -12 dB"))
        model.dxCluster.spots.add(Self.spot("K1ZZ", 14_250_000))
        Self.click(model.bandmap, 14_074_000)
        await runMainQueue()
        #expect(model.entry.form.mode == .ft8)
        Self.click(model.bandmap, 14_250_000)
        await runMainQueue()
        #expect(model.entry.form.mode == .ssb)
        #expect(model.entry.form.rstSent == "59")

        model.config.config.dxCluster.spotModeOnTune = false
        Self.click(model.bandmap, 14_074_000)
        await runMainQueue()
        #expect(model.entry.form.mode == .ssb)
    }

    /// The label marks (skimmer `#`, `QSX`, `NEW` for three minutes) and the tooltip (spotter, age, comment, count).
    @Test func marksAndTooltip() async throws {
        let now = TestNow(Date(timeIntervalSince1970: 1_790_000_000))
        let app = try await SpotApp.make(now: now)
        let model: AppModel = app.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        let split = Self.spot("K1ZZ", 14_025_000, comment: "UP 2")
        model.dxCluster.spots.add(split)
        model.dxCluster.spots.add(split)
        let skimmed = Self.spot("W1AW", 14_030_000, spotter: "DL8LAS-#", comment: "12 dB 28 WPM CQ")
        model.dxCluster.spots.add(skimmed)
        #expect(bandmap.drawnLabel(split) == "K1ZZ QSX 027 NEW")
        #expect(bandmap.drawnLabel(skimmed) == "W1AW# NEW")
        now.advance(seconds: 4 * 60)
        #expect(bandmap.drawnLabel(split) == "K1ZZ QSX 027")
        let tooltip: String = bandmap.tooltip(split)
        #expect(tooltip.hasPrefix("K1ZZ   14025.0 kHz\nSpotter: OK1RR\nPřed 4 min\nKomentář: UP 2\nQSX 14027.0 kHz"))
        #expect(tooltip.contains("Spotováno 2x"))
        #expect(bandmap.tooltip(skimmed).contains("Skimmerů: 1"))
    }

    /// „Find a Callsign": the next matching spot above the tuned frequency (wrapping), tuned like a click; none found
    /// says so in the status line.
    @Test func findACallsign() async throws {
        let app = try await SpotApp.make()
        let model: AppModel = app.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        model.dxCluster.spots.add(Self.spot("K1ABC", 14_010_000))
        model.dxCluster.spots.add(Self.spot("DL1ABC", 14_100_000))
        bandmap.find("abc")
        #expect(model.rig.tuning.tunedFreqHz == 14_100_000)
        #expect(model.rig.tuning.previousFreqHz == 14_025_000)
        bandmap.find("abc")
        #expect(model.rig.tuning.tunedFreqHz == 14_010_000)
        await runMainQueue()
        #expect(model.entry.form.call.isEmpty)
        #expect(model.entry.callFrameCall == "K1ABC")
        bandmap.find("zz9")
        #expect(model.status.message == "ZZ9 v bandmapě není")
        #expect(model.rig.tuning.tunedFreqHz == 14_010_000)
        bandmap.promptFind()
        #expect(model.dialogs.textPrompt != nil)
        model.dialogs.submitPrompt("DL1")
        #expect(model.rig.tuning.tunedFreqHz == 14_100_000)
    }
}
