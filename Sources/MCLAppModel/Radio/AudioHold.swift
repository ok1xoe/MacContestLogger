import Foundation
import MCLCore

/// What a radio tool window (CW reader, waterfall) holds of the receiver audio: its sample listener and its audio
/// user. `release()` gives both back when the window closes; if the window's model goes away without a close, `deinit`
/// gives them back on the main actor as a last resort, so the input never stays open for a window that is gone.
final class AudioHold: @unchecked Sendable {

    private let lock = NSLock()
    private let audio: AudioModel
    private let user: String
    private var listener: AudioCapture.ListenerID?
    private var acquired = false

    init(audio: AudioModel, user: String) {
        self.audio = audio
        self.user = user
    }

    /// The listener is attached.
    @MainActor
    func listen(_ body: @escaping @Sendable ([Double]) -> Void) {
        let id: AudioCapture.ListenerID = audio.addListener(body)
        lock.withLock { listener = id }
    }

    /// The audio user is about to be acquired (released with the hold from now on).
    func willAcquire() {
        lock.withLock { acquired = true }
    }

    /// Gives back the listener and the audio user (each once).
    @MainActor
    func release() {
        let (id, held) = take()
        Self.giveBack(audio: audio, user: user, listener: id, acquired: held)
    }

    private func take() -> (AudioCapture.ListenerID?, Bool) {
        lock.withLock {
            let taken: (AudioCapture.ListenerID?, Bool) = (listener, acquired)
            listener = nil
            acquired = false
            return taken
        }
    }

    @MainActor
    private static func giveBack(audio: AudioModel, user: String, listener: AudioCapture.ListenerID?,
                                 acquired: Bool) {
        if let listener {
            audio.removeListener(listener)
        }
        if acquired {
            audio.release(user)
        }
    }

    deinit {
        let (id, held) = take()
        guard id != nil || held else { return }
        let audio: AudioModel = self.audio
        let user: String = self.user
        MainHop.post {
            Self.giveBack(audio: audio, user: user, listener: id, acquired: held)
        }
    }
}
