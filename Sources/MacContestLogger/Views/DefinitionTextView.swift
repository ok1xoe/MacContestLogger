import AppKit
import SwiftUI

/// The YAML text of the definition editor (Kotlin `BasicTextField`, `DE:170-180`): an `NSTextView` in a scroll view,
/// monospaced at the window's size − 1, plain text, and **no automatic substitutions** — quotes, dashes, text
/// replacement, spelling correction, links and data detection would silently change the YAML (Compose's field
/// replaces nothing).
///
/// Every edit goes to `onChange`; a text set by the model (open, new, discard) replaces the view's text and its undo
/// history. Changes are followed through `NSText.didChangeNotification` of this view (no delegate conformance).
struct DefinitionTextView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    let accessibilityLabel: String
    let onChange: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll: NSScrollView = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        if let view = scroll.documentView as? NSTextView {
            Self.configure(view)
            context.coordinator.attach(view)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        guard let view = scroll.documentView as? NSTextView else { return }
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        if view.font != font {
            view.font = font
            view.typingAttributes[.font] = font
        }
        view.setAccessibilityLabel(accessibilityLabel)
        // Not while the input system composes (marked text) and not for the view's own edit coming back.
        if !view.hasMarkedText(), !view.string.utf16.elementsEqual(text.utf16) {
            view.string = text
            // ⌘Z must not bring back another definition's text: the window holds only this text view.
            view.breakUndoCoalescing()
            view.undoManager?.removeAllActions()
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Plain monospaced text without any automatic change of what is typed; long lines wrap (as Compose's field).
    private static func configure(_ view: NSTextView) {
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.textColor = NSColor.textColor
        view.backgroundColor = NSColor.textBackgroundColor
        view.textContainerInset = NSSize(width: 2, height: 4)
    }

    @MainActor
    final class Coordinator {
        var onChange: (@MainActor (String) -> Void)?
        private var observer: NSObjectProtocol?

        func attach(_ view: NSTextView) {
            observer = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: view,
                                                              queue: .main) { [weak self, weak view] _ in
                MainActor.assumeIsolated {
                    guard let self, let view else { return }
                    self.onChange?(view.string)
                }
            }
        }

        func detach() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
        }
    }
}
