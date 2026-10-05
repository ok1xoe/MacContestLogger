import Foundation
import MCLCore
import Observation

/// The CQ repeat loop of the entry window (N1MM Alt+R, `EP:757-768`) over `CqRepeatLoop` and the injected clock:
/// it (re)starts whenever `cqRepeat`, a blank call or a keyable mode change — typing a call pauses it, clearing the
/// call resumes it, Esc switches it off — waits while a message is sent, presses F1, waits 250 ms, waits for the
/// message to end and pauses `repeatSeconds`.
///
/// It switches `cqRepeat` off on the TX lockout, in post-contest entry, in a mode that cannot be keyed
/// and after a failed F1 send (`CqRepeatLoop.sendFailed`), so it never keeps transmitting on its own.
/// with two entry windows only the active window's loop runs (see `enabled`).
@MainActor
final class CqRepeatRunner {

    private struct Keys: Equatable {
        let enabled: Bool
        let callBlank: Bool
        let keyable: Bool
    }

    private var loop = CqRepeatLoop()
    private var timer: (any RescoreTimer)?
    private var keys: Keys?
    /// `keyer.sendFailures` when F1 was pressed; a change means the send failed.
    private var failureBaseline: Int?
    private weak var entry: EntryModel?
    private let operating: OperatingModel
    private let keyer: KeyerModel
    private let config: ConfigModel
    private let status: StatusModel
    private let clock: any RescoreClock
    private var stopped = false
    /// The entry window is shown (the VFO B window only while `twoEntryWindows`; Kotlin's loop lives in the panel's
    /// composition). A hidden window's loop is idle.
    var present: @MainActor () -> Bool = { true }

    init(entry: EntryModel, operating: OperatingModel, keyer: KeyerModel, config: ConfigModel, status: StatusModel,
         clock: any RescoreClock) {
        self.entry = entry
        self.operating = operating
        self.keyer = keyer
        self.config = config
        self.status = status
        self.clock = clock
    }

    /// Starts following the keys.
    func start() {
        observe()
        keysChanged()
    }

    /// The quit: no more F1.
    func stop() {
        stopped = true
        timer?.cancel()
        timer = nil
    }

    /// The loop is waiting for its clock (tests).
    var isScheduled: Bool {
        timer != nil
    }

    private func currentKeys() -> Keys? {
        guard let entry else { return nil }
        let keyable: Bool = CqRepeatLoop.isKeyable(mode: entry.form.mode, digitalReady: keyer.digital.ready)
        return Keys(enabled: enabled(entry), callBlank: KotlinStrings.isBlank(entry.form.call),
                    keyable: keyable)
    }

    /// `cqRepeat` for this window's loop: only while the window is shown, and (safety) only in the
    /// active window. Kotlin runs one loop per panel without an `active` gate, so the inactive window's loop keyed
    /// the active rig/VFO with its own form, also between the messages of the operator's QSO in the other window.
    /// Switching the active window restarts the loop there, with that window's call and mode.
    private func enabled(_ entry: EntryModel) -> Bool {
        operating.cqRepeat && present() && entry.isActivePanel
    }

    private func observe() {
        withObservationTracking {
            _ = currentKeys()
        } onChange: { [weak self] in
            MainHop.post {
                guard let self, !self.stopped else { return }
                self.observe()
                self.keysChanged()
            }
        }
    }

    /// Kotlin `LaunchedEffect(cqRepeat, call.isBlank(), keyable)`: a changed key cancels the loop and starts it again.
    private func keysChanged() {
        let now: Keys? = currentKeys()
        guard now != keys else { return }
        keys = now
        timer?.cancel()
        timer = nil
        failureBaseline = nil
        loop.restart()
        step()
    }

    private func step() {
        timer = nil
        guard !stopped, let entry else { return }
        // No F1 while the entry accepts no input (quitting, a database switch, a contest activation): try again later.
        guard entry.inputGate() else {
            perform(.wait(milliseconds: CqRepeatLoop.idlePollMillis), entry: entry)
            return
        }
        if let baseline = failureBaseline, keyer.sendFailures != baseline {
            failureBaseline = nil
            perform(loop.sendFailed(), entry: entry)
            return
        }
        let keyable: Bool = CqRepeatLoop.isKeyable(mode: entry.form.mode, digitalReady: keyer.digital.ready)
        let inputs = CqRepeatLoop.Inputs(
            enabled: enabled(entry), callBlank: KotlinStrings.isBlank(entry.form.call),
            keyable: keyable,
            isSending: keyer.isSending, postContest: operating.postContest, txLocked: keyer.tx.txGate() != nil,
            repeatSeconds: config.config.runMode.repeatSeconds)
        perform(loop.next(inputs), entry: entry)
    }

    private func perform(_ action: CqRepeatLoop.Action, entry: EntryModel) {
        switch action {
        case .idle:
            failureBaseline = nil
        case .wait(let milliseconds):
            timer = clock.schedule(afterMilliseconds: Int(clamping: milliseconds)) { [weak self] in
                self?.step()
            }
        case .sendF1:
            failureBaseline = keyer.sendFailures
            entry.sendKeys([EsmEngine.f1], refocus: false)
            step()
        case .stop(let reason):
            failureBaseline = nil
            operating.applyCqRepeat(false)
            show(reason)
        }
    }

    /// The status of a stop: the lockout's refusal, the post-contest text, „Opakování CQ vypnuto"; after a
    /// failed send the keyer's error stays in the status line.
    private func show(_ reason: CqRepeatLoop.StopReason) {
        let message: EntryStatus?
        switch reason {
        case .txLockout:
            message = keyer.tx.txGate()
        case .postContest:
            message = KeyerTexts.postContest
        case .notKeyable:
            message = KeyerTexts.cqRepeat(false, seconds: config.config.runMode.repeatSeconds)
        case .sendFailed:
            message = nil
        }
        if let message {
            status.showJoined(message.parts, separator: "")
        }
    }
}
