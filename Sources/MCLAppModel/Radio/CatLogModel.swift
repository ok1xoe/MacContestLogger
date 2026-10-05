import Foundation
import MCLCore
import Observation

/// The CAT log (`CatLogWindow.kt`): the lines of the session's `CatTrafficLog`, refreshed while the window is open
/// (a listener added on open and removed on close, `ListenerID`), and „Vymazat".
@Observable @MainActor
public final class CatLogModel {
    public private(set) var lines: [String] = []

    @ObservationIgnored private let log: CatTrafficLog
    @ObservationIgnored private var listener: CatTrafficLog.ListenerID?

    init(log: CatTrafficLog) {
        self.log = log
    }

    /// The window opened: the listener (lines from the writers' threads hop to the main actor) and the snapshot.
    public func open() {
        guard listener == nil else { return }
        let log: CatTrafficLog = self.log
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
}
