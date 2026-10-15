import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The spectrum pane of N1MM+'s Spectrum Display: the instant levels (white columns, or a line with „Show Noise
/// Floor as Line"), the decaying levels (blue), the signal threshold (the blue dashed line the mouse wheel moves),
/// and the RX (yellow) and TX (red) lines. Horizontal: frequency across, level up; vertical (bar chart): frequency
/// up the pane, level to the right.
struct SpectrumPaneView: View {
    let picture: SpectrumPicture?
    let setup: SpectrumSetup
    let axis: SpectrumAxisLayout
    let lines: [SpectrumLine]

    var body: some View {
        Canvas { context, size in
            draw(&context, size)
        }
        .accessibilityHidden(true)
    }

    private struct Colors {
        let background: Color
        let instant: Color
        let decayed: Color
        let threshold: Color
    }

    private var colors: Colors {
        switch setup.background {
        case .black:
            return Colors(background: .black, instant: Color(white: 0.85), decayed: Color(red: 0.3, green: 0.55,
                                                                                            blue: 1),
                          threshold: Color(red: 0.35, green: 0.6, blue: 1))
        case .gray:
            return Colors(background: Color(white: 0.22), instant: Color(white: 0.9),
                          decayed: Color(red: 0.4, green: 0.65, blue: 1), threshold: Color(red: 0.45, green: 0.7, blue: 1))
        case .white:
            return Colors(background: .white, instant: Color(white: 0.35), decayed: Color(red: 0.05, green: 0.25,
                                                                                            blue: 0.85),
                          threshold: Color(red: 0.1, green: 0.3, blue: 0.9))
        }
    }

    /// A point from a position along the frequency axis and a level fraction (0 = bottom / left).
    private func point(_ along: Double, _ level: Double, _ size: CGSize) -> CGPoint {
        if axis.vertical {
            let down: Double = axis.binZeroAtBottom ? 1 - along : along
            return CGPoint(x: level * Double(size.width), y: down * Double(size.height))
        }
        return CGPoint(x: along * Double(size.width), y: (1 - level) * Double(size.height))
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let palette: Colors = colors
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        guard let picture, !picture.instant.isEmpty else {
            drawLines(&context, size)
            return
        }
        let scale: SpectrumScale = setup.scale
        let floor: Double = picture.floorDb
        let n: Int = picture.instant.count
        let thresholdFraction: Double = scale.fraction(picture.thresholdLevelDb, floorDb: floor)
        let showInstant: Bool = setup.flag(.showInstant)
        let asLine: Bool = setup.flag(.noiseAsLine) && !axis.vertical
        // Bin i covers i/n … (i+1)/n of the axis.
        func along(_ i: Int) -> Double { (Double(i) + 0.5) / Double(n) }
        if asLine {
            var area = Path()
            var started = false
            for i in 0..<n where picture.decayed[i] >= picture.thresholdLevelDb {
                let top: CGPoint = point(along(i), scale.fraction(picture.decayed[i], floorDb: floor), size)
                let base: CGPoint = point(along(i), thresholdFraction, size)
                area.move(to: base)
                area.addLine(to: top)
                started = true
            }
            if started {
                context.stroke(area, with: .color(palette.decayed), lineWidth: Swift.max(1, size.width / CGFloat(n)))
            }
            if showInstant {
                var line = Path()
                for i in 0..<n {
                    let p: CGPoint = point(along(i), scale.fraction(picture.instant[i], floorDb: floor), size)
                    if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                context.stroke(line, with: .color(palette.instant), lineWidth: 1)
            }
        } else {
            var columns = Path()
            for i in 0..<n {
                let level: Double = picture.instant[i]
                if !showInstant && level < picture.thresholdLevelDb {
                    continue
                }
                columns.move(to: point(along(i), 0, size))
                columns.addLine(to: point(along(i), scale.fraction(level, floorDb: floor), size))
            }
            let extent: CGFloat = axis.vertical ? size.height : size.width
            context.stroke(columns, with: .color(palette.instant), lineWidth: Swift.max(1, extent / CGFloat(n)))
            var decay = Path()
            for i in 0..<n {
                let p: CGPoint = point(along(i), scale.fraction(picture.decayed[i], floorDb: floor), size)
                if i == 0 { decay.move(to: p) } else { decay.addLine(to: p) }
            }
            context.stroke(decay, with: .color(palette.decayed), lineWidth: 1.5)
        }
        var threshold = Path()
        threshold.move(to: point(0, thresholdFraction, size))
        threshold.addLine(to: point(1, thresholdFraction, size))
        context.stroke(threshold, with: .color(palette.threshold), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        drawLines(&context, size)
    }

    private func drawLines(_ context: inout GraphicsContext, _ size: CGSize) {
        for line in lines {
            var path = Path()
            path.move(to: point(line.fraction, 0, size))
            path.addLine(to: point(line.fraction, 1, size))
            context.stroke(path, with: .color(Color(nsColor: line.color)), lineWidth: 1.5)
        }
    }
}
