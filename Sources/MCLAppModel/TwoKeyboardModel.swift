import Foundation
import MCLCore
import Observation

/// macOS „Input Monitoring" for the app: reading which keyboard a key came from needs it.
public enum KeyboardAccess: Sendable, Equatable {
    case granted
    case denied
    case undetermined
}

/// The HID side of N1MM „Two Keyboards": the attached keyboards and their key presses with the keyboard they came
/// from (IOKit's HID manager in the app; tests use a fake — no test reads a real input device). `start` reports
/// presses on any thread until `stop`.
public protocol KeyboardDeviceSource: AnyObject, Sendable {
    var access: KeyboardAccess { get }
    /// Asks macOS for Input Monitoring (the system shows its prompt once); `true` = granted now.
    func requestAccess() -> Bool
    /// The keyboards attached now.
    func keyboards() -> [KeyboardDevice]
    /// Starts reporting key presses; `false` = the HID manager could not be opened.
    func start(_ onPress: @escaping @Sendable (HidKeyPress) -> Void) -> Bool
    func stop()
}

/// N1MM Config → SO2R → „Two Keyboards" (Nastavení → SO2R → Dvě klávesnice, off by default): with two entry windows
/// each keyboard drives its own window — a key typed on keyboard 1 goes to the left (radio 1 / VFO A) window, one
/// typed on keyboard 2 to the right window, whichever window has the focus. `\` typed on a keyboard only moves the
/// focus to its window; the Pause key (F15) does nothing (N1MM: no longer needed). Which keyboard is which: the
/// saved assignment, otherwise the first keyboard typed on is keyboard 1 (N1MM).
///
/// It needs macOS Input Monitoring; without it the option says so and the keys stay with the focused window.
@Observable @MainActor
public final class TwoKeyboardModel {

    /// What the key monitor does with a key event.
    public enum Route: Equatable, Sendable {
        /// Not routed: the focused window handles it as usual.
        case none
        /// The key belongs to entry window `window`.
        case window(Int)
        /// `\` on the keyboard of entry window `window`: the focus moves there, the key itself is dropped.
        case focusOnly(Int)
        /// Dropped (the Pause key).
        case drop
    }

    /// The keyboards attached (refreshed by `refreshDevices`).
    public private(set) var devices: [KeyboardDevice] = []
    /// The keyboard of the last press (the settings window's test).
    public private(set) var lastPressedDevice: String?
    /// Input Monitoring as last checked.
    public private(set) var access: KeyboardAccess = .undetermined
    /// The HID side is running.
    public private(set) var isRunning = false
    /// The setup window is open: keys are not moved, their keyboard is only shown.
    public private(set) var isTesting = false

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let rig: RigModel
    @ObservationIgnored private let source: (any KeyboardDeviceSource)?
    @ObservationIgnored private let inbox = PressInbox()
    @ObservationIgnored private var router = TwoKeyboardRouter()
    /// The routes of the last events, so each entry window's key monitor gets the same answer for one event.
    @ObservationIgnored private var recent: [(key: EventKey, route: Route)] = []

    /// One key event (the window server's timestamp, key code and kind).
    public struct EventKey: Equatable, Sendable {
        public let timestamp: Double
        public let keyCode: UInt16
        public let down: Bool

        public init(timestamp: Double, keyCode: UInt16, down: Bool) {
            self.timestamp = timestamp
            self.keyCode = keyCode
            self.down = down
        }
    }

    public init(config: ConfigModel, status: StatusModel, rig: RigModel, source: (any KeyboardDeviceSource)?) {
        self.config = config
        self.status = status
        self.rig = rig
        self.source = source
        loadAssignment()
        observeConfig()
    }

    /// The option and the assignment follow the saved setup (the menu, a profile, the setup window).
    private func observeConfig() {
        withObservationTracking {
            _ = config.config.so2rSetup
        } onChange: { [weak self] in
            MainHop.post {
                guard let self else { return }
                self.observeConfig()
                self.configChanged()
            }
        }
    }

    private func configChanged() {
        let setup: So2rSetup = config.config.so2r
        if setup.text(.keyboard1) != (router.saved[0] ?? "") || setup.text(.keyboard2) != (router.saved[1] ?? "") {
            loadAssignment()
        }
        if isEnabled && !isRunning {
            start()
        } else if !isEnabled && isRunning && !isTesting {
            stop()
        }
    }

    /// The option is on (saved).
    public var isEnabled: Bool {
        config.config.so2r.flag(.twoKeyboards)
    }

    /// Two entry windows are on screen and the option is on.
    public var isActive: Bool {
        isEnabled && isRunning && rig.vfo.twoEntryWindows
    }

    /// The saved keyboard of entry window `window` (0 / 1), `nil` = none.
    public func savedKeyboard(window: Int) -> String? {
        router.saved.indices.contains(window) ? router.saved[window] : nil
    }

    /// The window keyboard `id` drives now (saved or found this run).
    public func window(of id: String) -> Int? {
        router.window(of: id)
    }

    /// The keyboard that drives entry window `window` now (saved or found this run).
    public func keyboard(window: Int) -> String? {
        router.keyboard(window: window)
    }

    /// The name of keyboard `id` (its id when it is not attached).
    public func name(of id: String) -> String {
        devices.first { $0.id == id }?.name ?? id
    }

    // MARK: - switching

    /// Starts the HID side when the option is on (the app's start, the option switched on).
    public func start() {
        guard isEnabled || isTesting, !isRunning, let source else { return }
        access = source.access
        if access != .granted {
            access = source.requestAccess() ? .granted : source.access
        }
        guard access == .granted else {
            status.show("Dvě klávesnice: povol aplikaci Sledování vstupu (Nastavení systému → Soukromí a zabezpečení)")
            return
        }
        let inbox: PressInbox = self.inbox
        // The presses wait in the inbox for the key events; the main actor also takes them as soon as it can.
        guard source.start({ [weak self] press in
            inbox.add(press)
            MainHop.post { self?.drainPresses() }
        }) else {
            status.show("Dvě klávesnice: klávesnice nelze číst")
            return
        }
        isRunning = true
        refreshDevices()
    }

    /// The setup window opened: the HID side runs (also with the option off) so a key shows its keyboard.
    public func beginTest() {
        isTesting = true
        lastPressedDevice = nil
        start()
        refreshDevices()
    }

    /// The setup window closed.
    public func endTest() {
        isTesting = false
        if !isEnabled {
            stop()
        }
    }

    /// Takes the presses reported meanwhile (the test line follows them).
    public func drainPresses() {
        for press in inbox.take() {
            router.pressed(press)
            lastPressedDevice = press.deviceId
        }
    }

    public func stop() {
        guard isRunning else { return }
        source?.stop()
        isRunning = false
        _ = inbox.take()
        router.reset()
        recent = []
    }

    /// The option on / off (saved; the menu item and the setup window). Switching on starts the HID side at once,
    /// so a missing Input Monitoring permission is reported right away.
    public func toggle() {
        var setup: So2rSetup = config.config.so2r
        let on: Bool = !setup.flag(.twoKeyboards)
        setup.set(.twoKeyboards, flag: on)
        config.config.so2r = setup
        config.save(failureKey: "Uložení nastavení selhalo: %s")
        if on {
            start()
            if isRunning {
                status.show("Dvě klávesnice zapnuty — klávesnice 1 ovládá levé okno, klávesnice 2 pravé")
            }
        } else {
            if !isTesting {
                stop()
            }
            status.show("Dvě klávesnice vypnuty")
        }
    }

    public func refreshDevices() {
        devices = source?.keyboards() ?? []
        if let source {
            access = source.access
        }
    }

    /// Saves keyboard `id` as the one of entry window `window` (`nil` = none; a keyboard drives one window only).
    public func assign(_ id: String?, window: Int) {
        guard window == 0 || window == 1 else { return }
        var setup: So2rSetup = config.config.so2r
        let keys: [So2rSetup.Key] = [.keyboard1, .keyboard2]
        if let id, setup.text(keys[1 - window]) == id {
            setup.set(keys[1 - window], "")
        }
        setup.set(keys[window], id ?? "")
        config.config.so2r = setup
        config.save(failureKey: "Uložení nastavení selhalo: %s")
        loadAssignment()
    }

    private func loadAssignment() {
        let setup: So2rSetup = config.config.so2r
        router = TwoKeyboardRouter(keyboard1: setup.text(.keyboard1), keyboard2: setup.text(.keyboard2))
        recent = []
    }

    // MARK: - routing

    /// Where the key event goes. Asked by every entry window's key monitor for the same event; the answer is
    /// computed once. Key downs and ups only (modifier changes are not routed).
    public func route(_ key: EventKey, isRepeat: Bool) -> Route {
        if let known = recent.first(where: { $0.key == key }) {
            return known.route
        }
        let route: Route = compute(key, isRepeat: isRepeat)
        recent.append((key, route))
        if recent.count > 8 {
            recent.removeFirst(recent.count - 8)
        }
        return route
    }

    private func compute(_ key: EventKey, isRepeat: Bool) -> Route {
        drainPresses()
        guard isActive, !isTesting else { return .none }
        let window: Int?
        if key.down {
            window = router.keyDown(keyCode: key.keyCode, isRepeat: isRepeat)
        } else {
            window = router.keyUp(keyCode: key.keyCode)
        }
        guard let window else { return .none }
        if key.keyCode == Self.backslashKeyCode {
            return key.down ? .focusOnly(window) : .drop
        }
        if key.keyCode == Self.pauseKeyCode {
            return .drop
        }
        return .window(window)
    }

    /// `kVK_ANSI_Backslash`.
    static let backslashKeyCode: UInt16 = 0x2A
    /// `kVK_F15` — a PC keyboard's Pause key.
    static let pauseKeyCode: UInt16 = 0x71

    /// Collects the presses the HID side reports on its own thread until the main actor takes them.
    private final class PressInbox: @unchecked Sendable {
        private let lock = NSLock()
        private var presses: [HidKeyPress] = []

        func add(_ press: HidKeyPress) {
            lock.withLock {
                presses.append(press)
                if presses.count > TwoKeyboardRouter.pendingLimit {
                    presses.removeFirst(presses.count - TwoKeyboardRouter.pendingLimit)
                }
            }
        }

        func take() -> [HidKeyPress] {
            lock.withLock {
                let taken: [HidKeyPress] = presses
                presses = []
                return taken
            }
        }
    }
}
