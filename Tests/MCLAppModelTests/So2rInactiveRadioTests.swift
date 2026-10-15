import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM's non-active radio keys (SO2R): the other radio jumps to spots (skipping the active radio's frequency on its
/// band), changes band past the software band lockout, goes to its CQ frequency, `/freq` and the band map's
/// Shift+click tune it, and Alt+PgUp/PgDn set its own CW speed. No rig is connected and nothing transmits.
@MainActor @Suite struct So2rInactiveRadioTests {

    private static func spot(_ call: String, _ freqHz: Int) -> DxSpot {
        DxSpot(spotter: "OK1RR", freqHz: freqHz, dxCall: call, comment: "")
    }

    private static func make() async throws -> (SpotApp, EntryModel) {
        let spot = try await SpotApp.make(configure: { config, _ in
            config.radioMode = "SO2R"
        })
        let second: EntryModel = spot.model.vfoB.entry
        second.isWindowShown = true
        spot.model.rig.qsy(14_025_000)
        spot.model.rig.rememberInactiveFrequency(7_000_000, vfo: 1)
        return (spot, second)
    }

    @Test func otherRadioJumpsToSpots() async throws {
        let (spot, second) = try await Self.make()
        let model: AppModel = spot.model
        let buffer: SpotBuffer = model.dxCluster.spots
        buffer.add(Self.spot("DL2XYZ", 7_005_000))
        buffer.add(Self.spot("W1AW", 7_012_000))
        buffer.add(Self.spot("K1ABC", 14_025_100))
        buffer.add(Self.spot("N1MM", 14_030_000))
        model.entry.runShortcut(.otherSpotUp)
        #expect(model.rig.otherVfoFreqHz == 7_005_000)
        #expect(second.form.call == "DL2XYZ")
        #expect(second.form.freqKHz == "7005.00")
        #expect(model.rig.tuning.tunedFreqHz == 14_025_000)
        #expect(model.rig.vfo.activeVfo == 0)
        model.entry.runShortcut(.otherSpotUp)
        #expect(second.form.call == "W1AW")
        model.entry.runShortcut(.otherSpotDown)
        #expect(second.form.call == "DL2XYZ")
        // On the active radio's band its own frequency (the CQ frequency) is skipped.
        model.rig.rememberInactiveFrequency(14_020_000, vfo: 1)
        model.entry.runShortcut(.otherSpotUp)
        #expect(model.rig.otherVfoFreqHz == 14_030_000)
        #expect(second.form.call == "N1MM")
    }

    @Test func bandsCqFrequencyAndSlashFrequency() async throws {
        let (spot, second) = try await Self.make()
        let model: AppModel = spot.model
        // Ctrl+Shift+PgUp from 40 m: 20 m belongs to the active radio and is skipped.
        model.entry.runShortcut(.otherBandUp)
        let up: Int64 = try #require(model.rig.otherVfoFreqHz)
        let band: Band? = Band.from(frequencyHz: Int(up))
        #expect(band != nil && band != .m20 && band != .m40)
        #expect(up > 7_300_000)
        // Ctrl+PgUp of the active radio skips the other radio's band.
        model.rig.rememberInactiveFrequency(18_080_000, vfo: 1)
        let otherBand: Band? = model.rig.otherRadioBand
        model.entry.runShortcut(.bandUp)
        #expect(model.rig.currentBand != otherBand)
        #expect(model.rig.currentBand != .m20)
        // Shift+Alt+Q: the other radio to the CQ frequency of its band.
        model.operating.onCqSent(18_075_000)
        model.entry.runShortcut(.otherCqFrequency)
        #expect(model.rig.otherVfoFreqHz == 18_075_000)
        model.rig.rememberInactiveFrequency(28_400_000, vfo: 1)
        model.entry.runShortcut(.otherCqFrequency)
        #expect(model.status.message == "Druhé rádio: na jeho pásmu není CQ frekvence")
        // `/7030` tunes the other radio in SO2R.
        model.entry.runRigCommand(.otherVfo(freqHz: 7_030_000))
        #expect(model.rig.otherVfoFreqHz == 7_030_000)
        #expect(second.form.freqKHz == "7030.00")
        // The band map's Shift+click path.
        model.rig.tuneOtherToSpot(Self.spot("OK1XOE", 7_021_000))
        #expect(second.form.call == "OK1XOE")
        #expect(model.entry.form.call.isEmpty)
    }

    @Test func eachRadioKeepsItsCwSpeed() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.radioMode = "SO2R"
            config.cwKeyer.speed = 28
            config.cwSpeedStep = 2
        })
        app.model.vfoB.entry.isWindowShown = true
        app.entry.setMode(.cw)
        #expect(app.entry.handle(.cwSpeedOther(1)))
        #expect(app.keyer.cwSpeed == 28)
        #expect(app.keyer.otherCwSpeed == 30)
        #expect(app.status == "CW rádio 2: 30 WPM")
        app.model.rig.claimTx(1)
        #expect(app.keyer.cwSpeed == 30)
        #expect(app.keyer.otherCwSpeed == 28)
        app.model.rig.claimTx(0)
        #expect(app.keyer.cwSpeed == 28)
    }

    @Test func altPageKeysNeedTwoRadios() {
        let alt: Int32 = AwtKeyCodes.altDownMask
        let press = AwtKeyStroke(vk: AwtKeyCodes.vkPageUp, location: 1, modifiers: alt, phase: .pressed)
        let one = EntryKeyContext(bindings: KeyBindings(nil), isCw: true)
        #expect(EntryKeyRouter.route(press, context: one) == .cwSpeed(1))
        let two = EntryKeyContext(bindings: KeyBindings(nil), isCw: true, twoRadios: true)
        #expect(EntryKeyRouter.route(press, context: two) == .cwSpeedOther(1))
    }
}
