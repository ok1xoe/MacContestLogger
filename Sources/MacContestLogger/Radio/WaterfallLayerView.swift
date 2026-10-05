import AppKit
import QuartzCore
import SwiftUI

/// The waterfall image (an AppKit island, `CALayer`): the rendered `CGImage` stretched over the view
/// (Kotlin `drawImage(dstSize = size)`, black without an image), the yellow CW pitch line (`0xFFFFC107`, 1 px), and
/// the pointer — moves and exits for the hover text, presses for tuning — as `x` from the left edge with the width.
struct WaterfallLayerView: NSViewRepresentable {
    let image: CGImage?
    /// The pitch line as a fraction of the width, `nil` = no line (outside CW).
    let pitchLine: Double?
    let onHover: @MainActor (Float, Float) -> Void
    let onExit: @MainActor () -> Void
    let onPress: @MainActor (Float, Float) -> Void
    /// What VoiceOver says: the image's description and the hover text (frequency under the pointer or the state).
    let accessibilityText: String
    let accessibilityValueText: String

    final class LayerView: NSView {
        var onHover: (@MainActor (Float, Float) -> Void)?
        var onExit: (@MainActor () -> Void)?
        var onPress: (@MainActor (Float, Float) -> Void)?
        var pitchFraction: Double?
        private let pitchLineLayer = CALayer()
        private var tracking: NSTrackingArea?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            layer?.contentsGravity = .resize
            pitchLineLayer.backgroundColor = DomainColors.pitchLine.cgColor
            pitchLineLayer.isHidden = true
            layer?.addSublayer(pitchLineLayer)
            setAccessibilityElement(true)
            setAccessibilityRole(.image)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("not used")
        }

        override var isFlipped: Bool {
            true
        }

        func show(_ image: CGImage?) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contents = image
            layoutPitchLine()
            CATransaction.commit()
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layoutPitchLine()
            CATransaction.commit()
        }

        private func layoutPitchLine() {
            guard let fraction = pitchFraction else {
                pitchLineLayer.isHidden = true
                return
            }
            // Kotlin `(pitch / model.maxHz() * size.width).toFloat()`.
            let x: Float = Float(fraction * Double(bounds.width))
            pitchLineLayer.isHidden = false
            pitchLineLayer.frame = CGRect(x: CGFloat(x), y: 0, width: 1, height: bounds.height)
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

        private func position(_ event: NSEvent) -> Float {
            Float(convert(event.locationInWindow, from: nil).x)
        }

        override func mouseMoved(with event: NSEvent) {
            onHover?(position(event), Float(bounds.width))
        }

        override func mouseExited(with event: NSEvent) {
            onExit?()
        }

        override func mouseDown(with event: NSEvent) {
            onPress?(position(event), Float(bounds.width))
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
        view.pitchFraction = pitchLine
        view.setAccessibilityLabel(accessibilityText)
        view.setAccessibilityValue(accessibilityValueText)
        view.show(image)
    }
}
