import Foundation
import MCLCore

/// A serial lane of blocking work on a thread of its own (Kotlin `Dispatchers.IO` per device): jobs
/// run one after another in submission order, never on the main thread, in Swift's cooperative pool or on a shared
/// GCD queue. The thread exists only while there is work — an idle lane holds no thread.
final class SerialLane: @unchecked Sendable {
    private let name: String
    private let lock = NSLock()
    private var jobs: [@Sendable () -> Void] = []
    private var running = false

    init(name: String) {
        self.name = name
    }

    /// Queues `job` after everything submitted before it.
    func submit(_ job: @escaping @Sendable () -> Void) {
        lock.lock()
        jobs.append(job)
        if running {
            lock.unlock()
            return
        }
        running = true
        lock.unlock()
        let thread = Thread { [self] in
            drain()
        }
        thread.name = name
        thread.start()
    }

    /// Runs `body` on the lane, then `then` with its result on the main actor (asynchronously, in order).
    func submit<T: Sendable>(_ body: @escaping @Sendable () -> T,
                             then: @escaping @MainActor @Sendable (T) -> Void) {
        submit {
            let result: T = body()
            MainHop.post {
                then(result)
            }
        }
    }

    /// Waits (without blocking a thread) until everything submitted before has run.
    func settle() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            submit {
                continuation.resume()
            }
        }
    }

    private func drain() {
        while true {
            lock.lock()
            guard !jobs.isEmpty else {
                running = false
                lock.unlock()
                return
            }
            let job: @Sendable () -> Void = jobs.removeFirst()
            lock.unlock()
            job()
        }
    }
}

/// One rig's CAT session with its serial lane (`RigLane`): `connect`, `disconnect`, `tune`, `setMode`,
/// `setPtt` and the `RigController` operations of the rig run there in the order they were asked for; results come
/// back to the main actor asynchronously. The main actor never calls the session's getters (it reads the mirror
/// that `onChange` fills).
final class RigLane: Sendable {
    let cat: any CatPort
    private let lane: SerialLane

    init(cat: any CatPort, name: String) {
        self.cat = cat
        self.lane = SerialLane(name: name)
    }

    /// Fire and forget (Kotlin `cat.tune(hz)` and friends; errors are the caller's to drop).
    func run(_ body: @escaping @Sendable (any CatPort) -> Void) {
        let cat: any CatPort = self.cat
        lane.submit {
            body(cat)
        }
    }

    /// `body` on the lane, `then` with the result on the main actor.
    func run<T: Sendable>(_ body: @escaping @Sendable (any CatPort) -> T,
                          then: @escaping @MainActor @Sendable (T) -> Void) {
        let cat: any CatPort = self.cat
        lane.submit({ body(cat) }, then: then)
    }

    /// Waits until the work queued before has run.
    func settle() async {
        await lane.settle()
    }
}

/// The result of a rig operation on the lane: success, no rig (CAT went away meanwhile), or the error's message.
enum RigOutcome: Sendable, Equatable {
    case done
    case noRig
    case failed(String)

    /// Runs `op` on the connected rig of `cat` (on the lane).
    static func run(_ cat: any CatPort, _ op: (any RigController) throws -> Void) -> RigOutcome {
        guard let rig = cat.rigOrNull() else { return .noRig }
        do {
            try op(rig)
            return .done
        } catch {
            return .failed(ErrorText.message(error))
        }
    }
}
