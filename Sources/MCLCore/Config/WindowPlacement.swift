import CoreGraphics
import Foundation

/// Pure geometry of window placement relative to displays. The Java original (`WindowPlacement`)
/// is a `final class` with a private constructor and a single static method —
/// a stateless utility, not a data record. Hence here too it is a stateless caseless
/// enum (same pattern as `AppPaths`), without `Codable`/`Equatable` — there is no
/// persistable value that these conformances would meaningfully describe.
/// neexistuje.
public enum WindowPlacement {

    /// Minimum visible strip of the window (dp), so the title bar can be grabbed. A display is
    /// rejected only when the intersection is small in BOTH dimensions (a tiny corner); it is enough for it to
    /// be large enough in one dimension, and the window is clamped back onto the area.
    private static let minVisibleWidth: CGFloat = 80
    private static let minVisibleHeight: CGFloat = 24

    /// Returns a clamped position so that the window is entirely inside the display with the largest
    /// overlap, or `nil` if the window has no sufficiently large visible intersection
    /// with any display (e.g. a disconnected monitor).
    public static func clampToScreens(x: Int, y: Int, width: Int, height: Int, screens: [CGRect]) -> (x: Int, y: Int)? {
        guard !screens.isEmpty else { return nil }
        let win = CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(max(1, width)), height: CGFloat(max(1, height)))
        var best: CGRect?
        var bestArea: CGFloat = -1
        for screen in screens {
            let inter = screen.intersection(win)
            if inter.isEmpty { continue }
            if inter.width < minVisibleWidth && inter.height < minVisibleHeight { continue }
            let area = inter.width * inter.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        guard let best else { return nil }
        let nx = clamp(x, lo: Int(best.minX), hi: Int(best.minX + best.width) - width)
        let ny = clamp(y, lo: Int(best.minY), hi: Int(best.minY + best.height) - height)
        return (nx, ny)
    }

    /// Clamps `v` into [lo,hi]; if the window is larger than the display (hi<lo), returns lo.
    private static func clamp(_ v: Int, lo: Int, hi: Int) -> Int {
        if hi < lo { return lo }
        return max(lo, min(hi, v))
    }
}
