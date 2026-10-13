import AppKit
import SwiftUI

/// A read-only text island (AppKit `NSTextView`) for the decoded text of the Digital Interface window and
/// the lines of the CAT log: selectable (⌘C copies), scrolled to the end whenever the text changes (Kotlin
/// `LaunchedEffect(text) { scroll.scrollTo(scroll.maxValue) }`), and — when `onTap` is set — reporting a click
/// without a drag-selection as the UTF-16 offset under the pointer (Compose `getOffsetForPosition`) with the modifier
/// keys held.
///
/// The Digital Interface adds: the pointer position (`onHover`, N1MM MouseOver / Hover Mode / pause routines), the
/// right click (`onRightClick`, also Ctrl+click — the macOS secondary click; `true` = handled, otherwise the
/// text view's own menu) and N1MM's non-scrolling mode (`scrolling == false`): new text never moves what is on
/// screen; when it runs past the bottom the view turns a page so the newest line is at the top.
struct DigitalRxTextView: NSViewRepresentable {
    let text: NSAttributedString
    /// What VoiceOver calls the text area (the text itself is its value).
    let accessibilityText: String
    var inset: NSSize = NSSize(width: 0, height: 0)
    var scrolling: Bool = true
    var onTap: (@MainActor (Int, NSEvent.ModifierFlags) -> Void)?
    var onHover: (@MainActor (Int?) -> Void)?
    var onRightClick: (@MainActor () -> Bool)?

    final class TapTextView: NSTextView {
        var onTap: (@MainActor (Int, NSEvent.ModifierFlags) -> Void)?
        var onHover: (@MainActor (Int?) -> Void)?
        var onRightClick: (@MainActor () -> Bool)?
        private var tracking: NSTrackingArea?

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control), let onRightClick, onRightClick() {
                return
            }
            let point: NSPoint = convert(event.locationInWindow, from: nil)
            let offset: Int = characterIndexForInsertion(at: point)
            super.mouseDown(with: event)
            // `super` tracks the drag until the button is released: a selection is not a tap.
            guard let onTap, selectedRange().length == 0 else { return }
            onTap(offset, event.modifierFlags)
        }

        override func rightMouseDown(with event: NSEvent) {
            if let onRightClick, onRightClick() {
                return
            }
            super.rightMouseDown(with: event)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking {
                removeTrackingArea(tracking)
            }
            guard onHover != nil else { return }
            let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways,
                                                              .inVisibleRect], owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            guard let onHover else { return }
            let point: NSPoint = convert(event.locationInWindow, from: nil)
            guard let layout = layoutManager, let container = textContainer, let storage = textStorage,
                  storage.length > 0 else {
                onHover(nil)
                return
            }
            let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            var fraction: CGFloat = 0
            let glyph: Int = layout.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: &fraction)
            let rect: NSRect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            guard rect.contains(local) else {
                onHover(nil)
                return
            }
            onHover(layout.characterIndexForGlyph(at: glyph))
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            onHover?(nil)
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
        textView.onHover = onHover
        textView.onRightClick = onRightClick
        textView.setAccessibilityLabel(accessibilityText)
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? TapTextView else { return }
        textView.onTap = onTap
        textView.onRightClick = onRightClick
        if (textView.onHover == nil) != (onHover == nil) {
            textView.onHover = onHover
            textView.updateTrackingAreas()
        } else {
            textView.onHover = onHover
        }
        textView.textContainerInset = inset
        guard let storage = textView.textStorage, !storage.isEqual(to: text) else { return }
        let visible: NSRect = scroll.contentView.bounds
        storage.setAttributedString(text)
        if scrolling {
            textView.scrollToEndOfDocument(nil)
            return
        }
        // Non-scrolling: keep the view still; when the newest text is below the visible area, turn a page so that
        // the last line is at the top.
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        layout.ensureLayout(for: container)
        let used: NSRect = layout.usedRect(for: container)
        if used.maxY > visible.maxY {
            let lastLine: NSRect = layout.lineFragmentRect(forGlyphAt: max(layout.numberOfGlyphs - 1, 0),
                                                           effectiveRange: nil)
            textView.scroll(NSPoint(x: 0, y: lastLine.minY))
        } else {
            textView.scroll(visible.origin)
        }
    }
}
