import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Tuning (`AS:544-551, 582-588, 811-838`, `EP:178-196, 782-803, 1032-1043`): QSY, the previous
/// frequency, band stepping, the arrows and the wheel, the loop guard between the field and the tuned frequency.
@MainActor @Suite struct RigTuningTests {

    static func connected(freqHz: Int64 = 14_025_000, mode: String = "CW",
                          configure: @escaping (inout AppConfig) -> Void = { _ in })
        async throws -> (RigApp, FakeRigctld) {
        let fake = try FakeRigctld(freqHz: freqHz, mode: mode)
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port)
            configure(&config)
        }
        await rigApp.connect()
        return (rigApp, fake)
    }

    /// A QSY to ≤ 0 is local as in Kotlin (the tuned and previous frequency follow), nothing reaches CAT.
    @Test func qsyToZeroOrLessIsLocalOnly() async throws {
        let (rigApp, fake) = try await Self.connected()
        let rig: MCLAppModel.RigModel = rigApp.rig
        rig.qsy(7_010_000)
        rig.qsy(0)
        #expect(rig.tuning.tunedFreqHz == 0)
        #expect(rig.tuning.previousFreqHz == 7_010_000)
        rig.qsy(-5)
        #expect(rig.tuning.tunedFreqHz == -5)
        // The previous frequency is kept only from a tuned frequency > 0.
        #expect(rig.tuning.previousFreqHz == 7_010_000)
        // The QSY command with 0: the field, the status, the shared frequency — no CAT.
        rigApp.entry.runCommand(.qsy(freqHz: 0))
        #expect(rigApp.entry.form.freqKHz == "0.00")
        #expect(rigApp.status == "QSY na 0.00 kHz")
        #expect(rig.tuning.tunedFreqHz == 0)
        await rigApp.settle()
        #expect(fake.writes == ["F 7010000"])
    }

    /// A QSY command tunes the rig; the previous frequency is the one before the command (Kotlin `state.qsy` runs
    /// before the field's effect).
    @Test func qsyCommandTunesTheRigAndRemembersThePreviousFrequency() async throws {
        let (rigApp, fake) = try await Self.connected()
        rigApp.entry.callChanged("7010")
        rigApp.entry.handle(.enter(ctrl: false, step: .logQso(ctrlEnter: false)))
        #expect(rigApp.entry.form.freqKHz == "7010.00")
        #expect(rigApp.rig.tuning.tunedFreqHz == 7_010_000)
        #expect(rigApp.rig.tuning.previousFreqHz == 14_025_000)
        await rigApp.settle()
        #expect(fake.writes == ["F 7010000"])
    }

    /// Alt+F8 goes there and back; without a previous frequency `tr("Alt+F8: žádná předchozí frekvence")`.
    @Test func previousFrequencyThereAndBack() async throws {
        let rigApp = try await RigApp.make()
        let rig: MCLAppModel.RigModel = rigApp.rig
        rigApp.entry.runShortcut(.previousFrequency)
        #expect(rigApp.status == "Alt+F8: žádná předchozí frekvence")
        rig.qsy(14_025_000)
        rig.qsy(7_010_000)
        rigApp.entry.runShortcut(.previousFrequency)
        #expect(rig.tuning.tunedFreqHz == 14_025_000)
        #expect(rigApp.entry.form.freqKHz == "14025.00")
        rigApp.entry.runShortcut(.previousFrequency)
        #expect(rig.tuning.tunedFreqHz == 7_010_000)
        #expect(rigApp.entry.form.freqKHz == "7010.00")
        // A jump of 1 kHz or less is not remembered.
        rig.qsy(7_010_900)
        #expect(rig.tuning.previousFreqHz == 14_025_000)
    }

    /// Ctrl+PgUp/PgDn: the next band's segment start of the mode, back to the last frequency on a band; outside a
    /// contest without WARC.
    @Test func stepBandGoesToTheLastFrequencyOrTheSegmentStart() async throws {
        let (rigApp, fake) = try await Self.connected()
        let entry: EntryModel = rigApp.entry
        entry.runShortcut(.bandUp)
        #expect(entry.form.freqKHz == "21000.00")
        #expect(rigApp.rig.tuning.tunedFreqHz == 21_000_000)
        #expect(rigApp.rig.tuning.previousFreqHz == 14_025_000)
        entry.runShortcut(.bandDown)
        #expect(entry.form.freqKHz == "14025.00")
        entry.setMode(.ssb)
        entry.runShortcut(.bandDown)
        #expect(entry.form.freqKHz == "7060.00")
        await rigApp.settle()
        #expect(fake.writes == ["F 21000000", "M CW 0", "F 14025000", "M CW 0", "F 7060000", "M LSB 0"])
    }

    /// ↑/↓ step by the mode's step (CW 20 Hz, SSB 100 Hz from the configuration); the wheel rounds with Alt/Ctrl.
    @Test func arrowsAndTheWheelTuneTheRig() async throws {
        let (rigApp, fake) = try await Self.connected()
        let entry: EntryModel = rigApp.entry
        entry.handle(.tune(1))
        #expect(entry.form.freqKHz == "14025.02")
        #expect(rigApp.rig.tuning.tunedFreqHz == 14_025_020)
        entry.handle(.tune(-1))
        #expect(entry.form.freqKHz == "14025.00")
        entry.wheel(direction: 1, alt: true, ctrl: false)
        #expect(entry.form.freqKHz == "14026.00")
        entry.wheel(direction: -1, alt: false, ctrl: true)
        #expect(entry.form.freqKHz == "14020.00")
        entry.setMode(.ssb)
        entry.wheel(direction: 1, alt: false, ctrl: false)
        #expect(entry.form.freqKHz == "14020.10")
        // The previous frequency is untouched by the arrows and the wheel.
        #expect(rigApp.rig.tuning.previousFreqHz == 0)
        await rigApp.settle()
        #expect(fake.writes == ["F 14025020", "F 14025000", "F 14026000", "F 14020000", "F 14020100"])
        // Without a frequency nothing happens.
        entry.setFrequency("")
        entry.handle(.tune(1))
        #expect(entry.form.freqKHz == "")
    }

    /// The loop guard (`EP:186-196`): typing into the field moves the shared frequency but never tunes CAT; a QSY
    /// from elsewhere (the bandmap) brings the field along.
    @Test func typingNeverTunesTheRigAndTheFieldFollowsTheSharedFrequency() async throws {
        let (rigApp, fake) = try await Self.connected()
        let entry: EntryModel = rigApp.entry
        entry.setFrequency("14030")
        #expect(rigApp.rig.tuning.tunedFreqHz == 14_030_000)
        #expect(rigApp.rig.tuning.lastFrequency(on: .m20) == 14_030_000)
        entry.setFrequency("7015.5")
        #expect(rigApp.rig.tuning.tunedFreqHz == 7_015_500)
        await rigApp.settle()
        #expect(fake.writes.isEmpty)
        rigApp.rig.qsy(21_010_000)
        #expect(entry.form.freqKHz == "21010.00")
        // A rounded field (10 Hz) settles on the field's value, as Kotlin's field effect does.
        rigApp.rig.qsy(21_010_005)
        #expect(entry.form.freqKHz == "21010.01")
        #expect(rigApp.rig.tuning.tunedFreqHz == 21_010_010)
    }

    /// Only the active entry window follows the rig (`if (!active) return`): in SO2V with VFO B active the main
    /// window keeps its field.
    @Test func onlyTheActiveWindowFollowsTheRig() async throws {
        let (rigApp, fake) = try await Self.connected { config in
            config.radioMode = "SO2V"
        }
        let rig: MCLAppModel.RigModel = rigApp.rig
        #expect(rigApp.entry.isActivePanel)
        rig.activateVfo(1)
        #expect(!rigApp.entry.isActivePanel)
        await rigApp.settle()
        #expect(rigApp.status == "Aktivní VFO B")
        fake.setFrequency(7_020_000)
        rig.toggle(vfo: 1)
        await eventually("disconnected") { !rig.cat1.connected }
        rig.toggle(vfo: 1)
        await eventually("state again") { rig.cat1.state?.freqHz == 7_020_000 }
        #expect(rigApp.entry.form.freqKHz == "14025.00")
        // VFO A again: its frequency comes back and the window follows the rig.
        rig.activateVfo(0)
        #expect(rigApp.entry.isActivePanel)
        #expect(rigApp.entry.form.freqKHz == "7020.00")
    }

    /// A multi-mode contest takes the rig's mode once when it starts (`state.cat.state?.mode()`).
    @Test func aMultiModeContestTakesTheRigsModeOnce() async throws {
        let (rigApp, _) = try await Self.connected(mode: "CW")
        rigApp.entry.setMode(.ssb)
        var setup = ContestSetup()
        setup.sentExchange = ["exch": "28"]
        let started: Bool = await rigApp.model.contest.createAndStart(definitionId: "iaru-hf", setup: setup)
        try #require(started)
        #expect(rigApp.entry.form.mode == .cw)
        rigApp.entry.setMode(.ssb)
        #expect(rigApp.entry.form.mode == .ssb)
    }

    /// The rig's mode follows Mode Control when the rig is followed (not in a single-mode contest).
    @Test func theFollowedModeIsTheLoggedMode() async throws {
        let (rigApp, _) = try await Self.connected(mode: "USB") { config in
            config.modeRule = "ALWAYS"
            config.modeAlways = "RTTY"
        }
        #expect(rigApp.entry.form.mode == .rtty)
    }
}
