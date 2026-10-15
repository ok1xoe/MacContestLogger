/// The waterfall image of the spectrum display: the zoomed bins of the rows, and the vertical (bar chart) layout of
/// N1MM, where the frequency runs up the window and the waterfall moves from right to left (the newest line next to
/// the spectrum pane on the right).
public enum SpectrumPixels {

    /// The rows cut to the visible bins (`window`); the full width is returned as it is.
    public static func crop(_ rows: [[Float]], window: Range<Int>) -> [[Float]] {
        guard let first = rows.first, !window.isEmpty, window != 0..<first.count else { return rows }
        return rows.map { row in
            let lo: Int = Swift.min(row.count, window.lowerBound)
            let hi: Int = Swift.min(row.count, window.upperBound)
            return Array(row[lo..<hi])
        }
    }

    /// The image turned for the vertical layout: one column per row with the newest on the right, bin 0 at the
    /// bottom (`binZeroAtBottom`) or at the top (N1MM „Reverse frequency scale").
    public static func vertical(_ image: WaterfallPixels.Image, binZeroAtBottom: Bool) -> WaterfallPixels.Image {
        let bins: Int = image.width
        let rows: Int = image.height
        var pixels = [UInt32](repeating: 0, count: bins * rows)
        for y in 0..<rows {
            let x: Int = rows - 1 - y
            for b in 0..<bins {
                let ny: Int = binZeroAtBottom ? bins - 1 - b : b
                pixels[ny * rows + x] = image.pixels[y * bins + b]
            }
        }
        return WaterfallPixels.Image(width: rows, height: bins, pixels: pixels)
    }
}
