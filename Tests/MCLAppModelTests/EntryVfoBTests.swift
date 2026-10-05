import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The VFO B / rig 2 entry window (`entry-vfob`; Kotlin `EntryPanel(state, vfo = 1)`): its model follows
/// the rig only while shown and active, the typed call is the active window's, the footswitch and the wheel act in the
/// active window only, and only the active window's CQ repeat loop runs — a hidden one never presses
/// F1.
@MainActor @Suite struct EntryVfoBTests {

    /// SO1V: the VFO B model exists but is never the active panel — the rig is followed by the main window only, and
    /// the footswitch's F1 is sent once.
    @Test func hiddenWindowIsInert() async throws {
        let fake = try FakeRigctld(freqHz: 14_025_000)
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port)
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "F1"
        }
        let second: EntryModel = rigApp.model.vfoB.entry
        #expect(second.vfo == 1)
        #expect(second.rig === rigApp.rig)
        #expect(rigApp.entry.isActivePanel)
        #expect(!second.isActivePanel)
        await rigApp.connect()
        await rigApp.settle()
        #expect(rigApp.entry.form.freqKHz == "14025.00")
        #expect(second.form.freqKHz.isEmpty)
        rigApp.entry.setMode(.cw)
        second.setFrequency("7010")
        second.setMode(.cw)
        rigApp.hardware.press(true)
        await eventually("press") { rigApp.model.peripherals.footswitchPresses == 1 }
        rigApp.hardware.press(false)
        await runMainQueue()
        #expect(rigApp.keyer.keys == [[0]])
    }

    /// SO2V: only the window of the active VFO follows the rig; the typed call (antenna azimuth) is the active
    /// window's; the footswitch reaches the active window only.
    @Test func activeWindowFollowsTheRig() async throws {
        let fake = try FakeRigctld(freqHz: 14_025_000)
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2V"
            config.rig = fakeRigConfig(fake.port)
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "F1"
        }
        let rig: MCLAppModel.RigModel = rigApp.rig
        let second: EntryModel = rigApp.model.vfoB.entry
        #expect(rig.vfo.twoEntryWindows)
        // Its window is not on screen yet: never active, even as the active VFO.
        #expect(!second.isWindowShown)
        rig.activateVfo(1)
        #expect(!second.isActivePanel)
        rig.activateVfo(0)
        second.isWindowShown = true
        #expect(rigApp.entry.isActivePanel && !second.isActivePanel)
        rigApp.entry.callChanged("DL1ABC")
        second.callChanged("OK1XYZ")
        #expect(rig.typedCall() == "DL1ABC")
        rig.activateVfo(1)
        #expect(second.isActivePanel && !rigApp.entry.isActivePanel)
        #expect(rig.typedCall() == "OK1XYZ")
        await rigApp.connect(vfo: 1)
        await rigApp.settle()
        #expect(second.form.freqKHz == "14025.00")
        #expect(rigApp.entry.form.freqKHz.isEmpty)
        second.setMode(.cw)
        rigApp.entry.setFrequency("7010")
        rigApp.entry.setMode(.cw)
        rigApp.hardware.press(true)
        await eventually("press") { rigApp.model.peripherals.footswitchPresses == 1 }
        rigApp.hardware.press(false)
        await runMainQueue()
        #expect(rigApp.keyer.keys == [[0]])
    }

    /// The wheel tunes in the active window only (a safety divergence: Kotlin QSYs the active rig to the inactive
    /// window's frequency ± a step).
    @Test func wheelActsInTheActiveWindowOnly() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2V"
        }
        let second: EntryModel = rigApp.model.vfoB.entry
        second.isWindowShown = true
        rigApp.entry.setMode(.cw)
        rigApp.entry.setFrequency("14025")
        second.setMode(.cw)
        second.setFrequency("7010")
        let mainField: String = rigApp.entry.form.freqKHz
        let secondField: String = second.form.freqKHz
        second.wheel(direction: 1, alt: true, ctrl: false)
        #expect(second.form.freqKHz == secondField)
        #expect(rigApp.entry.form.freqKHz == mainField)
        rigApp.entry.wheel(direction: 1, alt: true, ctrl: false)
        #expect(rigApp.entry.form.freqKHz == "14026.00")
        rigApp.rig.activateVfo(1)
        second.wheel(direction: -1, alt: true, ctrl: false)
        #expect(second.form.freqKHz == "7009.00")
    }

    /// A contest activation reaches both windows (Kotlin: both panels follow `contest.activeId`): a single-mode
    /// contest locks the mode of each.
    @Test func contestActivationReachesBothWindows() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2V"
        }
        let second: EntryModel = rigApp.model.vfoB.entry
        rigApp.entry.setMode(.ssb)
        second.setMode(.ssb)
        try await rigApp.app.startCqWwCw()
        #expect(rigApp.entry.form.mode == .cw)
        #expect(second.form.mode == .cw)
        #expect(!second.fields.isEmpty)
    }
}

/// The CQ repeat loops of the two entry windows (`EP:757-768` per panel).
@MainActor @Suite struct EntryVfoBCqRepeatTests {

    private static func make(radioMode: String) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.runMode.repeatSeconds = 2.0
            config.radioMode = radioMode
        })
        for entry in [app.entry, app.model.vfoB.entry] {
            entry.setMode(.cw)
            entry.setFrequency("14025")
        }
        return app
    }

    private static func sends(_ app: KeyingApp) -> Int {
        (app.keying.lastKeyer?.events ?? []).filter { $0.hasPrefix("send ") }.count
    }

    /// The inactive window's loop never calls CQ — with the operator's call typed in the active
    /// window (the repeat paused there), the blank VFO B window sends nothing however long it waits.
    @Test func inactiveWindowNeverCallsCq() async throws {
        let app = try await Self.make(radioMode: "SO2V")
        app.model.vfoB.entry.isWindowShown = true
        app.entry.callChanged("DL1")
        app.entry.runShortcut(.cqRepeat)
        await runMainQueue()
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(app.keying.openedKeyers.isEmpty)
        #expect(app.model.operating.cqRepeat)
    }

    /// The loop follows `activeVfo`: activating VFO B starts it in the VFO B window (blank call → F1), back on VFO A
    /// it pauses for A's typed call; VFO B's window closing (or SO1V) leaves it idle.
    @Test func loopFollowsTheActiveWindow() async throws {
        let app = try await Self.make(radioMode: "SO2V")
        let rig: MCLAppModel.RigModel = app.model.rig
        let second: EntryModel = app.model.vfoB.entry
        second.isWindowShown = true
        app.entry.callChanged("DL1")
        app.entry.runShortcut(.cqRepeat)
        await runMainQueue()
        await app.settle()
        #expect(Self.sends(app) == 0)
        rig.activateVfo(1)
        await runMainQueue()
        await app.settle()
        #expect(Self.sends(app) == 1)
        rig.activateVfo(0)
        await runMainQueue()
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(Self.sends(app) == 1)
        rig.activateVfo(1)
        await runMainQueue()
        await app.settle()
        #expect(Self.sends(app) == 2)
        second.isWindowShown = false
        await runMainQueue()
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(Self.sends(app) == 2)
        #expect(app.model.operating.cqRepeat)
    }

    /// SO1V: one loop only — a blank call in the hidden VFO B model sends nothing (the main window's typed call
    /// pauses the only loop).
    @Test func hiddenWindowNeverCallsCq() async throws {
        let app = try await Self.make(radioMode: "SO1V")
        app.entry.callChanged("DL1")
        app.entry.runShortcut(.cqRepeat)
        await runMainQueue()
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(app.keying.openedKeyers.isEmpty)
        #expect(app.model.operating.cqRepeat)
    }

    /// With two windows: only the active window's loop runs, so a VFO B window in a mode that cannot be keyed
    /// does not stop the repeat VFO A runs; once VFO B is active its loop stops it.
    @Test func notKeyableInactiveWindowDoesNotStopTheRepeat() async throws {
        let app = try await Self.make(radioMode: "SO2V")
        app.model.vfoB.entry.isWindowShown = true
        app.model.vfoB.entry.setMode(.rtty)
        #expect(app.model.vfoB.entry.form.mode == .rtty)
        #expect(app.model.rig.vfo.twoEntryWindows)
        #expect(app.model.cqRepeatRunnerB != nil)
        app.entry.runShortcut(.cqRepeat)
        #expect(app.model.operating.cqRepeat)
        await runMainQueue()
        await app.settle()
        #expect(app.model.operating.cqRepeat)
        #expect(Self.sends(app) == 1)
        app.model.rig.activateVfo(1)
        await runMainQueue()
        #expect(!app.model.operating.cqRepeat)
        #expect(app.status == "Opakování CQ vypnuto")
    }
}

/// The info strip's rig and keyer items (`EP:1282-1290`).
@MainActor @Suite struct InfoStripRigItemsTests {

    /// ● REC follows the contest recording.
    @Test func recordingShowsRec() async throws {
        let app = try await KeyingApp.make(configure: { config, dataDir in
            config.recordingsDir = dataDir.appendingPathComponent("rec").path
        })
        #expect(app.model.infoStrip.text.isEmpty)
        await app.model.recording.setRecording(true)
        #expect(app.model.infoStrip.text == " ● REC")
        await app.model.recording.setRecording(false)
        await app.settle()
        #expect(app.model.infoStrip.text.isEmpty)
    }

    /// RIT shows the last offset the rig accepted, with its sign; 0 hides it.
    @Test func ritShowsTheOffset() async throws {
        let (rigApp, _) = try await RigTuningTests.connected()
        rigApp.rig.setRit(120)
        await rigApp.settle()
        #expect(rigApp.model.infoStrip.text == " RIT +120")
        rigApp.rig.setRit(-40)
        await rigApp.settle()
        #expect(rigApp.model.infoStrip.text == " RIT -40")
        rigApp.rig.setRit(0)
        await rigApp.settle()
        #expect(rigApp.model.infoStrip.text.isEmpty)
    }
}
