import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// A keyboard source that reads no device: the test reports presses and sets the Input Monitoring answer.
final class FakeKeyboardSource: KeyboardDeviceSource, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (HidKeyPress) -> Void)?
    var accessAnswer: KeyboardAccess = .granted
    var grantsOnRequest = false
    var attached: [KeyboardDevice] = []
    private(set) var starts = 0
    private(set) var stops = 0

    var access: KeyboardAccess { lock.withLock { accessAnswer } }

    func requestAccess() -> Bool {
        lock.withLock {
            if grantsOnRequest {
                accessAnswer = .granted
            }
            return accessAnswer == .granted
        }
    }

    func keyboards() -> [KeyboardDevice] { lock.withLock { attached } }

    func start(_ onPress: @escaping @Sendable (HidKeyPress) -> Void) -> Bool {
        lock.withLock {
            handler = onPress
            starts += 1
        }
        return true
    }

    func stop() {
        lock.withLock {
            handler = nil
            stops += 1
        }
    }

    var isStarted: Bool { lock.withLock { handler != nil } }

    func press(_ device: String, usage: UInt32) {
        let handler: (@Sendable (HidKeyPress) -> Void)? = lock.withLock { self.handler }
        handler?(HidKeyPress(deviceId: device, usage: usage))
    }
}

/// N1MM „Two Keyboards" in the model: off by default, Input Monitoring asked for and its refusal explained, keys
/// routed to the entry window of their keyboard (`\` only moves the focus, Pause is dropped), the setup window's test
/// and the saved assignment. A fake keyboard source; no input device is read.
@MainActor @Suite struct TwoKeyboardModelTests {

    private static let left = "05AC:0250:00100000"
    private static let right = "046D:C31C:00200000"

    private static func make(enabled: Bool = true, so2r: Bool = true,
                             source: FakeKeyboardSource = FakeKeyboardSource()) async throws
        -> (TestApp, TwoKeyboardModel, FakeKeyboardSource) {
        let app = try await TestApp.make(configure: { config, _ in
            config.radioMode = so2r ? "SO2R" : "SO1V"
            var setup: So2rSetup = config.so2r
            setup.set(.twoKeyboards, flag: enabled)
            config.so2r = setup
        })
        source.attached = [KeyboardDevice(id: left, name: "Apple Keyboard"), KeyboardDevice(id: right, name: "PC")]
        let model = TwoKeyboardModel(config: app.model.config, status: app.model.status, rig: app.model.rig,
                                     source: source)
        model.start()
        return (app, model, source)
    }

    private static func key(_ code: UInt16, _ time: Double, down: Bool = true) -> TwoKeyboardModel.EventKey {
        TwoKeyboardModel.EventKey(timestamp: time, keyCode: code, down: down)
    }

    @Test func offByDefault() async throws {
        #expect(!AppConfig().so2r.flag(.twoKeyboards))
        let (_, model, source) = try await Self.make(enabled: false)
        #expect(!model.isRunning)
        #expect(source.starts == 0)
        #expect(model.route(Self.key(0x00, 1), isRepeat: false) == .none)
    }

    @Test func aRefusedPermissionIsExplained() async throws {
        let source = FakeKeyboardSource()
        source.accessAnswer = .denied
        let (app, model, _) = try await Self.make(source: source)
        #expect(!model.isRunning)
        #expect(model.access == .denied)
        #expect(source.starts == 0)
        #expect(app.model.status.message.contains("Sledování vstupu"))
        // Granted at the prompt: it runs.
        let asking = FakeKeyboardSource()
        asking.accessAnswer = .undetermined
        asking.grantsOnRequest = true
        let (_, granted, _) = try await Self.make(source: asking)
        #expect(granted.isRunning)
    }

    @Test func eachKeyboardDrivesItsWindow() async throws {
        let (app, model, source) = try await Self.make()
        app.model.vfoB.entry.isWindowShown = true
        #expect(model.isActive)
        source.press(Self.left, usage: 0x04)
        source.press(Self.right, usage: 0x05)
        // The first keyboard typed on is window 1 (N1MM), the other window 2.
        #expect(model.route(Self.key(0x00, 1), isRepeat: false) == .window(0))
        #expect(model.route(Self.key(0x0B, 2), isRepeat: false) == .window(1))
        // Both entry windows' monitors ask: the same event has the same answer.
        #expect(model.route(Self.key(0x0B, 2), isRepeat: false) == .window(1))
        #expect(model.route(Self.key(0x0B, 3, down: false), isRepeat: false) == .window(1))
        // `\` only moves the focus; Pause (F15) is dropped.
        source.press(Self.right, usage: 0x31)
        #expect(model.route(Self.key(0x2A, 4), isRepeat: false) == .focusOnly(1))
        #expect(model.route(Self.key(0x2A, 5, down: false), isRepeat: false) == .drop)
        source.press(Self.left, usage: 0x48)
        #expect(model.route(Self.key(0x71, 6), isRepeat: false) == .drop)
        // One radio: nothing is routed.
        let (_, single, singleSource) = try await Self.make(so2r: false)
        singleSource.press(Self.left, usage: 0x04)
        #expect(single.route(Self.key(0x00, 1), isRepeat: false) == .none)
    }

    @Test func theSetupWindowTestsAndAssigns() async throws {
        let (app, model, source) = try await Self.make()
        model.beginTest()
        #expect(model.devices.count == 2)
        source.press(Self.right, usage: 0x04)
        // While the window is open nothing is moved; the key's keyboard is shown.
        #expect(model.route(Self.key(0x00, 1), isRepeat: false) == .none)
        #expect(model.lastPressedDevice == Self.right)
        model.assign(Self.right, window: 0)
        #expect(app.model.config.config.so2r.text(.keyboard1) == Self.right)
        // A keyboard drives one window only.
        model.assign(Self.right, window: 1)
        #expect(app.model.config.config.so2r.text(.keyboard1) == "")
        #expect(app.model.config.config.so2r.text(.keyboard2) == Self.right)
        #expect(model.window(of: Self.right) == 1)
        model.endTest()
        #expect(model.isRunning)
        model.assign(nil, window: 1)
        #expect(app.model.config.config.so2rSetup["keyboard2"] == nil)
    }

    @Test func theMenuSwitchStartsAndStops() async throws {
        let (app, model, source) = try await Self.make(enabled: false)
        #expect(MenuActions.perform("so2r.twoKeyboards", app: app.model) == nil)
        #expect(MenuActions.isChecked("so2r.twoKeyboards", app: app.model))
        await runMainQueue()
        #expect(model.isRunning)
        #expect(source.isStarted)
        _ = MenuActions.perform("so2r.twoKeyboards", app: app.model)
        await runMainQueue()
        #expect(!model.isRunning)
        #expect(source.stops == 1)
        // The setup window is a window of its own.
        #expect(MenuActions.perform("so2r.keyboards", app: app.model) == nil)
        #expect(app.model.windows.openIds.contains("keyboards"))
    }
}
