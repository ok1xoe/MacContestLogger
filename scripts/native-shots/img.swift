import CoreGraphics
import CoreText
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
// img crop IN OUT x y w h           (pixels, top-left origin)
// img compose SPEC.json OUT         {"w":2880,"h":1800,"bg":[r,g,b],"gradient":[[r,g,b],[r,g,b]],"items":[{"file":..,"x":..,"y":..,"scale":1}]}  RGB, no alpha
// img info IN
func load(_ p: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}
func save(_ img: CGImage, _ p: String) {
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: p) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}
let a = CommandLine.arguments
switch a[1] {
case "crop":
    let img = load(a[2])
    let r = CGRect(x: Double(a[4])!, y: Double(a[5])!, width: Double(a[6])!, height: Double(a[7])!)
    save(img.cropping(to: r)!, a[3])
case "info":
    let img = load(a[2]); print(img.width, img.height, img.alphaInfo.rawValue)
case "compose":
    let spec = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: a[2]))) as! [String: Any]
    let w = spec["w"] as! Int, h = spec["h"] as! Int
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    if let g = spec["gradient"] as? [[Double]] {
        let colors = g.map { CGColor(colorSpace: cs, components: [$0[0]/255, $0[1]/255, $0[2]/255, 1])! } as CFArray
        let grad = CGGradient(colorsSpace: cs, colors: colors, locations: nil)!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
    } else {
        let bg = spec["bg"] as? [Double] ?? [240, 240, 240]
        ctx.setFillColor(CGColor(colorSpace: cs, components: [bg[0]/255, bg[1]/255, bg[2]/255, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
    ctx.interpolationQuality = .high
    for item in spec["items"] as! [[String: Any]] {
        let img = load(item["file"] as! String)
        let s = item["scale"] as? Double ?? 1
        let x = item["x"] as! Double, y = item["y"] as! Double
        let iw = Double(img.width) * s, ih = Double(img.height) * s
        ctx.saveGState()
        if item["shadow"] as? Bool ?? true {
            ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 70,
                          color: CGColor(colorSpace: cs, components: [0, 0, 0, 0.55])!)
        }
        ctx.draw(img, in: CGRect(x: x, y: Double(h) - y - ih, width: iw, height: ih))
        ctx.restoreGState()
    }
    for t in spec["texts"] as? [[String: Any]] ?? [] {
        let size = t["size"] as? Double ?? 64
        let c = t["color"] as? [Double] ?? [255, 255, 255]
        let font = NSFont.systemFont(ofSize: size, weight: (t["bold"] as? Bool ?? false) ? .bold : .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font,
            .foregroundColor: NSColor(srgbRed: c[0]/255, green: c[1]/255, blue: c[2]/255, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: t["text"] as! String, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, [])
        var x = t["x"] as? Double ?? 0
        if t["center"] as? Bool ?? false { x = (Double(w) - bounds.width) / 2 }
        let y = t["y"] as! Double
        ctx.textPosition = CGPoint(x: x, y: Double(h) - y - size)
        CTLineDraw(line, ctx)
    }
    save(ctx.makeImage()!, a[3])
default: print("?")
}
