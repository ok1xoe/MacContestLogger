import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM entry keys: Ctrl+Shift+W wipes the other entry window, Ctrl+Alt+Q goes to the last CQ frequency on any band,
/// SH/DX typed in the call field goes to the DX cluster. Fake rig and cluster only; nothing transmits.
@MainActor @Suite struct KeyboardEntryKeysTests {

    @Test func wipeOtherWindow() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2V"
        }
        let second: EntryModel = rigApp.model.vfoB.entry
        second.isWindowShown = true
        rigApp.entry.callChanged("OK1ABC")
        second.callChanged("DL1XYZ")
        rigApp.entry.runShortcut(.wipeOther)
        #expect(second.form.call.isEmpty)
        #expect(rigApp.entry.form.call == "OK1ABC")
        second.callChanged("DL2AA")
        second.runShortcut(.wipeOther)
        #expect(rigApp.entry.form.call.isEmpty)
        #expect(second.form.call == "DL2AA")
    }

    @Test func wipeOtherWithoutTwoWindowsSaysSo() async throws {
        let rigApp = try await RigApp.make()
        rigApp.entry.callChanged("OK1ABC")
        rigApp.entry.runShortcut(.wipeOther)
        #expect(rigApp.entry.form.call == "OK1ABC")
        #expect(rigApp.model.status.message == "Druhé okno není otevřené (SO2V / SO2R)")
    }

    @Test func lastCqFrequencyOnAnyBand() async throws {
        let rigApp = try await RigApp.make()
        let model: AppModel = rigApp.model
        rigApp.entry.runShortcut(.jumpLastCq)
        #expect(model.status.message == "Zatím nebylo žádné CQ")
        model.operating.onCqSent(14_030_000)
        model.operating.onCqSent(7_012_000)
        rigApp.entry.setFrequency("21025")
        model.operating.runMode = .searchAndPounce
        rigApp.entry.runShortcut(.jumpLastCq)
        #expect(rigApp.entry.form.freqHz == 7_012_000)
        #expect(model.operating.runMode == .run)
    }

    @Test func shDxGoesToTheCluster() async throws {
        let spot = try await SpotApp.make()
        let entry: EntryModel = spot.model.entry
        entry.callChanged("SH/DX")
        #expect(entry.hasCommand)
        entry.submit()
        #expect(spot.model.status.message == "DX Cluster není připojen")
        #expect(entry.form.call == "SH/DX")
        let fav: DxClusterFavorite = spot.server.favorite(name: "")
        spot.dx.toggle(fav)
        await eventually("connected") { spot.dx.connected }
        entry.submit()
        await eventually("SH/DX sent") { spot.server.lines(0).contains("SH/DX") }
        #expect(entry.form.call.isEmpty)
        #expect(spot.model.logbook.rows.isEmpty)
    }
}
