import Foundation
import MCLCore

/// The periodic automatic backup (Kotlin `AppState` init, `AS:2045-2052`: `while (true) { delay(60_000);
/// runCatching { autoBackupIfDue() } }` on `Dispatchers.IO`).
///
/// Every 60 s of the injected clock the tick runs (`DatabaseModel.backup(force: false, revision:)`, whose copy is one
/// job on the handle's serial queue — off the main thread and never beside a write); a failure is a status text there.
/// The next tick is scheduled only after the previous one finished, like Kotlin's sequential loop.
///
/// Swift-only stops: `stop()` before the forced backup on quit and while the database is switched, so
/// no periodic backup runs beside them; `start()` resumes after the switch.
@MainActor
public final class AutoBackupLoop {

    /// Kotlin `delay(60_000)`.
    public static let intervalMilliseconds = 60_000

    private let clock: any RescoreClock
    private let tick: @MainActor () async -> Void
    private var timer: (any RescoreTimer)?
    private var running: Task<Void, Never>?
    private var generation: Int = 0

    /// `true` between `start()` and `stop()`.
    public private(set) var isRunning: Bool = false

    public init(clock: any RescoreClock, tick: @escaping @MainActor () async -> Void) {
        self.clock = clock
        self.tick = tick
    }

    /// Starts the loop (the first tick after one interval); a running loop is left as it is.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        generation += 1
        schedule(generation)
    }

    /// Stops the loop and waits for a tick in flight (its backup finishes; no later one starts).
    public func stop() async {
        isRunning = false
        generation += 1
        timer?.cancel()
        timer = nil
        await running?.value
    }

    /// Waits for a tick in flight (tests).
    func settle() async {
        await running?.value
    }

    private func schedule(_ owner: Int) {
        timer = clock.schedule(afterMilliseconds: Self.intervalMilliseconds) { [weak self] in
            self?.fire(owner)
        }
    }

    private func fire(_ owner: Int) {
        guard isRunning, owner == generation else { return }
        timer = nil
        let previous: Task<Void, Never>? = running
        running = Task { [weak self] in
            await previous?.value
            guard let self, self.isRunning, owner == self.generation else { return }
            await self.tick()
            if self.isRunning && owner == self.generation {
                self.schedule(owner)
            }
        }
    }
}
