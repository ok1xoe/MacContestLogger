import CoreGraphics
import Foundation

/// N1MM „Snap windows to edges": where a dragged window goes when it was let go near the edge of a screen's usable
/// area or near another window of the app. Each axis snaps on its own to the nearest edge within `distance`:
/// the screen's edges, the outer edges of another window (the windows then sit side by side) and its matching edges
/// (aligned). Another window counts only when the two overlap, or nearly, on the other axis. Pure geometry
/// (AppKit coordinates, y up).
public enum WindowSnap {

    /// The snapped origin of `frame`, or `nil` when nothing is within `distance`.
    public static func snappedOrigin(_ frame: CGRect, screens: [CGRect], others: [CGRect],
                                     distance: CGFloat) -> CGPoint? {
        let screen: CGRect? = screens.max { lhs, rhs in
            area(lhs.intersection(frame)) < area(rhs.intersection(frame))
        }
        var xTargets: [(edge: CGFloat, to: CGFloat)] = []
        var yTargets: [(edge: CGFloat, to: CGFloat)] = []
        if let screen, !screen.isEmpty {
            xTargets += [(frame.minX, screen.minX), (frame.maxX, screen.maxX)]
            yTargets += [(frame.minY, screen.minY), (frame.maxY, screen.maxY)]
        }
        for other in others where !other.isEmpty && other != frame {
            let overlapsVertically: Bool = frame.minY < other.maxY + distance && other.minY < frame.maxY + distance
            let overlapsHorizontally: Bool = frame.minX < other.maxX + distance && other.minX < frame.maxX + distance
            if overlapsVertically {
                xTargets += [(frame.minX, other.maxX), (frame.maxX, other.minX),
                             (frame.minX, other.minX), (frame.maxX, other.maxX)]
            }
            if overlapsHorizontally {
                yTargets += [(frame.minY, other.maxY), (frame.maxY, other.minY),
                             (frame.minY, other.minY), (frame.maxY, other.maxY)]
            }
        }
        let dx: CGFloat? = nearest(xTargets, distance: distance)
        let dy: CGFloat? = nearest(yTargets, distance: distance)
        guard dx != nil || dy != nil else { return nil }
        return CGPoint(x: frame.minX + (dx ?? 0), y: frame.minY + (dy ?? 0))
    }

    /// The smallest move that brings an edge onto its target, within `distance` (0 = already there).
    private static func nearest(_ targets: [(edge: CGFloat, to: CGFloat)], distance: CGFloat) -> CGFloat? {
        let moves: [CGFloat] = targets.map { $0.to - $0.edge }.filter { abs($0) <= distance }
        guard let best = moves.min(by: { abs($0) < abs($1) }), best != 0 else { return nil }
        return best
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
