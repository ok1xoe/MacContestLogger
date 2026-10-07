import Foundation
import MCLCore

/// What one run of a window plugin sends, gathered off the main actor and handed over in batches: one hop to the
/// main actor at a time, however fast the plugin writes.
///
/// - A `set` replaces the pending `set` of its window (the latest content wins; nothing else of it is kept).
/// - Other messages queue in order; while `maxQueued` wait, the stdout reader blocks in `receive`, so the plugin
///   blocks on its own output and memory stays bounded.
/// - `log` and stderr lines count against the run's output budget here; past it they are dropped before any hop
///   (one notice), and a stderr line that finds the queue full is dropped too (stderr never blocks).
/// - Protocol errors are reported once per text and run.
final class PluginInbox: @unchecked Sendable {

    enum Item: Equatable, Sendable {
        case message(PluginInbound)
        case output(String)
        case outputSuppressed
        case protocolError(String)
    }

    struct Batch: Sendable {
        var items: [Item] = []
        /// The latest content per window, in the order the windows were first set in the batch.
        var sets: [(window: String, content: PluginUIContent)] = []
    }

    /// Messages (other than `set`) waiting for the main actor before the reader pauses.
    static let maxQueued = 32
    /// The longest `log` text kept.
    static let maxLogText = 500

    private let condition = NSCondition()
    private var items: [Item] = []
    private var sets: [(window: String, content: PluginUIContent)] = []
    private var hopPending = false
    private var closed = false
    private var budget: Int
    private var reportedErrors: Set<String> = []
    private let deliver: @MainActor @Sendable (Batch) -> Void
    /// Hops made so far (tests check the flood stays bounded).
    private var hops = 0

    init(outputBudget: Int, deliver: @escaping @MainActor @Sendable (Batch) -> Void) {
        self.budget = outputBudget
        self.deliver = deliver
    }

    var hopCount: Int {
        condition.withLock { hops }
    }

    /// From the stdout reader; blocks while the queue is full (unless closed).
    func receive(_ message: PluginInbound) {
        condition.lock()
        defer { condition.unlock() }
        guard !closed else { return }
        switch message {
        case .set(let window, let content):
            if let index = sets.firstIndex(where: { $0.window == window }) {
                sets[index].content = content
            } else {
                sets.append((window, content))
            }
        case .log(let text):
            guard let item = budgeted(text.count > Self.maxLogText ? String(text.prefix(Self.maxLogText)) + "…"
                                                                    : text) else { return }
            waitForRoom()
            guard !closed else { return }
            items.append(contentsOf: item)
        default:
            waitForRoom()
            guard !closed else { return }
            items.append(.message(message))
        }
        scheduleHop()
    }

    /// A stderr line: never blocks; dropped past the budget or when the queue is full.
    func stderr(_ line: String) {
        condition.lock()
        defer { condition.unlock() }
        guard !closed, items.count < Self.maxQueued, let item = budgeted(line) else { return }
        items.append(contentsOf: item)
        scheduleHop()
    }

    func protocolError(_ text: String) {
        condition.lock()
        defer { condition.unlock() }
        guard !closed, reportedErrors.insert(text).inserted else { return }
        items.append(.protocolError(text))
        scheduleHop()
    }

    /// The run is over or stopped: a blocked reader returns, nothing more is delivered.
    func close() {
        condition.lock()
        closed = true
        items = []
        sets = []
        condition.broadcast()
        condition.unlock()
    }

    /// Takes everything pending (on the main actor, in the hop).
    private func take() -> Batch? {
        condition.lock()
        defer { condition.unlock() }
        hopPending = false
        condition.broadcast()
        guard !closed else { return nil }
        let batch = Batch(items: items, sets: sets)
        items = []
        sets = []
        return batch
    }

    // MARK: - under the lock

    private func budgeted(_ line: String) -> [Item]? {
        guard budget > 0 else { return nil }
        budget -= 1
        return budget == 0 ? [.output(line), .outputSuppressed] : [.output(line)]
    }

    private func waitForRoom() {
        while !closed && items.count >= Self.maxQueued {
            condition.wait()
        }
    }

    private func scheduleHop() {
        guard !hopPending else { return }
        hopPending = true
        hops += 1
        let deliver = self.deliver
        MainHop.post { [self] in
            if let batch = take() {
                deliver(batch)
            }
        }
    }
}
