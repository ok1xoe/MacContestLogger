import Foundation
import MCLCore
import Observation

/// The HamQTH log window (`HamQthLogWindow.kt`): the lines of the callbook's `HamQthLog`, refreshed while the window is
/// open (a listener added on open and removed on close, `ListenerID`), „Kopírovat" and „Vymazat".
@Observable @MainActor
public final class HamQthLogModel {
    public private(set) var lines: [String] = []

    @ObservationIgnored private let log: HamQthLog
    @ObservationIgnored private var listener: HamQthLog.ListenerID?

    public init(log: HamQthLog) {
        self.log = log
    }

    /// The listener is registered (the window is open).
    public var isListening: Bool {
        listener != nil
    }

    /// The window opened: the listener (lines from the writers' threads hop to the main actor) and the snapshot.
    public func open() {
        guard listener == nil else { return }
        let log: HamQthLog = self.log
        listener = log.addListener { [weak self] in
            let lines: [String] = log.snapshot()
            MainHop.post {
                self?.lines = lines
            }
        }
        lines = log.snapshot()
    }

    /// The window closed: the listener goes.
    public func close() {
        if let listener {
            log.removeListener(listener)
        }
        listener = nil
    }

    /// „Vymazat".
    public func clear() {
        log.clear()
        lines = []
    }

    /// „Kopírovat": every line, one per row (Kotlin `lines.joinToString("\n")`).
    public var clipboardText: String {
        lines.joined(separator: "\n")
    }
}
