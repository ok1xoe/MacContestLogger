import Foundation
import MCLCore
import Observation

/// The serial peripherals of v1.1.1: the N1MM footswitch (`AS:636-665`) and the OTRSP SO2R controller
/// (`AS:2259-2307`). Opening, closing and every command run on the peripherals lane; the handles live
/// only there. The main actor keeps what the UI and the rig model read: whether OTRSP is open and the press counter.
@Observable @MainActor
public final class PeripheralsModel {

    /// Kotlin `footswitchPresses`: raised by a press with the action ENTER or F1 (the active entry window acts).
    public private(set) var footswitchPresses: Int = 0
    /// An OTRSP controller is open (Kotlin `otrsp != null`), as last reported by the lane.
    public private(set) var otrspOpen: Bool = false

    /// The footswitch changed (`pressed`), on the main actor; wired by the app to the rig model's PTT and the
    /// entry windows.
    @ObservationIgnored var onFootswitch: @MainActor (Bool) -> Void = { _ in }
    /// Observers of `footswitchPresses` (the entry windows: F1 or Enter in the active one).
    @ObservationIgnored var pressObservers: [@MainActor () -> Void] = []
    /// Runs before the footswitch closes (a reload, the quit): wired to release a PTT it holds.
    @ObservationIgnored var beforeFootswitchCloses: @MainActor () -> Void = {}

    /// The handles, touched only on the lane.
    private final class Handles: @unchecked Sendable {
        var footswitch: Footswitch?
        var otrsp: Otrsp?
    }

    @ObservationIgnored private let handles = Handles()
    @ObservationIgnored let lane = SerialLane(name: "peripherals")
    @ObservationIgnored private let hardware: HardwarePorts
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    /// Raised by every reopen of OTRSP: a late open result of an older request is ignored.
    @ObservationIgnored private var otrspGeneration: Int = 0

    init(hardware: HardwarePorts, config: ConfigModel, status: StatusModel) {
        self.hardware = hardware
        self.config = config
        self.status = status
    }

    // MARK: - footswitch

    /// Kotlin `reloadFootswitch()`: the open switch closes; a blank port opens nothing; the pin is
    /// `Pin.valueOf(footswitchPin)` with CTS as the fallback; a failure shows its message, otherwise
    /// `tr("Footswitch nejde otevřít")`.
    public func reloadFootswitch() {
        beforeFootswitchCloses()
        let port: String = config.config.footswitchPort
        let pin: Footswitch.Pin = Footswitch.Pin(rawValue: config.config.footswitchPin) ?? .cts
        let handles: Handles = self.handles
        let hardware: HardwarePorts = self.hardware
        lane.submit({ [weak self] () -> EntryStatus? in
            handles.footswitch?.close()
            handles.footswitch = nil
            if KotlinStrings.isBlank(port) {
                return nil
            }
            do {
                handles.footswitch = try hardware.openFootswitch(port, pin) { [weak self] pressed in
                    MainHop.post {
                        self?.onFootswitch(pressed)
                    }
                }
                return nil
            } catch {
                return RigTexts.footswitchFailure(Self.message(error))
            }
        }, then: { [weak self] failure in
            if let failure {
                self?.show(failure)
            }
        })
    }

    /// A press with the action ENTER or F1 (Kotlin `footswitchPresses++`).
    func footswitchPressed() {
        footswitchPresses += 1
        for observer in pressObservers {
            observer()
        }
    }

    // MARK: - OTRSP

    /// The OTRSP part of `syncRadioModeFromConfig()`: the open controller closes; `portPath` (SO2R with a port)
    /// opens a new one, a failure shows `"SO2R: <message>"`.
    func reopenOtrsp(_ portPath: String?) {
        otrspGeneration += 1
        let generation: Int = otrspGeneration
        otrspOpen = false
        let handles: Handles = self.handles
        let hardware: HardwarePorts = self.hardware
        lane.submit({ () -> Result<Bool, OtrspFailure> in
            handles.otrsp?.close()
            handles.otrsp = nil
            guard let portPath else { return .success(false) }
            do {
                handles.otrsp = try hardware.openOtrsp(portPath)
                return .success(true)
            } catch {
                return .failure(OtrspFailure(message: Self.message(error)))
            }
        }, then: { [weak self] result in
            guard let self, generation == self.otrspGeneration else { return }
            switch result {
            case .success(let open):
                self.otrspOpen = open
            case .failure(let failure):
                self.otrspOpen = false
                self.show(RigTexts.so2rOpenFailure(failure.message))
            }
        })
    }

    struct OtrspFailure: Error, Sendable {
        let message: String?
    }

    /// `o.focus(rig, stereo)` on the lane (errors ignored, Kotlin `runCatching`).
    func otrspFocus(rig: Int, stereo: Bool) {
        let handles: Handles = self.handles
        lane.submit {
            try? handles.otrsp?.focus(Int32(truncatingIfNeeded: rig), stereo: stereo)
        }
    }

    /// `otrsp?.rx(rig, stereo)` (Kotlin on the UI thread; here on the lane).
    func otrspRx(rig: Int, stereo: Bool) {
        let handles: Handles = self.handles
        lane.submit {
            try? handles.otrsp?.rx(Int32(truncatingIfNeeded: rig), stereo: stereo)
        }
    }

    /// `o.aux(port, code)` of an antenna (errors ignored).
    func otrspAux(port: Int, code: Int) {
        let handles: Handles = self.handles
        lane.submit {
            try? handles.otrsp?.aux(Int32(truncatingIfNeeded: port), value: Int32(truncatingIfNeeded: code))
        }
    }

    // MARK: - lifecycle

    /// Waits for the work queued on the lane (tests, quit).
    func settle() async {
        await lane.settle()
    }

    /// Quit: the footswitch and OTRSP close (Kotlin leaves them open).
    func shutdown() async {
        beforeFootswitchCloses()
        otrspGeneration += 1
        otrspOpen = false
        let handles: Handles = self.handles
        lane.submit {
            handles.footswitch?.close()
            handles.footswitch = nil
            handles.otrsp?.close()
            handles.otrsp = nil
        }
        await lane.settle()
    }

    private func show(_ message: EntryStatus) {
        status.showJoined(message.parts, separator: "")
    }

    /// Kotlin `it.message` (`null` → `nil`).
    nonisolated static func message(_ error: any Error) -> String? {
        if error is InertHardwareError {
            return InertHardwareError.message
        }
        return ErrorText.message(error)
    }
}
