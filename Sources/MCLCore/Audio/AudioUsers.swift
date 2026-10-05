/// Reference counting of the shared receiver audio (`AppState.acquireAudio` / `releaseAudio`, `AS:152-167`): the
/// waterfall, the CW reader and the contest recorder share one `AudioCapture`. The first user starts the input
/// (`audio.start(config.rxAudioDevice)`); a running input is not reselected; the last user closes it.
///
/// **Resource leak fixed:** Kotlin registers the user before starting, so after a failed start the
/// user stays registered — the input then never closes and a later `acquire` returns "no error" without starting.
/// Here a failed start unregisters the user (`startFailed`).
public struct AudioUsers: Sendable, Equatable {

    /// What `acquire` asks of the device.
    public enum AcquireAction: Equatable, Sendable {
        /// The input is already running — nothing (Kotlin returns `null`).
        case alreadyRunning
        /// Start the input; report the outcome with `startFailed` on an error.
        case start
    }

    public private(set) var users: Set<String> = []

    public init() {}

    /// `acquireAudio(user)`: registers the user; `running` = `audio.isRunning`.
    public mutating func acquire(_ user: String, running: Bool) -> AcquireAction {
        users.insert(user)
        return running ? .alreadyRunning : .start
    }

    /// The start for `user` failed: the user is not left registered.
    public mutating func startFailed(_ user: String) {
        users.remove(user)
    }

    /// `releaseAudio(user)`: `true` = no user is left, close the input (Kotlin closes whenever the set is empty, even
    /// for a user that was not registered).
    public mutating func release(_ user: String) -> Bool {
        users.remove(user)
        return users.isEmpty
    }
}
