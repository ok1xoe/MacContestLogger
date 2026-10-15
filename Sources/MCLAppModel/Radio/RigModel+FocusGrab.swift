import Foundation
import MCLCore

/// A request to bring the app to the front with entry window `vfo` (`id` makes each request a change).
public struct FocusGrabRequest: Equatable, Sendable {
    public let vfo: Int
    public let id: Int
}

/// N1MM Config → „Grab Focus From Other Apps When Radio Is Tuned" (Nastavení → Převzít fokus při ladění rádia, off by
/// default): when the operator tunes a radio the app controls, the entry window of that radio asks to come to the
/// front. Frequency changes the app made itself (a QSY, a spot, the arrows) never do; the view decides whether
/// the app may take the focus (not while a modal dialog is open, not when it already has it).
extension RigModel {

    /// The app sends `freqHz` to rig `rig`: its polled change is not the operator's.
    func noteAppTune(rig: Int, freqHz: Int64) {
        tuneDetector.appTuned(rig: rig, freqHz: freqHz)
    }

    /// The app sent rig `rig` a command that may move its frequency (a VFO operation, a CAT macro).
    func noteAppChange(rig: Int) {
        tuneDetector.appChanged(rig: rig)
    }

    /// A polled state of rig `index`.
    func radioTuned(_ index: Int, previous: Int64?, now: Int64?) {
        guard tuneDetector.polled(rig: index, previousHz: previous, nowHz: now),
              config.config.window.flag(.grabFocusOnTune) else { return }
        requestFocusGrab(vfo: vfo.so2r ? index : vfo.activeVfo)
    }

    func requestFocusGrab(vfo window: Int) {
        focusGrabCounter += 1
        focusGrabRequest = FocusGrabRequest(vfo: window, id: focusGrabCounter)
    }
}
