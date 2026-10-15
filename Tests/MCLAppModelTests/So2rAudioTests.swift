import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Radio 2's own receiver audio (the second CW Reader and the spectrum window bound to radio 2) and N1MM's SO2R
/// routing of the voice messages. No audio device is opened; nothing transmits.
@MainActor @Suite struct So2rAudioTests {

    @Test func theSecondReaderFillsTheSecondWindow() async throws {
        let app = try await TestApp.make { config, _ in
            config.radioMode = "SO2R"
        }
        let model: AppModel = app.model
        model.vfoB.entry.isWindowShown = true
        model.setRadio2AudioDevice("USB Audio 2")
        #expect(model.config.config.so2rSetup == ["rx2AudioDevice": "USB Audio 2"])
        let reader: CwReaderModel = model.makeCwReader2()
        reader.take("DL1ABC")
        #expect(model.vfoB.entry.form.call == "DL1ABC")
        #expect(model.entry.form.call.isEmpty)
        #expect(MenuActions.perform("window.cwreader2", app: model) == nil)
        #expect(model.windows.isOpen("cwreader2"))
    }

    @Test func theSecondSpectrumWindowFollowsRadio2() async throws {
        let app = try await TestApp.make { config, _ in
            config.radioMode = "SO2R"
        }
        let model: AppModel = app.model
        model.vfoB.entry.isWindowShown = true
        model.rig.qsy(14_025_000)
        model.rig.rememberInactiveFrequency(7_010_000, vfo: 1)
        let spectrum: WaterfallModel = model.makeWaterfall2()
        #expect(spectrum.radio == 1)
        #expect(spectrum.bindsOtherRadio)
        #expect(spectrum.dialHz == 7_010_000)
        spectrum.tuneRig(7_012_000)
        #expect(model.rig.otherVfoFreqHz == 7_012_000)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_000)
        // With radio 2 focused the window tunes it as the focused radio.
        model.rig.activateVfo(1, rxOnly: true)
        #expect(!spectrum.bindsOtherRadio)
        let first: WaterfallModel = model.makeWaterfall()
        #expect(first.radio == nil && !first.bindsOtherRadio)
    }

    @Test func voiceMessagesFollowTheRouting() async throws {
        let app = try await TestApp.make { config, _ in
            config.radioMode = "SO2R"
        }
        let model: AppModel = app.model
        #expect(MenuActions.perform("so2r.voice2.right", app: model) == nil)
        #expect(MenuActions.isChecked("so2r.voice2.right", app: model))
        #expect(MenuActions.isChecked("so2r.voice1.both", app: model))
        #expect(model.config.config.so2rSetup == ["voiceChannel2": "right"])
        #expect(So2rSetup.VoiceChannel(rawValue: model.config.config.so2r.text(.voiceChannel2))?.index == 2)
    }
}

/// N1MM's Available window per entry window (SO2V / SO2R): the second one is bound to radio 2.
@MainActor @Suite struct So2rAvailableTests {

    @Test func theSecondAvailableWindowServesRadio2() async throws {
        let spot = try await SpotApp.make(configure: { config, _ in
            config.radioMode = "SO2R"
        })
        let model: AppModel = spot.model
        try await spot.app.startCqWwCw()
        model.vfoB.entry.isWindowShown = true
        model.rig.qsy(14_025_000)
        model.rig.rememberInactiveFrequency(7_000_000, vfo: 1)
        model.dxCluster.spots.add(DxSpot(spotter: "OK1RR", freqHz: 7_012_000, dxCall: "W1AW", comment: ""))
        model.dxCluster.spots.add(DxSpot(spotter: "OK1RR", freqHz: 14_030_000, dxCall: "JA1ABC", comment: ""))
        let second: AvailMultModel = model.availMult2
        #expect(second.radio == 1 && second.focusRadioOnly)
        let rows: [String] = second.snapshot().rows.map(\.call)
        #expect(rows == ["W1AW"])
        let row = try #require(second.snapshot().rows.first)
        second.click(row)
        #expect(model.rig.otherVfoFreqHz == 7_012_000)
        #expect(model.vfoB.entry.form.call == "W1AW")
        #expect(model.rig.vfo.activeVfo == 0)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_000)
        #expect(MenuActions.perform("window.availmult2", app: model) == nil)
        #expect(model.windows.isOpen("availMult2"))
    }
}
