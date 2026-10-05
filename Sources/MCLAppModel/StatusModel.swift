import Foundation
import MCLCore
import Observation

/// A status-line text kept as translation keys, so it follows a language switch (texts are translated
/// when shown, not frozen when set).
public enum StatusText: Equatable, Sendable {
    /// One message (Kotlin `statusMessage = tr(…)`).
    case message(ContestMessage)
    /// Messages joined by a separator (Kotlin `buildString { append(tr(…)); append(" · ") … }`).
    case joined([ContestMessage], separator: String)
}

/// The status line of the main window (Kotlin `AppState.statusMessage`, `KA:1114`).
@Observable @MainActor
public final class StatusModel {

    /// The current text; `nil` = empty (Kotlin `""`).
    public private(set) var current: StatusText?

    @ObservationIgnored private let language: LanguageModel

    public init(language: LanguageModel) {
        self.language = language
    }

    /// The text in the current language (`""` when there is none).
    public var message: String {
        guard let current else { return "" }
        return language.text(current)
    }

    public func show(_ message: ContestMessage) {
        current = .message(message)
    }

    /// `statusMessage = tr(key, args…)`.
    public func show(_ key: String, _ args: Translator.Arg...) {
        current = .message(ContestMessage(key, parts: args.map { ContestMessage.Part.value($0) }))
    }

    /// A text shown as is (Kotlin strings without `tr`, exception messages).
    public func showVerbatim(_ text: String) {
        current = .message(.verbatim(text))
    }

    public func showJoined(_ parts: [ContestMessage], separator: String) {
        current = .joined(parts, separator: separator)
    }

    public func clear() {
        current = nil
    }
}
