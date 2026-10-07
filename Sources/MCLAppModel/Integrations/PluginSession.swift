import Foundation
import MCLCore
import Observation

/// One window plugin as its windows show it: the run state, the last content of each window (kept after a crash),
/// and the interactions the views hand back. The process itself is driven by `PluginWindowsModel`.
@Observable @MainActor
public final class PluginSession {

    public enum Phase: Equatable, Sendable {
        /// Not running (never started, or stopped with its windows).
        case stopped
        /// Started, `hello` sent, no answer yet.
        case starting
        case running
        /// Ended on its own (or killed) with the exit code.
        case exited(Int32)
        /// No answer to `hello` within the limit, or its input is full; it was stopped.
        case hung
        /// The executable could not be started (the reason).
        case failed(String)
        /// Asks for permissions this version does not grant (the permissions).
        case refused([String])
        /// Window plugins are switched off (`MCL_INERT_*`).
        case disabled
    }

    public let package: PluginPackage
    public internal(set) var phase: Phase = .stopped
    /// The shown content of each window (by window id).
    public private(set) var contents: [String: PluginUIContent] = [:]
    /// How many times the content was applied (renders are throttled).
    public private(set) var renderCount: Int = 0

    @ObservationIgnored var connection: (any PluginConnection)?
    /// Raised at every start: messages of an older run are ignored.
    @ObservationIgnored var generation: Int = 0
    @ObservationIgnored var helloTimer: (any RescoreTimer)?
    @ObservationIgnored var stopping = false
    @ObservationIgnored var inbox: PluginInbox?
    /// Requests being answered.
    @ObservationIgnored var inFlight = 0
    @ObservationIgnored var inputClosedReported = false
    @ObservationIgnored var reportedErrors: Set<String> = []
    @ObservationIgnored private var pending: [String: PluginUIContent] = [:]
    @ObservationIgnored private var throttleTimer: (any RescoreTimer)?

    init(package: PluginPackage) {
        self.package = package
    }

    public var name: String {
        package.manifest.name
    }

    /// Whether the banner offers „Restart".
    public var canRestart: Bool {
        switch phase {
        case .exited, .hung, .failed:
            return true
        default:
            return false
        }
    }

    // MARK: - content, throttled

    /// A `set` from the plugin: applied at once when nothing was applied in the last `renderIntervalMs`, otherwise
    /// at the end of that interval (the latest content per window wins), so a window renders at most 5× a second.
    func receive(window: String, content: PluginUIContent, clock: any RescoreClock) {
        pending[window] = content
        guard throttleTimer == nil else { return }
        flush()
        armThrottle(clock)
    }

    private func armThrottle(_ clock: any RescoreClock) {
        throttleTimer = clock.schedule(afterMilliseconds: PluginWindowsModel.renderIntervalMs) { [weak self] in
            guard let self else { return }
            self.throttleTimer = nil
            guard !self.pending.isEmpty else { return }
            self.flush()
            self.armThrottle(clock)
        }
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        contents.merge(pending) { _, new in new }
        pending = [:]
        renderCount += 1
    }

    /// The new run starts with no pending content (the shown one stays until the plugin replaces it).
    func resetForRun() {
        pending = [:]
        throttleTimer?.cancel()
        throttleTimer = nil
        helloTimer?.cancel()
        helloTimer = nil
        reportedErrors = []
        inFlight = 0
        inputClosedReported = false
        stopping = false
    }

    /// A toggle flips at once in the shown content (the plugin's next `set` confirms or corrects it).
    func setToggle(window: String, id: String, value: Bool) {
        guard let content = contents[window] else { return }
        var copy: PluginUIContent = content
        copy.elements = Self.replacingToggle(copy.elements, id: id, value: value)
        contents[window] = copy
    }

    private static func replacingToggle(_ elements: [PluginUIElement], id: String, value: Bool) -> [PluginUIElement] {
        elements.map { element in
            switch element {
            case .toggle(let toggleId, let label, _) where toggleId == id:
                return .toggle(id: toggleId, label: label, value: value)
            case .tabs(let tabsId, let tabs):
                return .tabs(id: tabsId, tabs: tabs.map { tab in
                    PluginUITab(id: tab.id, title: tab.title,
                                elements: replacingToggle(tab.elements, id: id, value: value))
                })
            default:
                return element
            }
        }
    }
}
