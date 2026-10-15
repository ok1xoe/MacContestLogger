import Foundation
import MCLCore
import Observation

/// N1MM's SO2R automation over the two entry windows: Dueling CQs (Ctrl+B) and Focus on Other Radio (Ctrl+Shift+K,
/// „FocusOther Always Swap").
///
/// **Dueling CQs**: the CQ key goes out on one radio, and once it has been sent and the dueling pause
/// (`So2rSetup.duelingCqMs`) is over, on the other one — alternately, while both call fields are blank (a typed
/// call pauses it, as the CQ repeat). It switches itself off on Esc, Ctrl+B, either radio moving more than 200 Hz, a
/// failed send, the TX lockout, post-contest entry and N1MM's „Max Repeat / Dueling CQ duration". It only ever
/// starts on the operator's Ctrl+B and never outside SO2R with both windows on screen.
///
/// **FocusOther**: while the run radio (the one that sent the last CQ) transmits, the entry focus goes to the other
/// radio; when it stops, the focus returns unless an unworked call has been typed there. „Always swap": any
/// transmission moves the focus to the other radio and back, whatever was typed.
@MainActor
final class So2rAutomation {

    /// A call field that has to stay blank for the next dueling CQ, polled meanwhile.
    static let idlePollMillis = 250
    /// N1MM: either radio moving more than this ends the dueling CQs.
    static let qsyLimitHz: Int64 = 200
    /// The wait after a CQ was handed to the keyer before its end is watched (as the CQ repeat).
    static let settleMillis = 250

    private let operating: OperatingModel
    private let keyer: KeyerModel
    private let rig: RigModel
    private let config: ConfigModel
    private let status: StatusModel
    private let clock: any RescoreClock
    /// The entry window of a VFO / radio (`nil` = not on screen).
    private let window: @MainActor (Int) -> EntryModel?
    private var timer: (any RescoreTimer)?
    private var stopped = false
    /// The radio whose CQ comes next.
    private var next = 0
    /// Where each radio was when the dueling started.
    private var startFreqHz: [Int64] = [0, 0]
    private var startedAt: Date?
    private var failureBaseline: Int?
    /// FocusOther: the radio the entry focus returns to when the transmission ends.
    private var returnTo: Int?
    private var wasSending = false
    /// The time source of the maximum duration (tests set it).
    var now: @MainActor () -> Date = { Date() }

    init(operating: OperatingModel, keyer: KeyerModel, rig: RigModel, config: ConfigModel, status: StatusModel,
         clock: any RescoreClock, window: @escaping @MainActor (Int) -> EntryModel?) {
        self.operating = operating
        self.keyer = keyer
        self.rig = rig
        self.config = config
        self.status = status
        self.clock = clock
        self.window = window
    }

    func start() {
        observe()
    }

    /// The quit: nothing is sent any more.
    func stop() {
        stopped = true
        timer?.cancel()
        timer = nil
        operating.duelingCq = false
    }

    /// Waiting for the clock (tests).
    var isScheduled: Bool {
        timer != nil
    }

    // MARK: - dueling CQs

    /// Ctrl+B: dueling CQs on (from the radio with the entry focus) or off.
    func toggleDueling() {
        if operating.duelingCq {
            end(.tr("Dueling CQ vypnuto"))
            return
        }
        guard rig.vfo.so2r, let first = window(0), let second = window(1) else {
            status.show("Dueling CQ: jen v SO2R s oběma zadávacími okny")
            return
        }
        guard !operating.postContest else {
            status.showJoined(KeyerTexts.postContest.parts, separator: "")
            return
        }
        operating.applyCqRepeat(false)
        operating.duelingCq = true
        operating.runMode = .run
        next = rig.vfo.activeVfo
        startFreqHz = [first.form.freqHz, second.form.freqHz]
        startedAt = now()
        failureBaseline = nil
        status.show("Dueling CQ zapnuto (pauza %s ms)", .int(config.config.so2r.millis(.duelingCqMs)))
        step()
    }

    private func end(_ message: EntryStatus?) {
        timer?.cancel()
        timer = nil
        failureBaseline = nil
        operating.duelingCq = false
        if let message {
            status.showJoined(message.parts, separator: "")
        }
    }

    private func schedule(_ milliseconds: Int) {
        timer?.cancel()
        timer = clock.schedule(afterMilliseconds: milliseconds) { [weak self] in
            self?.timer = nil
            self?.step()
        }
    }

    /// One turn: stop conditions, wait while sending or while a call is typed, otherwise the CQ key on `next`.
    private func step() {
        guard !stopped, operating.duelingCq else { return }
        guard rig.vfo.so2r, let first = window(0), let second = window(1) else {
            end(.tr("Dueling CQ vypnuto"))
            return
        }
        if let baseline = failureBaseline, keyer.sendFailures != baseline {
            end(nil)
            return
        }
        if operating.postContest {
            end(KeyerTexts.postContest)
            return
        }
        if let locked = keyer.tx.txGate() {
            end(locked)
            return
        }
        let windows: [EntryModel] = [first, second]
        for (index, entry) in windows.enumerated() where startFreqHz[index] > 0
            && abs(entry.form.freqHz - startFreqHz[index]) > Self.qsyLimitHz {
            end(.tr("Dueling CQ vypnuto — rádio %s změnilo frekvenci", .int(index + 1)))
            return
        }
        let maxMinutes: Int = config.config.runMode.repeatMaxMinutes
        if maxMinutes > 0, let startedAt, now().timeIntervalSince(startedAt) >= Double(maxMinutes) * 60 {
            end(.tr("Dueling CQ vypnuto po %s min (nejdelší doba)", .int(maxMinutes)))
            return
        }
        if keyer.isSending {
            schedule(Self.idlePollMillis)
            return
        }
        if failureBaseline != nil {
            // The last CQ has been sent: the pause, then the other radio.
            failureBaseline = nil
            next = 1 - next
            schedule(config.config.so2r.millis(.duelingCqMs))
            return
        }
        if windows.contains(where: { !KotlinStrings.isBlank($0.form.call) }) {
            schedule(Self.idlePollMillis)
            return
        }
        let entry: EntryModel = windows[next]
        guard entry.canTransmit, entry.inputGate() else {
            schedule(Self.idlePollMillis)
            return
        }
        failureBaseline = keyer.sendFailures
        entry.sendKeys([config.config.esm.keys.cq], refocus: false)
        schedule(Self.settleMillis)
    }

    // MARK: - FocusOther

    private func observe() {
        withObservationTracking {
            _ = keyer.isSending
            _ = keyer.isTuning
        } onChange: { [weak self] in
            MainHop.post {
                guard let self, !self.stopped else { return }
                self.observe()
                self.sendingChanged()
            }
        }
    }

    /// A transmission began or ended.
    private func sendingChanged() {
        let sending: Bool = keyer.isSending || keyer.isTuning
        guard sending != wasSending else { return }
        wasSending = sending
        let setup: So2rSetup = config.config.so2r
        guard setup.flag(.focusOther), rig.vfo.so2r, window(0) != nil, window(1) != nil else {
            returnTo = nil
            return
        }
        let always: Bool = setup.flag(.focusOtherAlwaysSwap)
        let tx: Int = rig.vfo.txVfo
        if sending {
            guard rig.vfo.activeVfo == tx, always || tx == operating.lastCqWindow else { return }
            returnTo = tx
            rig.requestFocusVfo(1 - tx, rxOnly: true)
            rig.focusCaretAtEnd = true
            return
        }
        guard let back = returnTo else { return }
        returnTo = nil
        guard rig.vfo.activeVfo != back else { return }
        if !always, let other = window(1 - back), !KotlinStrings.isBlank(other.form.call), !other.isDupe {
            // An unworked call typed on the S&P radio keeps the focus there.
            return
        }
        rig.requestFocusVfo(back, rxOnly: true)
        rig.focusCaretAtEnd = true
    }

    /// Ctrl+Shift+K: FocusOther on / off (saved).
    func toggleFocusOther() {
        var setup: So2rSetup = config.config.so2r
        let on: Bool = !setup.flag(.focusOther)
        setup.set(.focusOther, flag: on)
        config.config.so2r = setup
        config.saveSilently()
        returnTo = nil
        status.show(on ? "FocusOther zapnuto (fokus na druhé rádio během vysílání)" : "FocusOther vypnuto")
    }
}
