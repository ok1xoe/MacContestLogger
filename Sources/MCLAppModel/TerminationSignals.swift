import Foundation
import MCLCore

/// SIGTERM / SIGINT / SIGHUP (`kill`, a script's force quit, Ctrl+C in a terminal, the terminal closed) end the app
/// through the regular quit, so `AppModel.shutdown` releases PTT, voice, CW and the carrier first (with the
/// transmit-release milestone). The app installs the sources (`install`: the hooks hand their
/// signal handling over, the signals' default action is ignored, `DispatchSource` on the main queue); the decision is
/// `TerminationSignalGate`:
///
/// - the first signal asks for the regular quit (`NSApp.terminate`, which `TerminationGate` turns into one quit
///   sequence);
/// - a further signal — or a signal while a ⌘Q quit runs — ends the process at once (the shutdown hooks, the frame
///   records removed, `exit(128 + signo)`), but only once the quit released the transmitter and is not writing its
///   forced backup (`AppModel.signalExitAllowed`). Before that the exit is deferred to the milestone;
/// - a wedged lane cannot hold the exit forever: a third signal, or `deadline` seconds after the first deferral,
///   exits anyway;
/// - a single signal cannot either: when the quit has not released the transmitter `releaseDeadline` seconds after
///   the first signal (wedged before or inside the release), the process ends the same way. launchd and a logout send
///   one SIGTERM and a SIGKILL some 20 s later, which runs nothing; this exit still runs the shutdown hooks (our
///   `rigctld` is killed) and the frame cleanup.
///
/// The JVM version only runs its shutdown hook (it kills `rigctld`) on these signals; a held PTT stays keyed there.
@MainActor
public final class TerminationSignals {

    /// What the app does for a decision.
    public struct Actions {
        /// The regular quit (`NSApp.terminate(nil)`, scheduled from the run loop: `handle` runs inside a main-queue
        /// block, and `terminate:` waiting there for the quit's reply would keep the main actor from ever running it).
        public var terminate: @MainActor () -> Void
        /// A quit is under way (`AppHost.isTerminating`, ⌘Q included).
        public var isTerminating: @MainActor () -> Bool
        /// An immediate exit is allowed now (`AppModel.signalExitAllowed`; `true` without a model).
        public var exitAllowed: @MainActor () -> Bool
        /// The quit released the transmitter (`AppModel.transmitReleased`; `false` without a model).
        public var transmitReleased: @MainActor () -> Bool
        /// The immediate end: hooks, frame records, `exit(code)`.
        public var forceExit: @MainActor (Int32) -> Void
        /// Runs `body` on the main actor after `seconds` (the deadline of a deferred exit).
        public var after: @MainActor (Double, @escaping @MainActor () -> Void) -> Void

        public init(terminate: @escaping @MainActor () -> Void, isTerminating: @escaping @MainActor () -> Bool,
                    exitAllowed: @escaping @MainActor () -> Bool,
                    transmitReleased: @escaping @MainActor () -> Bool,
                    forceExit: @escaping @MainActor (Int32) -> Void,
                    after: @escaping @MainActor (Double, @escaping @MainActor () -> Void) -> Void) {
            self.terminate = terminate
            self.isTerminating = isTerminating
            self.exitAllowed = exitAllowed
            self.transmitReleased = transmitReleased
            self.forceExit = forceExit
            self.after = after
        }
    }

    /// The signals routed to the quit.
    public static let signals: [Int32] = [SIGTERM, SIGINT, SIGHUP]
    /// Seconds a deferred exit waits at most for the transmit release (a lane wedged on a dead socket).
    public static let deadline: Double = 5
    /// Seconds after the first signal by which the quit must have released the transmitter, or the process ends.
    public static let releaseDeadline: Double = 15

    private let actions: Actions
    public private(set) var gate = TerminationSignalGate()
    private var sources: [any DispatchSourceSignal] = []

    public init(actions: Actions) {
        self.actions = actions
    }

    /// One delivered signal (the source's handler; tests call it directly — no signal is ever raised in a test).
    public func handle(_ signo: Int32) {
        let action: TerminationSignalGate.Action = gate.receive(
            signo, isTerminating: actions.isTerminating(), exitAllowed: actions.exitAllowed())
        perform(action)
    }

    /// A quit milestone changed (`AppModel.onQuitMilestone`): a deferred exit runs now when it is allowed.
    public func milestoneReached() {
        perform(gate.milestone(exitAllowed: actions.exitAllowed()))
    }

    private func perform(_ action: TerminationSignalGate.Action) {
        switch action {
        case .none:
            break
        case .terminate:
            actions.terminate()
            actions.after(Self.releaseDeadline) { [weak self] in
                guard let self else { return }
                self.perform(self.gate.releaseDeadlineExpired(transmitReleased: self.actions.transmitReleased()))
            }
        case .deferred(let startDeadline):
            guard startDeadline else { return }
            actions.after(Self.deadline) { [weak self] in
                guard let self else { return }
                self.perform(self.gate.deadlineExpired())
            }
        case .forceExit(let code):
            actions.forceExit(code)
        }
    }

    /// Takes the signals over from `ProcessShutdownHooks` (which would re-raise them before the quit released PTT),
    /// ignores their default action and delivers them to `handle` on the main queue. Once per process, before any
    /// daemon registers a hook (the app delegate's `applicationDidFinishLaunching`). Children started through
    /// `Process` get the default dispositions back (measured: a SIGTERM still ends a spawned `sleep`).
    public func install(hooks: ProcessShutdownHooks = .shared) {
        guard sources.isEmpty else { return }
        hooks.handOverSignalHandling()
        for signo in Self.signals {
            signal(signo, SIG_IGN)
            let source: any DispatchSourceSignal = DispatchSource.makeSignalSource(signal: signo, queue: .main)
            // Signals that arrive before the handler ran are coalesced into one event and count as one request (the
            // safe reading: three quick `kill`s never skip the transmit release as a third signal would).
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.handle(signo) }
            }
            source.resume()
            sources.append(source)
        }
    }
}

/// The decision of `TerminationSignals`.
public struct TerminationSignalGate: Equatable, Sendable {

    public enum Action: Equatable, Sendable {
        case none
        case terminate
        /// The exit waits for the quit's milestone; `startDeadline` for the first deferral.
        case deferred(startDeadline: Bool)
        case forceExit(code: Int32)
    }

    /// Signals received so far.
    public private(set) var count = 0
    /// The exit code of a deferred exit (`128 + signo` of the latest deferred signal).
    public private(set) var pendingCode: Int32?
    /// An exit was decided; nothing follows.
    public private(set) var exited = false
    /// The exit code of the first signal (`128 + signo`), for the release deadline.
    public private(set) var firstCode: Int32?

    public init() {}

    /// The first signal (no quit running) asks for the quit. A further one exits when `exitAllowed`, a third one
    /// always; otherwise it is deferred.
    public mutating func receive(_ signo: Int32, isTerminating: Bool, exitAllowed: Bool) -> Action {
        guard !exited else { return .none }
        count += 1
        let code: Int32 = 128 + signo
        if count == 1 && !isTerminating {
            firstCode = code
            return .terminate
        }
        if exitAllowed || count >= 3 {
            return exit(code)
        }
        let first: Bool = pendingCode == nil
        pendingCode = code
        return .deferred(startDeadline: first)
    }

    /// A quit milestone: a deferred exit runs once it is allowed.
    public mutating func milestone(exitAllowed: Bool) -> Action {
        guard !exited, exitAllowed, let pendingCode else { return .none }
        return exit(pendingCode)
    }

    /// The release deadline of the first signal: the process ends unless the quit released the transmitter by then.
    public mutating func releaseDeadlineExpired(transmitReleased: Bool) -> Action {
        guard !exited, !transmitReleased, let firstCode else { return .none }
        return exit(pendingCode ?? firstCode)
    }

    /// The deadline of a deferred exit: it runs whatever the quit's state.
    public mutating func deadlineExpired() -> Action {
        guard !exited, let pendingCode else { return .none }
        return exit(pendingCode)
    }

    private mutating func exit(_ code: Int32) -> Action {
        exited = true
        return .forceExit(code: code)
    }
}
