import Foundation

/// Maps `NSEvent` scroll deltas to the convention the core's `BandmapViewport.wheel` takes (Compose's
/// `PointerEventType.Scroll`, `BM:236-257`: **negative `dy` = up** = frequency up / zoom in; `dy == 0` = down / out).
///
/// AWT turns a Cocoa wheel event into a rotation of the opposite sign (`wheelRotation = -deltaY`, with the user's
/// natural-scrolling setting already applied by the system), and Compose passes the rotation on as `scrollDelta`; so
/// the Compose value is the negated `scrollingDeltaY`/`scrollingDeltaX` whatever the direction setting. Shift+wheel
/// arrives in the `x` delta (the core picks the dominant axis).
///
/// A trackpad (precise deltas) sends a stream of small events, and its momentum phase goes on after the fingers lift.
/// A step of the tuned frequency per event would flood the rig with `F` commands, so precise deltas are summed and
/// one step is taken per `preciseStep` points of travel (the remainder is kept, a fast swipe is several steps), and the
/// momentum events are ignored. A notched wheel sends
/// one event per notch, each one step (Kotlin). The trackpad handling is a deliberate refinement: v1.1.1's AWT
/// stream for a trackpad was not measured.
public struct BandmapWheel: Equatable, Sendable {

    /// Points of trackpad travel for one step (about one line of text).
    public static let preciseStep: Double = 10

    private var sumX: Double = 0
    private var sumY: Double = 0

    public init() {}

    /// One scroll event. Returns the Compose deltas of every step to take (empty: a zero event, a momentum event, or
    /// a precise delta that has not reached a step yet). A notched wheel event is exactly one step carrying its raw
    /// deltas (Kotlin); a trackpad's travel is summed, each `preciseStep` points is one step of unit size on the
    /// dominant axis, and the remainder stays for the next event (a fast swipe is several steps).
    public mutating func feed(deltaX: Double, deltaY: Double, precise: Bool,
                              momentum: Bool) -> [(dx: Float, dy: Float)] {
        if momentum {
            return []
        }
        if !precise {
            guard deltaX != 0 || deltaY != 0 else { return [] }
            return [(Float(-deltaX), Float(-deltaY))]
        }
        sumX += deltaX
        sumY += deltaY
        let horizontal: Bool = abs(sumX) > abs(sumY)
        let dominant: Double = horizontal ? sumX : sumY
        let steps: Int = Int(abs(dominant) / Self.preciseStep)
        guard steps > 0 else { return [] }
        let sign: Double = dominant < 0 ? -1 : 1
        let consumed: Double = sign * Double(steps) * Self.preciseStep
        if horizontal {
            sumX -= consumed
            sumY = 0
        } else {
            sumY -= consumed
            sumX = 0
        }
        let unit = Float(-sign)
        let step: (dx: Float, dy: Float) = horizontal ? (unit, 0) : (0, unit)
        return Array(repeating: step, count: steps)
    }

    /// A new gesture starts (the phase began): what was summed before is dropped.
    public mutating func reset() {
        sumX = 0
        sumY = 0
    }
}
