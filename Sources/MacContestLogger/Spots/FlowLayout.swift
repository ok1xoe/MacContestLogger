import AppKit
import SwiftUI

/// Kotlin `FlowRow`: children left to right, wrapping to the next line when the width is used up.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in arranged.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                                  proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size: CGSize = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = Swift.max(rowHeight, size.height)
            widest = Swift.max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}

/// A transparent overlay that takes only the secondary click (or Control+click) and passes everything else through
/// to the view under it (Kotlin `onPointerEvent(Press) { if (e.buttons.isSecondaryPressed) … }`).
struct SecondaryClickArea: NSViewRepresentable {
    let action: @MainActor () -> Void

    final class AreaView: NSView {
        var action: (@MainActor () -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let secondary: Bool = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return secondary && bounds.contains(convert(point, from: superview)) ? self : nil
        }

        override func rightMouseDown(with event: NSEvent) {
            action?()
        }

        override func mouseDown(with event: NSEvent) {
            action?()
        }
    }

    func makeNSView(context: Context) -> AreaView {
        let view = AreaView()
        view.action = action
        return view
    }

    func updateNSView(_ view: AreaView, context: Context) {
        view.action = action
    }
}
