import AppKit
import SwiftUI

/// A read-only text island (AppKit `NSTextView`) for the decoded text of the Digital Interface window and
/// the lines of the CAT log: selectable (⌘C copies), scrolled to the end whenever the text changes (Kotlin
/// `LaunchedEffect(text) { scroll.scrollTo(scroll.maxValue) }`), and — when `onTap` is set — reporting a click
/// without a drag-selection as the UTF-16 offset under the pointer (Compose `getOffsetForPosition`).
struct DigitalRxTextView: NSViewRepresentable {
    let text: NSAttributedString
    /// What VoiceOver calls the text area (the text itself is its value).
    let accessibilityText: String
    var inset: NSSize = NSSize(width: 0, height: 0)
    var onTap: (@MainActor (Int) -> Void)?

    final class TapTextView: NSTextView {
        var onTap: (@MainActor (Int) -> Void)?

        override func mouseDown(with event: NSEvent) {
            let point: NSPoint = convert(event.locationInWindow, from: nil)
            let offset: Int = characterIndexForInsertion(at: point)
            super.mouseDown(with: event)
            // `super` tracks the drag until the button is released: a selection is not a tap.
            guard let onTap, selectedRange().length == 0 else { return }
            onTap(offset)
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let textView = TapTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = inset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.onTap = onTap
        textView.setAccessibilityLabel(accessibilityText)
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? TapTextView else { return }
        textView.onTap = onTap
        textView.textContainerInset = inset
        guard let storage = textView.textStorage, !storage.isEqual(to: text) else { return }
        storage.setAttributedString(text)
        textView.scrollToEndOfDocument(nil)
    }
}
