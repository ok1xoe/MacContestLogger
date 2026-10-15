#if canImport(AppKit)
import AppKit
#endif
import Foundation
import MCLCore

/// N1MM „Program announcements for blind operators": with the switch on (Settings menu, off by default) the logger
/// speaks through VoiceOver — the typed call becoming a dupe or a new (or double) multiplier, a QSO that cannot be logged yet
/// (an incomplete exchange, a missing paper time) and the rig's split going on or off. The texts are posted as
/// accessibility announcements (`NSAccessibility` `announcementRequested`), which VoiceOver reads in its own voice;
/// nothing opens an audio device and nothing is keyed. The port is injected, tests record it.
@MainActor
public final class AnnouncementsModel {

    /// What is announced.
    public enum Event: Equatable, Sendable {
        case dupe
        case newMultiplier(count: Int)
        case incompleteExchange
        case paperTimeMissing
        case split(on: Bool)
    }

    private let config: ConfigModel
    private let language: LanguageModel
    private let post: @MainActor (String) -> Void

    init(config: ConfigModel, language: LanguageModel, post: @escaping @MainActor (String) -> Void) {
        self.config = config
        self.language = language
        self.post = post
    }

    /// „Hlášení pro nevidomé (VoiceOver)".
    public var isEnabled: Bool {
        get { config.config.accessibilityAnnouncements }
        set {
            config.config.accessibilityAnnouncements = newValue
            config.save(failureKey: "Uložení nastavení selhalo (%s)")
        }
    }

    /// Announces `event` when the switch is on.
    public func note(_ event: Event) {
        guard isEnabled else { return }
        post(text(event))
    }

    /// The spoken text in the UI language.
    public func text(_ event: Event) -> String {
        switch event {
        case .dupe:
            return language.tr("Dupe")
        case .newMultiplier(let count):
            return count >= 2 ? language.tr("Dvojitý násobič") : language.tr("Nový násobič")
        case .incompleteExchange:
            return language.tr("Neúplná výměna, QSO nezapsáno")
        case .paperTimeMissing:
            return language.tr("Chybí čas QSO")
        case .split(let on):
            return on ? language.tr("Split zapnut") : language.tr("Split vypnut")
        }
    }

    /// The production port: a VoiceOver announcement of high priority.
    public static let systemPost: @MainActor (String) -> Void = { text in
        #if canImport(AppKit)
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app.mainWindow ?? app as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        #endif
    }
}
