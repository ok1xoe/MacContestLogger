import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM „Grab Focus From Other Apps When Radio Is Tuned" and „Snap windows to edges" in the model: the menu switches
/// (off by default, saved), and a focus request only when the operator tunes the radio (fake `rigctld` on 127.0.0.1),
/// never for the app's own QSY.
@MainActor @Suite struct FocusGrabTests {

    private static func connected(grab: Bool) async throws -> (RigApp, FakeRigctld) {
        let fake = try FakeRigctld(freqHz: 14_025_000, mode: "CW")
        // The CAT session polls the fake often; the test waits for the polled state, never for a time.
        let rigApp = try await RigApp.make(configure: { config, _ in
            config.rig = fakeRigConfig(fake.port)
            var setup = WindowSetup()
            setup.set(.grabFocusOnTune, flag: grab)
            config.window = setup
        }, pollIntervalMs: 20)
        await rigApp.connect()
        return (rigApp, fake)
    }

    @Test func theOperatorsTuningRequestsTheFocus() async throws {
        let (rigApp, fake) = try await Self.connected(grab: true)
        let rig: MCLAppModel.RigModel = rigApp.rig
        #expect(rig.focusGrabRequest == nil)
        // The app's own QSY: no request.
        rig.qsy(7_010_000)
        await eventually("rig on 40 m") { rig.cat1.state?.freqHz == 7_010_000 }
        await rigApp.settle()
        #expect(rig.focusGrabRequest == nil)
        // The knob.
        fake.setFrequency(7_012_500)
        await eventually("rig tuned") { rig.cat1.state?.freqHz == 7_012_500 }
        #expect(rig.focusGrabRequest?.vfo == 0)
        let first: FocusGrabRequest? = rig.focusGrabRequest
        rig.focusGrabRequest = nil
        fake.setFrequency(7_013_000)
        await eventually("rig tuned again") { rig.cat1.state?.freqHz == 7_013_000 }
        #expect(rig.focusGrabRequest?.vfo == 0)
        #expect(rig.focusGrabRequest != first)
    }

    @Test func offByDefault() async throws {
        let (rigApp, fake) = try await Self.connected(grab: false)
        fake.setFrequency(14_030_000)
        await eventually("rig tuned") { rigApp.rig.cat1.state?.freqHz == 14_030_000 }
        #expect(rigApp.rig.focusGrabRequest == nil)
        #expect(!AppConfig().window.flag(.grabFocusOnTune))
        #expect(!AppConfig().window.flag(.snapWindows))
    }

    @Test func menuSwitchesAreSaved() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        for (id, key) in [("settings.grabFocus", WindowSetup.Key.grabFocusOnTune),
                          ("settings.snapWindows", WindowSetup.Key.snapWindows)] {
            #expect(!MenuActions.isChecked(id, app: model))
            #expect(MenuActions.perform(id, app: model) == nil)
            #expect(MenuActions.isChecked(id, app: model))
            #expect(model.config.config.window.flag(key))
            _ = MenuActions.perform(id, app: model)
            #expect(!MenuActions.isChecked(id, app: model))
        }
    }
}
