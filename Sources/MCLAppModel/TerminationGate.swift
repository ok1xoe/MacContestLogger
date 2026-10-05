/// The decisions of `applicationShouldTerminate` (L8): the quit sequence runs once, whatever the number of
/// ⌘Q presses.
///
/// - Before the bootstrap starts (or after it failed) the app quits at once.
/// - While the bootstrap runs, the first request waits (`terminateLater`) and the quit sequence starts when the model
///   exists (or the reply is sent at once when the bootstrap fails).
/// - With the model, the first request waits and starts the quit sequence.
/// - Every further request while a quit is pending is cancelled (`terminateCancel`): no second shutdown, the first
///   reply stays pending and is sent when the sequence finishes.
public struct TerminationGate: Equatable, Sendable {

    public enum Phase: Equatable, Sendable {
        case notStarted
        case bootstrapping
        case running
        /// ⌘Q arrived during the bootstrap; the quit sequence waits for the model.
        case quitPending
        case shuttingDown
        /// The quit sequence finished (the reply was sent).
        case finished
        /// The bootstrap failed; nothing is open.
        case failed
    }

    /// The reply to one `applicationShouldTerminate`.
    public enum Decision: Equatable, Sendable {
        case terminateNow
        /// `.terminateLater`; `startShutdown` = run the quit sequence now (the model exists).
        case terminateLater(startShutdown: Bool)
        case terminateCancel
    }

    public private(set) var phase: Phase = .notStarted

    public init() {}

    /// A quit is under way (window closes from now on are not the user's).
    public var isTerminating: Bool {
        switch phase {
        case .quitPending, .shuttingDown, .finished, .failed:
            return true
        case .notStarted, .bootstrapping, .running:
            return false
        }
    }

    public mutating func bootstrapStarted() {
        if phase == .notStarted {
            phase = .bootstrapping
        }
    }

    /// The model exists. `true` = a quit was requested meanwhile: run the quit sequence now.
    public mutating func bootstrapSucceeded() -> Bool {
        switch phase {
        case .quitPending:
            phase = .shuttingDown
            return true
        case .bootstrapping:
            phase = .running
            return false
        default:
            return false
        }
    }

    /// The bootstrap failed. `true` = a quit was requested meanwhile: reply `true` now (nothing is open).
    public mutating func bootstrapFailed() -> Bool {
        let pending: Bool = phase == .quitPending
        phase = pending ? .finished : .failed
        return pending
    }

    public mutating func requestTermination() -> Decision {
        switch phase {
        case .notStarted, .failed, .finished:
            return .terminateNow
        case .bootstrapping:
            phase = .quitPending
            return .terminateLater(startShutdown: false)
        case .running:
            phase = .shuttingDown
            return .terminateLater(startShutdown: true)
        case .quitPending, .shuttingDown:
            return .terminateCancel
        }
    }

    /// The quit sequence finished; the pending reply is sent now.
    public mutating func shutdownFinished() {
        phase = .finished
    }
}
