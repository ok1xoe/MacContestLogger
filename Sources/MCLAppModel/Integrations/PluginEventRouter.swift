import Foundation
import MCLCore
import os

/// Hands the plugin events to the running window plugins that subscribed to them. Thread-safe: the spot event comes
/// from a cluster reader thread, the others from the main actor; a delivery only queues a line on the plugin's
/// stdin writer and never blocks. A plugin that no longer reads its input (backpressure) is reported through
/// `onBackpressure` (on the main actor), which marks it hung.
final class PluginEventRouter: Sendable {

    private struct Target {
        let plugin: String
        let generation: Int
        let events: Set<String>
        let connection: any PluginConnection
    }

    private let targets = OSAllocatedUnfairLock<[Target]>(initialState: [])

    /// Web windows' pages listening to events: each gets the event line (on any thread; it hops itself).
    private struct Sink {
        let id: Int
        let events: Set<String>
        let deliver: @Sendable (String) -> Void
    }

    private let sinks = OSAllocatedUnfairLock<(next: Int, list: [Sink])>(initialState: (0, []))

    func addSink(events: [String], deliver: @escaping @Sendable (String) -> Void) -> Int {
        sinks.withLock { state in
            state.next += 1
            state.list.append(Sink(id: state.next, events: Set(events), deliver: deliver))
            return state.next
        }
    }

    func removeSink(_ id: Int) {
        sinks.withLock { state in
            state.list.removeAll { $0.id == id }
        }
    }
    /// The plugin and its run whose input is full.
    let onBackpressure = OSAllocatedUnfairLock<(@MainActor @Sendable (String, Int) -> Void)?>(initialState: nil)

    func add(plugin: String, generation: Int, events: [String], connection: any PluginConnection) {
        let target = Target(plugin: plugin, generation: generation, events: Set(events), connection: connection)
        targets.withLock { list in
            list.removeAll { $0.plugin == plugin }
            list.append(target)
        }
    }

    func remove(plugin: String) {
        targets.withLock { list in
            list.removeAll { $0.plugin == plugin }
        }
    }

    /// Whether any running plugin subscribed to `event` (directory form).
    func wants(_ event: String) -> Bool {
        targets.withLock { list in list.contains { $0.events.contains(event) } }
            || sinks.withLock { state in state.list.contains { $0.events.contains(event) } }
    }

    /// Delivers one event (`qso-logged`, the payload of `PluginEventJson`).
    func deliver(_ event: PluginRunner.Event, json: String) {
        let name: String = PluginRunner.dirName(event)
        let receivers: [Target] = targets.withLock { list in list.filter { $0.events.contains(name) } }
        let pages: [Sink] = sinks.withLock { state in state.list.filter { $0.events.contains(name) } }
        guard !receivers.isEmpty || !pages.isEmpty else { return }
        let line: String = PluginOutbound.event(name, json: json)
        for page in pages {
            page.deliver(line)
        }
        // A closed input (the plugin closed it, or it ended) just stops the events; a full one is a hang.
        for target in receivers where target.connection.send(line) == .full {
            let report = onBackpressure.withLock { $0 }
            let plugin: String = target.plugin
            let generation: Int = target.generation
            MainHop.post {
                report?(plugin, generation)
            }
        }
    }
}
