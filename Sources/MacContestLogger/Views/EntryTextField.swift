import AppKit
import MCLAppModel
import SwiftUI

/// Registry of the entry window's fields for programmatic focus (Kotlin `FocusRequester`s): the view registers
/// each `NSTextField` under its key, `focus` makes it the first responder.
@MainActor
final class EntryFocusController {

    private final class Box {
        weak var field: NSTextField?
        init(_ field: NSTextField) { self.field = field }
    }

    private var fields: [EntryFieldKey: Box] = [:]
    /// A focus request made before its field was in a window (start-up): honoured when the field gets one.
    private var pending: EntryFieldKey?

    func register(_ key: EntryFieldKey, _ field: EntryNSTextField) {
        fields[key] = Box(field)
        field.onMovedToWindow = { [weak self] in
            self?.fieldReady(key)
        }
        fieldReady(key)
    }

    /// Kotlin `requester.requestFocus()`; a field that is not shown is ignored (Kotlin `runCatching`), a field
    /// not yet in a window gets the focus as soon as it is.
    func focus(_ key: EntryFieldKey?) {
        guard let key else { return }
        guard let field = fields[key]?.field, field.window != nil else {
            pending = key
            return
        }
        pending = nil
        // After the current SwiftUI update: the field may be re-enabled (database switch) in the same pass.
        DispatchQueue.main.async {
            guard let window = field.window, field.isEnabled else { return }
            if window.firstResponder === field.currentEditor() {
                return
            }
            window.makeFirstResponder(field)
        }
    }

    /// The registered field whose editor is the first responder of its window (the key monitor's focus move starts
    /// there).
    func focusedKey() -> EntryFieldKey? {
        for (key, box) in fields {
            guard let field = box.field, let editor = field.currentEditor(), let window = field.window else { continue }
            if window.firstResponder === editor {
                return key
            }
        }
        return nil
    }

    private func fieldReady(_ key: EntryFieldKey) {
        guard pending == key, fields[key]?.field?.window != nil else { return }
        focus(key)
    }
}

/// An entry field: `NSTextField` with a delegate (podklad 4.3). Text is transformed as it is typed without moving
/// the caret (uppercase, frequency filter). The keys of the entry fields are routed by the window's key monitor
/// (`EntryKeyMonitor`) before the field sees them; the delegate only swallows the field editor's own Enter and
/// Esc commands (`insertNewline:`, `cancelOperation:` — Esc must not open the completion list), so Enter and Esc act
/// on their release, through the monitor, in every field.
struct EntryTextField: NSViewRepresentable {

    let key: EntryFieldKey?
    let text: String
    var transform: EntryTextTransform = .none
    var fontSize: Double
    var bold: Bool = false
    var isError: Bool = false
    var placeholder: String = ""
    var accessibilityLabel: String
    var focus: EntryFocusController?
    let onChange: @MainActor (String) -> Void
    /// Tab (`false`) / Shift+Tab (`true`) that reached the field (not routed by the key monitor); `true` = handled,
    /// otherwise AppKit's key-view loop moves the focus.
    var onTab: (@MainActor (_ backward: Bool) -> Bool)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> EntryNSTextField {
        let field = EntryNSTextField(frame: .zero)
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.focusRingType = .exterior
        field.wantsLayer = true
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: EntryNSTextField, context: Context) {
        let coordinator: Coordinator = context.coordinator
        coordinator.parent = self
        field.entryKey = key
        let weight: NSFont.Weight = bold ? .bold : .regular
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: weight)
        if field.font != font {
            field.font = font
        }
        field.isEnabled = context.environment.isEnabled
        field.placeholderString = placeholder
        field.setAccessibilityLabel(accessibilityLabel)
        field.textColor = isError ? DomainColors.dupe : NSColor.textColor
        field.layer?.borderWidth = isError ? 1 : 0
        field.layer?.borderColor = DomainColors.dupe.cgColor
        let current: String = (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
        if current != text {
            field.stringValue = text
        }
        if let key {
            focus?.register(key, field)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: EntryTextField?

        func controlTextDidChange(_ notification: Notification) {
            guard let parent, let field = notification.object as? NSTextField else { return }
            guard let editor = field.currentEditor() as? NSTextView else {
                parent.onChange(parent.transform.apply(field.stringValue))
                return
            }
            // A pending composition (dead key, input method) is transformed once it is committed.
            if editor.hasMarkedText() {
                return
            }
            let typed: String = editor.string
            let transformed: String = parent.transform.apply(typed)
            if transformed != typed {
                let caret: Int = editor.selectedRange().location
                let before: String = Self.prefix(typed, utf16Count: caret)
                let newCaret: Int = parent.transform.apply(before).utf16.count
                editor.string = transformed
                editor.setSelectedRange(NSRange(location: min(newCaret, transformed.utf16.count), length: 0))
            }
            parent.onChange(transformed)
        }

        /// The press of Enter and Esc reaches the field (the monitor acts on the release); the field editor's
        /// commands for them are swallowed. Kotlin fields have no completion list, so `complete:` goes too.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)),
                 #selector(NSResponder.complete(_:)):
                return true
            case #selector(NSResponder.insertTab(_:)):
                return parent?.onTab?(false) ?? false
            case #selector(NSResponder.insertBacktab(_:)):
                return parent?.onTab?(true) ?? false
            default:
                return false
            }
        }

        /// The first `utf16Count` UTF-16 units of `text`, rounded down to a whole character.
        private static func prefix(_ text: String, utf16Count: Int) -> String {
            let units: String.UTF16View = text.utf16
            let end: String.Index = units.index(units.startIndex, offsetBy: min(utf16Count, units.count))
            let rounded: String.Index = end.samePosition(in: text) ?? text.startIndex
            return String(text[..<rounded])
        }
    }
}

/// `NSTextField` whose cell hands out its own field editor, so the key monitor can tell an entry field's editor from
/// any other first responder.
final class EntryNSTextField: NSTextField {

    /// The entry field this is (`nil` = a field outside the key routing, e.g. the frequency).
    var entryKey: EntryFieldKey?
    /// Called when the field is put into a window (deferred focus at start-up).
    var onMovedToWindow: (@MainActor () -> Void)?

    /// The field editor of this field (kept on the control, not the cell: `NSCell` copies are shallow).
    private(set) lazy var fieldEditor: EntryFieldEditor = {
        let editor = EntryFieldEditor()
        editor.isFieldEditor = true
        editor.owner = self
        return editor
    }()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            onMovedToWindow?()
        }
    }

    override class var cellClass: AnyClass? {
        get { EntryTextFieldCell.self }
        set { _ = newValue }
    }
}

final class EntryTextFieldCell: NSTextFieldCell {

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        (controlView as? EntryNSTextField)?.fieldEditor
    }
}

/// The field editor of an `EntryNSTextField`; `owner` tells the key monitor which field has the focus.
final class EntryFieldEditor: NSTextView {

    weak var owner: EntryNSTextField?
}
