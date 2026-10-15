import CoreGraphics
import Foundation
import MCLCore

/// N1MM's recovery of a lost window (Ctrl+Shift+click): a window with no usable part on any connected display
/// (`WindowPlacement.clampToScreens` finds none — a disconnected monitor, a moved Space) moves to the top left of
/// the main display, the next one a step lower and to the right. Windows that can be grabbed stay where they are.
/// AppKit coordinates (the origin bottom left) for the frames and the displays alike.
public enum WindowGather {

    /// The cascade step between gathered windows.
    public static let step: CGFloat = 24
    /// The margin from the main display's top left corner.
    public static let margin: CGFloat = 20

    /// The new origin of every lost window by its index in `frames`.
    public static func moves(frames: [CGRect], screens: [CGRect], main: CGRect) -> [Int: CGPoint] {
        var out: [Int: CGPoint] = [:]
        var placed: CGFloat = 0
        for (index, frame) in frames.enumerated() {
            let reachable = WindowPlacement.clampToScreens(x: Int(frame.minX), y: Int(frame.minY),
                                                           width: Int(frame.width), height: Int(frame.height),
                                                           screens: screens) != nil
            guard !reachable else { continue }
            let left: CGFloat = main.minX + margin + placed * step
            let top: CGFloat = main.maxY - margin - placed * step
            out[index] = CGPoint(x: left, y: max(main.minY, top - frame.height))
            placed += 1
        }
        return out
    }
}
