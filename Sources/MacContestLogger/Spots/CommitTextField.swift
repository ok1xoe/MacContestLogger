import AppKit
import SwiftUI

/// A one-line text field that saves when it loses the focus or on Enter, and only when the text really changed
/// (Kotlin `InlineEdit`, `BlacklistWindow.kt:164-195`). The shown text follows `value` while the field is not being
/// edited; an empty text shows `placeholder`.
struct CommitTextField: NSViewRepresentable {
    let value: String
    var placeholder: String = ""
    var fontSize: CGFloat = 13
    var bold: Bool = false
    var accessibilityLabel: String = ""
    let onCommit: @MainActor (String) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: fontSize, weight: bold ? .bold : .regular)
        field.setAccessibilityLabel(accessibilityLabel)
        if field.currentEditor() == nil, field.stringValue != value {
            field.stringValue = value
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommitTextField

        init(_ parent: CommitTextField) {
            self.parent = parent
        }

        /// The end of an edit (Enter, Tab, a click elsewhere, the window resigning): a changed text is saved.
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let text: String = field.stringValue
            if text != parent.value {
                parent.onCommit(text)
            }
        }
    }
}
