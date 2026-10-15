import AppKit
import QuartzCore
import SwiftUI

/// The frequency axis of the spectrum display's panes: across (horizontal) or up the pane (vertical bar chart mode,
/// bin 0 at the bottom unless the scale is reversed).
struct SpectrumAxisLayout: Equatable {
    var vertical = false
    var binZeroAtBottom = true

    /// The position along the frequency axis (0…1) of a point in a flipped view of `size`.
    func fraction(x: CGFloat, y: CGFloat, size: CGSize) -> Double {
        if vertical {
            guard size.height > 0 else { return 0 }
            let down = Double(y / size.height)
            return binZeroAtBottom ? 1 - down : down
        }
        guard size.width > 0 else { return 0 }
        return Double(x / size.width)
    }
}

/// A line across the panes at a position along the frequency axis (the RX / CW pitch line, the TX line).
struct SpectrumLine: Equatable {
    let fraction: Double
    let color: NSColor
}

/// The pointer of the spectrum display's panes (an AppKit island): moves and exits for the hover text, presses with
/// Cmd for the split, and the scroll wheel (a mouse notch is one step, a trackpad gives a step every 10 points), all
/// as positions along the frequency axis.
class SpectrumPointerNSView: NSView {
    var onHover: (@MainActor (Double) -> Void)?
    var onExit: (@MainActor () -> Void)?
    var onPress: (@MainActor (Double, NSEvent.ModifierFlags) -> Void)?
    var onWheel: (@MainActor (Int, NSEvent.ModifierFlags) -> Void)?
    var axis = SpectrumAxisLayout()
    private var tracking: NSTrackingArea?
    private var wheelRemainder: CGFloat = 0

    override var isFlipped: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow,
                                                          .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private func fraction(_ event: NSEvent) -> Double {
        let point: NSPoint = convert(event.locationInWindow, from: nil)
        return axis.fraction(x: point.x, y: point.y, size: bounds.size)
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?(fraction(event))
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }

    override func mouseDown(with event: NSEvent) {
        onPress?(fraction(event), event.modifierFlags)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let onWheel else {
            super.scrollWheel(with: event)
            return
        }
        let delta: CGFloat = event.scrollingDeltaY
        var steps = 0
        if event.hasPreciseScrollingDeltas {
            wheelRemainder += delta
            steps = Int(wheelRemainder / 10)
            wheelRemainder -= CGFloat(steps) * 10
        } else if delta != 0 {
            steps = delta > 0 ? 1 : -1
        }
        if steps != 0 {
            onWheel(steps, event.modifierFlags)
        }
    }
}

/// The waterfall image (an AppKit island, `CALayer`): the rendered `CGImage` stretched over the view
/// (Kotlin `drawImage(dstSize = size)`, black without an image), the yellow RX / CW pitch line (`0xFFFFC107`, 1 px)
/// and the red TX line of a split, and the pointer as positions along the frequency axis.
struct WaterfallLayerView: NSViewRepresentable {
    let image: CGImage?
    let lines: [SpectrumLine]
    let axis: SpectrumAxisLayout
    let onHover: @MainActor (Double) -> Void
    let onExit: @MainActor () -> Void
    let onPress: @MainActor (Double, NSEvent.ModifierFlags) -> Void
    let onWheel: @MainActor (Int, NSEvent.ModifierFlags) -> Void
    /// What VoiceOver says: the image's description and the hover text (frequency under the pointer or the state).
    let accessibilityText: String
    let accessibilityValueText: String

    final class LayerView: SpectrumPointerNSView {
        var lines: [SpectrumLine] = []
        private var lineLayers: [CALayer] = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            layer?.contentsGravity = .resize
            setAccessibilityElement(true)
            setAccessibilityRole(.image)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("not used")
        }

        func show(_ image: CGImage?) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contents = image
            layoutLines()
            CATransaction.commit()
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layoutLines()
            CATransaction.commit()
        }

        private func layoutLines() {
            while lineLayers.count < lines.count {
                let line = CALayer()
                layer?.addSublayer(line)
                lineLayers.append(line)
            }
            for (index, line) in lineLayers.enumerated() {
                guard index < lines.count else {
                    line.isHidden = true
                    continue
                }
                let spec: SpectrumLine = lines[index]
                line.isHidden = false
                line.backgroundColor = spec.color.cgColor
                if axis.vertical {
                    let along: Double = axis.binZeroAtBottom ? 1 - spec.fraction : spec.fraction
                    let y: Float = Float(along * Double(bounds.height))
                    line.frame = CGRect(x: 0, y: CGFloat(y), width: bounds.width, height: 1)
                } else {
                    // Kotlin `(pitch / model.maxHz() * size.width).toFloat()`.
                    let x: Float = Float(spec.fraction * Double(bounds.width))
                    line.frame = CGRect(x: CGFloat(x), y: 0, width: 1, height: bounds.height)
                }
            }
        }
    }

    func makeNSView(context: Context) -> LayerView {
        let view = LayerView(frame: .zero)
        update(view)
        return view
    }

    func updateNSView(_ view: LayerView, context: Context) {
        update(view)
    }

    private func update(_ view: LayerView) {
        view.onHover = onHover
        view.onExit = onExit
        view.onPress = onPress
        view.onWheel = onWheel
        view.axis = axis
        view.lines = lines
        view.setAccessibilityLabel(accessibilityText)
        view.setAccessibilityValue(accessibilityValueText)
        view.show(image)
    }
}

/// A transparent pointer area over the spectrum pane's drawing (the pane itself is a SwiftUI `Canvas`).
struct SpectrumPointerArea: NSViewRepresentable {
    let axis: SpectrumAxisLayout
    let onHover: @MainActor (Double) -> Void
    let onExit: @MainActor () -> Void
    let onPress: @MainActor (Double, NSEvent.ModifierFlags) -> Void
    let onWheel: @MainActor (Int, NSEvent.ModifierFlags) -> Void
    let accessibilityText: String
    let accessibilityValueText: String

    func makeNSView(context: Context) -> SpectrumPointerNSView {
        let view = SpectrumPointerNSView(frame: .zero)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        update(view)
        return view
    }

    func updateNSView(_ view: SpectrumPointerNSView, context: Context) {
        update(view)
    }

    private func update(_ view: SpectrumPointerNSView) {
        view.axis = axis
        view.onHover = onHover
        view.onExit = onExit
        view.onPress = onPress
        view.onWheel = onWheel
        view.setAccessibilityLabel(accessibilityText)
        view.setAccessibilityValue(accessibilityValueText)
    }
}
