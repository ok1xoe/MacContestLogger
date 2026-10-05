import Foundation
import MCLCore
import Observation

/// The program messages of the Info window (Kotlin `AppState.messages = MessageLog(200)` and `messageRevision`,
/// `AS:262-265`): Cabrillo warnings, definition updates and, later, spots of the own call and the like.
///
/// One shared buffer over the core's `MessageLog` (same cap, same blank filtering and trimming). The Info window is a
/// later feature; until then the producers only fill it and their status texts point to it as in Kotlin.
@Observable @MainActor
public final class MessagesModel {

    /// Kotlin `MessageLog(200)`.
    public static let capacity = 200

    /// The messages, oldest first (a copy of the buffer after every change).
    public private(set) var lines: [MessageLog.Entry] = []
    /// Kotlin `messageRevision`: raised by every batch of messages the caller announces.
    public private(set) var revision: Int = 0

    @ObservationIgnored private let log = MessageLog(maxEntries: MessagesModel.capacity)

    public init() {}

    /// Kotlin `messages.add(now, text)` followed by `messageRevision++` (a blank text is dropped by the log; the
    /// revision is raised anyway, as Kotlin raises it after a non-empty batch).
    public func add(_ text: String, at: Date) {
        add([text], at: at)
    }

    /// A batch of messages with one time stamp and one revision step (Kotlin `forEach { messages.add(now, it) }`
    /// then `if (isNotEmpty()) messageRevision++`).
    public func add(_ texts: [String], at: Date) {
        guard !texts.isEmpty else { return }
        let instant = JavaInstant(date: at)
        for text in texts {
            log.add(instant, text)
        }
        lines = log.entries
        revision += 1
    }

    /// The clipboard text of the Info window (`MessageLog.asText`).
    public func asText() throws(JavaDateTimeException) -> String {
        try log.asText()
    }

    public func clear() {
        log.clear()
        lines = []
        revision += 1
    }
}
