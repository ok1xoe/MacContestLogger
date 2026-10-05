import Foundation
import MCLCore

/// The keyer behind the entry window's F-keys and ESM over the app's `KeyerModel` (in place of `NoKeyer`):
/// phone → the voice keyer, CW → the CW keyer, a ready digital mode → fldigi (`EP:727-741`; the router of
/// `FunctionKeyRouter` already chose the branch and built the message).
struct LiveKeyer: KeyerPort {
    weak var model: KeyerModel?

    var canSend: Bool {
        model?.entryModeKeyable() ?? false
    }

    var isSending: Bool {
        model?.isActive ?? false
    }

    var isTuning: Bool {
        model?.isTuning ?? false
    }

    func send(_ transmission: FunctionKeyTransmission, settings: KeyerSettings) -> EntryStatus? {
        guard let model else { return nil }
        switch transmission {
        case .cw(let message, let index):
            model.sendCw(message, key: index)
            return nil
        case .voice(let indices, let hisCall, let freqHz, let opposite):
            return model.voice.play(indices, hisCall: hisCall, freqHz: freqHz, opposite: opposite)
        case .digital(let text, let index):
            model.digital.send(text, key: index)
            return nil
        }
    }

    func stopSending() -> Bool {
        model?.stopSending() ?? false
    }

    func toggleRecording(_ key: Int) -> EntryStatus? {
        model?.voice.toggleRecording(key)
    }

    func toggleTune() -> EntryStatus? {
        model?.toggleTune()
        return nil
    }

    func changeCwSpeed(by deltaWpm: Int) -> EntryStatus? {
        model?.changeCwSpeed(deltaWpm)
        return nil
    }
}
