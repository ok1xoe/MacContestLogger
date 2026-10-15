import Foundation
@testable import MCLCore
import Testing

/// The engine pane's waterfall: the newest row on top, a strong bin bright against the noise, the line spectrum.
@Suite struct BuiltinWaterfallTests {

    @Test func newRowsScrollDownAndPeaksAreBright() {
        var waterfall = BuiltinWaterfall(width: 100, height: 4)
        var magnitudes = [Float](repeating: 10, count: 512)
        magnitudes[200] = 400
        let frame = BuiltinRttyChannel.Spectrum(binHz: 6_000 / 512, magnitudes: magnitudes)
        waterfall.push(frame, fromHz: 0, toHz: 6_000)
        let peakX = Int(200 * (6_000.0 / 512) / 60)
        let bright: UInt32 = waterfall.pixels[peakX]
        let dark: UInt32 = waterfall.pixels[10]
        #expect(bright != dark)
        #expect(dark == 0xFF00_0000, "the noise floor is black")
        #expect(waterfall.spectrumLine[peakX] > 0.9)
        waterfall.push(BuiltinRttyChannel.Spectrum(binHz: 6_000 / 512, magnitudes: [Float](repeating: 10, count: 512)),
                       fromHz: 0, toHz: 6_000)
        #expect(waterfall.pixels[100 + peakX] == bright, "the row moved down")
        #expect(waterfall.spectrumLine[peakX] > 0.3, "the line decays slowly")
    }
}

/// Settings → Digital modes: the built-in engine and its options go through the draft (one map, not a field each).
@MainActor @Suite struct BuiltinModemDraftTests {

    @Test func draftCarriesTheBuiltinOptions() {
        var config = AppConfig()
        config.contestDataDir = ConfigurerDraftApplyTests.defaultDir
        config.digital.engine = .builtin
        config.builtinModemSetup = ["channel2": "left", "input2": "radio2"]
        var draft = ConfigurerDraftApplyTests.draft(config)
        #expect(draft.digiEngine == .builtin)
        #expect(draft.builtinModem.channel(side: 1) == .left)
        var setup: BuiltinModemSetup = draft.builtinModem
        setup.set(.pttViaCat, flag: false)
        draft.builtinModem = setup
        let out: AppConfig = draft.applied(to: config, now: ConfigurerDraftApplyTests.now)
        #expect(out.digital.engine == .builtin)
        #expect(out.digital.builtinModem)
        #expect(out.builtinModemSetup == ["channel2": "left", "input2": "radio2", "pttViaCat": "false"])
        draft.digiEngine = .fldigi
        #expect(!draft.applied(to: config, now: ConfigurerDraftApplyTests.now).digital.builtinModem)
    }
}
