import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// What the world map draws (the model's values for one frame).
struct WorldMapScene: Equatable {
    var geo: WorldMapGeo
    var projection: WorldMapModel
    var scheme: MapScheme
    var political: Bool
    var dxccMode: Bool
    var fieldStates: [String: MultCell]
    var dots: [WorldMapModel.Dot]
    var night: [WorldMapModel.NightColumn]
    var nowMillis: Int64
    var station: (lat: Double, lon: Double)?
    var title: String

    static func == (lhs: WorldMapScene, rhs: WorldMapScene) -> Bool {
        lhs.geo.rings.count == rhs.geo.rings.count && lhs.projection == rhs.projection && lhs.scheme == rhs.scheme
            && lhs.political == rhs.political && lhs.dxccMode == rhs.dxccMode && lhs.fieldStates == rhs.fieldStates
            && lhs.dots == rhs.dots && lhs.night == rhs.night && lhs.nowMillis == rhs.nowMillis
            && lhs.station?.lat == rhs.station?.lat && lhs.station?.lon == rhs.station?.lon && lhs.title == rhs.title
    }
}

extension NSColor {
    /// A colour from `0xAARRGGBB` (the colour values of the core).
    convenience init(argb value: UInt32) {
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: CGFloat((value >> 24) & 0xFF) / 255)
    }
}

/// The map canvas (Kotlin `drawWorldMap`, `WorldMapWindow.kt:174-345`). The land layer — the ocean, the filled
/// outlines of thousands of points and the coast — is drawn once into a bitmap and reused until the size, the scheme,
/// the appearance, the political shading or the outlines change; the moving layers (night side, dots, coloured
/// fields, grid, Sun, station, labels) are drawn over it on every frame. Without outlines (no `dxcc.geojson`) the
/// land layer is just the ocean.
struct WorldMapCanvas: NSViewRepresentable {
    let scene: WorldMapScene
    /// The canvas size changed (the night side is computed for it).
    let onSize: @MainActor (CGSize) -> Void
    /// A click in the squares mode (x, y, width, height in points).
    let onTap: @MainActor (CGPoint, CGSize) -> Void
    /// The spoken summary of what the map shows (the number of fields or countries).
    var summary: String = ""

    func makeNSView(context: Context) -> WorldMapNSView {
        let view = WorldMapNSView()
        view.scene = scene
        view.onSize = onSize
        view.onTap = onTap
        view.setAccessibilityRole(.image)
        view.setAccessibilityIdentifier("worldmap.canvas")
        view.setAccessibilityLabel(scene.title)
        view.setAccessibilityValue(summary)
        return view
    }

    func updateNSView(_ view: WorldMapNSView, context: Context) {
        view.onSize = onSize
        view.onTap = onTap
        view.setAccessibilityLabel(scene.title)
        view.setAccessibilityValue(summary)
        if view.scene != scene {
            view.scene = scene
            view.needsDisplay = true
        }
    }
}

@MainActor
final class WorldMapNSView: NSView {
    var scene: WorldMapScene?
    var onSize: (@MainActor (CGSize) -> Void)?
    var onTap: (@MainActor (CGPoint, CGSize) -> Void)?

    private var cached: (key: String, image: NSImage)?
    private var reportedSize: CGSize = .zero

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        reportSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportSize()
    }

    private func reportSize() {
        let size: CGSize = bounds.size
        guard size.width > 0, size.height > 0, size != reportedSize else { return }
        reportedSize = size
        // Never from inside a layout or update pass of SwiftUI.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onSize?(self.reportedSize)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let scene, !scene.dxccMode else { return }
        let point: CGPoint = convert(event.locationInWindow, from: nil)
        onTap?(point, bounds.size)
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let scene, let context = NSGraphicsContext.current?.cgContext else { return }
        let size: CGSize = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        let dark: Bool = isDark
        baseImage(scene, size: size, dark: dark).draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
                                                       respectFlipped: true, hints: nil)
        drawOverlay(scene, in: context, size: size, dark: dark)
    }

    // MARK: - the cached land layer

    private func baseImage(_ scene: WorldMapScene, size: CGSize, dark: Bool) -> NSImage {
        let scale: CGFloat = window?.backingScaleFactor ?? 2
        let key = "\(Int(size.width))x\(Int(size.height))@\(scale) \(scene.scheme.key) \(dark) \(scene.political) "
            + "\(scene.projection.centerLon) \(scene.geo.rings.count)"
        if let cached, cached.key == key {
            return cached.image
        }
        let image: NSImage = renderBase(scene, size: size, dark: dark, scale: scale)
        cached = (key, image)
        return image
    }

    private func renderBase(_ scene: WorldMapScene, size: CGSize, dark: Bool, scale: CGFloat) -> NSImage {
        let pixelsWide: Int = max(Int(size.width * scale), 1)
        let pixelsHigh: Int = max(Int(size.height * scale), 1)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(size: size)
        }
        rep.size = size
        let cg: CGContext = graphics.cgContext
        // y down, in points (the bitmap is `scale` times finer).
        cg.translateBy(x: 0, y: CGFloat(pixelsHigh))
        cg.scaleBy(x: scale, y: -scale)
        drawLand(scene, in: cg, size: size, dark: dark)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private func drawLand(_ scene: WorldMapScene, in cg: CGContext, size: CGSize, dark: Bool) {
        let width = Float(size.width)
        let height = Float(size.height)
        let projection: WorldMapModel = scene.projection
        cg.setFillColor(NSColor(argb: scene.scheme.ocean(dark: dark)).cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        let coast: CGColor = NSColor(argb: scene.scheme.coast(dark: dark)).cgColor
        let plainLand: UInt32 = scene.scheme.land(dark: dark)
        cg.setLineWidth(0.8)
        for (index, ring) in scene.geo.rings.enumerated() {
            let group: Int = index < scene.geo.ringGroups.count ? Int(scene.geo.ringGroups[index]) : 0
            let argb: UInt32 = scene.political && index < scene.geo.ringGroups.count
                ? MapPalette.politicalColor(group: group, dark: dark) : plainLand
            let fill: CGColor = NSColor(argb: argb).cgColor
            switch WorldMapModel.classify(ring: ring) {
            case .antarctic:
                for segment in projection.antarcticSegments(ring: ring, width: width, height: height) {
                    let quad = CGMutablePath()
                    quad.move(to: CGPoint(x: CGFloat(segment.x0), y: CGFloat(segment.y0)))
                    quad.addLine(to: CGPoint(x: CGFloat(segment.x1), y: CGFloat(segment.y1)))
                    quad.addLine(to: CGPoint(x: CGFloat(segment.x1), y: size.height))
                    quad.addLine(to: CGPoint(x: CGFloat(segment.x0), y: size.height))
                    quad.closeSubpath()
                    cg.setFillColor(fill)
                    cg.addPath(quad)
                    cg.fillPath()
                    cg.setStrokeColor(coast)
                    cg.move(to: CGPoint(x: CGFloat(segment.x0), y: CGFloat(segment.y0)))
                    cg.addLine(to: CGPoint(x: CGFloat(segment.x1), y: CGFloat(segment.y1)))
                    cg.strokePath()
                }
            case .archipelago:
                cg.setFillColor(fill)
                for dot in projection.archipelagoDots(ring: ring, width: width, height: height) {
                    cg.fillEllipse(in: CGRect(x: CGFloat(dot.x) - 1.8, y: CGFloat(dot.y) - 1.8, width: 3.6,
                                              height: 3.6))
                }
            case .land:
                let path = CGMutablePath()
                for point in projection.landPath(ring: ring, width: width, height: height) {
                    let at = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
                    if point.move {
                        path.move(to: at)
                    } else {
                        path.addLine(to: at)
                    }
                }
                cg.setFillColor(fill)
                cg.addPath(path)
                cg.fillPath()
                cg.setStrokeColor(coast)
                cg.addPath(path)
                cg.strokePath()
            }
        }
    }

    // MARK: - the moving layers

    private func drawOverlay(_ scene: WorldMapScene, in cg: CGContext, size: CGSize, dark: Bool) {
        let width = Float(size.width)
        let height = Float(size.height)
        let projection: WorldMapModel = scene.projection

        // The night side: one smooth area of 1 px columns.
        let nightPath = CGMutablePath()
        for column in scene.night {
            nightPath.addRect(CGRect(x: CGFloat(column.x), y: CGFloat(column.y0), width: 1,
                                     height: CGFloat(column.y1 - column.y0)))
        }
        cg.setFillColor(NSColor(argb: 0x5500_0000).cgColor)
        cg.addPath(nightPath)
        cg.fillPath()

        // The DXCC entities: a dot in the middle of each.
        for dot in scene.dots {
            let radius = CGFloat(WorldMapModel.dotRadius(dot.state))
            let x = CGFloat(projection.px(lon: dot.lon, width: width))
            let y = CGFloat(projection.py(lat: dot.lat, height: height))
            cg.setFillColor(NSColor(argb: Self.dotColor(dot.state)).cgColor)
            cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }

        // The coloured Maidenhead fields (20° × 10°).
        for rect in projection.fieldRects(fieldStates: scene.fieldStates, width: width, height: height) {
            guard let argb = MultGridLayout.color(rect.cell) else { continue }
            cg.setFillColor(NSColor(argb: argb).withAlphaComponent(0.55).cgColor)
            cg.fill(CGRect(x: CGFloat(rect.x), y: CGFloat(rect.y), width: CGFloat(rect.width),
                           height: CGFloat(rect.height)))
        }

        if !scene.dxccMode {
            cg.setStrokeColor(NSColor(argb: dark ? 0x33FF_FFFF : 0x2A00_0000).cgColor)
            cg.setLineWidth(1)
            for x in projection.verticalGridLines(width: width) {
                cg.move(to: CGPoint(x: CGFloat(x), y: 0))
                cg.addLine(to: CGPoint(x: CGFloat(x), y: size.height))
            }
            for y in projection.horizontalGridLines(height: height) {
                cg.move(to: CGPoint(x: 0, y: CGFloat(y)))
                cg.addLine(to: CGPoint(x: size.width, y: CGFloat(y)))
            }
            cg.strokePath()
        }

        // The Sun (the subsolar point).
        if let sun = projection.sunMarker(width: width, height: height, epochMillis: scene.nowMillis) {
            let center = CGPoint(x: CGFloat(sun.x), y: CGFloat(sun.y))
            cg.setFillColor(NSColor(argb: 0x33FF_EB3B).cgColor)
            cg.fillEllipse(in: CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28))
            cg.setFillColor(NSColor(argb: 0xFFFF_EB3B).cgColor)
            cg.fillEllipse(in: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
            cg.setStrokeColor(NSColor(argb: 0xFFF9_A825).cgColor)
            cg.setLineWidth(1.5)
            cg.strokeEllipse(in: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
        }

        // The station (a cross).
        if let station = scene.station {
            let x = CGFloat(projection.px(lon: station.lon, width: width))
            let y = CGFloat(projection.py(lat: station.lat, height: height))
            cg.setStrokeColor(NSColor(argb: 0xFFD8_1B60).cgColor)
            cg.setLineWidth(2.5)
            cg.move(to: CGPoint(x: x - 8, y: y))
            cg.addLine(to: CGPoint(x: x + 8, y: y))
            cg.move(to: CGPoint(x: x, y: y - 8))
            cg.addLine(to: CGPoint(x: x, y: y + 8))
            cg.strokePath()
        }

        // The labels of the coloured fields.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor(argb: dark ? 0xFFB0_BEC5 : 0xFF3A_4326),
        ]
        for label in projection.fieldLabels(fieldStates: scene.fieldStates, width: width, height: height) {
            NSAttributedString(string: label.key, attributes: attributes)
                .draw(at: CGPoint(x: CGFloat(label.x), y: CGFloat(label.y)))
        }
    }

    private static func dotColor(_ state: WorldMapModel.DotState) -> UInt32 {
        switch state {
        case .worked: return MultGridLayout.workedColor
        case .spotted: return MultGridLayout.spottedColor
        case .none: return 0x9988_8888
        }
    }
}
