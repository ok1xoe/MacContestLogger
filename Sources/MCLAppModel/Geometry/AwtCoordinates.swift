import CoreGraphics

/// Window coordinates of the JVM version (AWT) and of AppKit.
///
/// AWT stores a window's top-left corner with the origin at the top left of the main display and y growing down;
/// AppKit's origin is the bottom left of the main display with y growing up. Both are logical points. The conversion
/// mirrors over the main display's height and is its own inverse: `y' = mainScreenHeight - y - h`. Without it a
/// window saved by v1.1.1 would reopen mirrored vertically.
public enum AwtCoordinates {

    /// An AWT rectangle (top-left origin) as an AppKit frame.
    public static func toAppKit(_ awt: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: awt.minX, y: mainScreenHeight - awt.minY - awt.height, width: awt.width, height: awt.height)
    }

    /// An AppKit frame as an AWT rectangle (top-left origin).
    public static func fromAppKit(_ frame: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: mainScreenHeight - frame.minY - frame.height, width: frame.width,
               height: frame.height)
    }
}
