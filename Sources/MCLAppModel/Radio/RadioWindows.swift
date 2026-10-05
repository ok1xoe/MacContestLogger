import Foundation
import MCLCore

/// A request another window makes of the active entry window (Kotlin `EntryAction`, `AS:531`): the Digital Interface
/// window fires the messages from there while the focus stays in it.
public enum EntryWindowAction: Equatable, Sendable {
    /// F1–F12 (`index` 0…11); `opposite` = the other message set (Shift).
    case functionKey(Int, opposite: Bool)
    /// Enter: the ESM Enter, otherwise log the QSO.
    case enter
    /// Esc: `stopSending()`.
    case stopSending
}

/// What the radio tool windows read from and hand to the entry windows (Kotlin `typedCall`, `prefillCall`,
/// `prefillExchange`, `currentExchange`, `entryAction` — `AS:525-540`), and the window models' factories.
extension AppModel {

    /// The active entry window (Kotlin `active`): the one whose panel is active, `nil` when none is (the VFO B
    /// window is active only while it is on screen).
    public var activeEntry: EntryModel? {
        if entry.isActivePanel {
            return entry
        }
        return vfoB.entry.isActivePanel ? vfoB.entry : nil
    }

    /// Kotlin `typedCall`: the call of the window the operator types in — here the active window's (the VFO B
    /// window only when it is the active one), as `rig.typedCall`.
    public var typedCall: String {
        let second: Bool = rig.vfo.twoEntryWindows && rig.vfo.activeVfo == 1
        return second ? vfoB.entry.form.call : entry.form.call
    }

    /// Kotlin `currentExchange`: the received contest exchange typed in the active window.
    public var currentExchange: JavaLinkedMap<String> {
        activeEntry?.form.contestExchange ?? JavaLinkedMap()
    }

    /// Kotlin `prefillCall = call` (`EP:205-211`): the active window takes the call as a call from a spot (a blank
    /// call does nothing) and the call field gets the focus. Kotlin keeps the request until a window is active; here
    /// it goes to the window active now (there always is one on screen).
    public func prefillCall(_ call: String) {
        activeEntry?.prefillCall(call)
    }

    /// Kotlin `prefillExchange = mapOf(id to value)` (`EP:214-219`): the non-blank values go into the active window's
    /// contest fields as they are (no touch mark), then the preview follows.
    public func prefillExchange(_ values: [(id: String?, value: String)]) {
        var map = JavaLinkedMap<String>()
        for item in values {
            map.put(item.id, item.value)
        }
        activeEntry?.prefillExchange(map)
    }

    /// Kotlin `entryAction = …` (`EP:839-850`): the active window runs it without taking the focus. Esc always
    /// stops: without an active window it runs the global `stopSending()` (a safety rule; Kotlin waits for an active
    /// panel).
    public func perform(_ action: EntryWindowAction) {
        guard let target = activeEntry else {
            if action == .stopSending {
                _ = entry.stopSending()
            }
            return
        }
        switch action {
        case .functionKey(let index, let opposite):
            target.sendKeys([index], opposite: opposite, refocus: false)
        case .enter:
            if target.esmActive {
                target.esmEnter()
            } else {
                target.submit()
            }
        case .stopSending:
            _ = target.stopSending()
        }
    }

    // MARK: - window models

    /// The CW keyboard window's model (`cwkeyboard`).
    public func makeCwKeyboard() -> CwKeyboardModel {
        CwKeyboardModel(keyer: keyer, stop: { [weak self] in
            _ = self?.entry.stopSending()
        }, typedCall: { [weak self] in
            self?.typedCall ?? ""
        })
    }

    /// The CW reader window's model (`cwreader`).
    public func makeCwReader() -> CwReaderModel {
        CwReaderModel(audio: audio, config: config, clock: radioWindowClock, prefill: { [weak self] call in
            self?.prefillCall(call)
        })
    }

    /// The waterfall window's model (`waterfall`).
    public func makeWaterfall() -> WaterfallModel {
        WaterfallModel(audio: audio, rig: rig, config: config, clock: radioWindowClock)
    }

    /// The Digital Interface window's model (`digitalinterface`).
    public func makeDigitalInterface() -> DigitalInterfaceModel {
        DigitalInterfaceModel(DigitalInterfaceModel.Dependencies(
            config: config, contest: contest, digital: keyer.digital, lane: keyer.lane, clock: radioWindowClock,
            app: self))
    }
}
