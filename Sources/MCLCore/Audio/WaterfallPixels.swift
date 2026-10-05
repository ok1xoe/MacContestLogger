/// The waterfall image of v1.1.1 (`WaterfallWindow.kt:118-128`, `render`): one pixel per FFT bin across, a fixed
/// number of rows down (`WATERFALL_ROWS = 300`), the newest row on top (row `y` of `Waterfall.normalizedRows()`, which
/// is newest first); rows not yet filled stay black. The view scales the image to its size (`drawImage` with
/// `dstSize`). Computed off the main actor.
///
/// Defensive where Kotlin would throw (none of it is reachable from the waterfall model, which keeps at most 300 rows
/// of one bin count): rows beyond `height` are not drawn (Kotlin: `ArrayIndexOutOfBoundsException` in `setRGB`), a
/// row shorter than the first is drawn as far as it goes (Kotlin: `IndexOutOfBoundsException`), and a zero width gives
/// `nil` (Kotlin: `IllegalArgumentException` from `BufferedImage(0, …)`).
public enum WaterfallPixels {

    /// `WATERFALL_ROWS`.
    public static let rows = 300
    /// `WATERFALL_MAX_HZ`.
    public static let maxHz = 3000.0

    /// An RGB image (`0x00RRGGBB` per pixel, row-major from the top).
    public struct Image: Equatable, Sendable {
        public let width: Int
        public let height: Int
        public let pixels: [UInt32]
    }

    /// `render(model)`: `nil` without rows (or with empty rows); the width is the first row's bin count.
    public static func render(rows source: [[Float]], height: Int = rows) -> Image? {
        guard let first = source.first, !first.isEmpty, height > 0 else { return nil }
        let width = first.count
        var pixels = [UInt32](repeating: 0, count: width * height)
        for (y, row) in source.prefix(height).enumerated() {
            let base = y * width
            for x in 0..<Swift.min(width, row.count) {
                pixels[base + x] = WaterfallPalette.heat(row[x])
            }
        }
        return Image(width: width, height: height, pixels: pixels)
    }

    /// Hover / click position → audio Hz: `position.x / widthPx * model.maxHz()` (`Float` division, then `Double`).
    public static func audioHz(x: Float, width: Float, maxHz: Double) -> Double {
        let ratio: Float = x / width
        return Double(ratio) * maxHz
    }

    /// The CW pitch line: `(pitch / model.maxHz() * size.width).toFloat()`.
    public static func pitchLineX(pitchHz: Int, maxHz: Double, width: Float) -> Float {
        let ratio: Double = Double(pitchHz) / maxHz
        return Float(ratio * Double(width))
    }
}
