// Adapted from RYRY's WaterfallRenderer (https://github.com/ok1xoe/RYRY). Copyright 2026 OK1XOE, GNU LGPL v3
// (third-party/MMTTY/NOTICE.md).
import Foundation

/// The built-in modem's scrolling waterfall and line spectrum (MMTTY's FFT window): pure pixel logic, the newest row
/// on top; the view draws `pixels` as an image. Automatic gain follows a slowly decaying peak over a noise floor (the
/// 20th percentile), so a signal that ends does not stretch the noise to full brightness.
public struct BuiltinWaterfall: Sendable {
    public let width: Int
    public let height: Int
    /// RGBA bytes in memory (UInt32 little-endian 0xAABBGGRR), row 0 = the newest.
    public private(set) var pixels: [UInt32]
    /// The smoothed line spectrum (0…1): fast attack, slower decay.
    public private(set) var spectrumLine: [Float] = []
    /// Display gain in dB.
    public var gainDB: Double = 0
    private var peak: Float = 1
    private var floor: Float?
    /// Minimum dynamic range of the automatic gain (FFT units, ~18 dB).
    static let minRange: Float = 60
    static let decay: Float = 0.6

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        pixels = [UInt32](repeating: 0xFF00_0000, count: self.width * self.height)
    }

    /// Black → blue → cyan → yellow → white.
    static let stops: [(Float, (Float, Float, Float))] = [
        (0, (0, 0, 0)), (0.3, (0, 0, 0.8)), (0.55, (0, 0.8, 0.9)), (0.8, (1, 0.9, 0)), (1, (1, 1, 1)),
    ]

    static func color(_ value: Float) -> UInt32 {
        let t: Float = max(0, min(1, value))
        var i = 0
        while i < stops.count - 2 && t > stops[i + 1].0 {
            i += 1
        }
        let (t0, c0) = stops[i]
        let (t1, c1) = stops[i + 1]
        let k: Float = max(0, min(1, (t - t0) / max(0.0001, t1 - t0)))
        let r = UInt32((c0.0 + (c1.0 - c0.0) * k) * 255)
        let g = UInt32((c0.1 + (c1.1 - c0.1) * k) * 255)
        let b = UInt32((c0.2 + (c1.2 - c0.2) * k) * 255)
        return 0xFF00_0000 | (b << 16) | (g << 8) | r
    }

    /// A new spectrum row for the range `fromHz…toHz` (each pixel the strongest bin under it).
    public mutating func push(_ frame: BuiltinRttyChannel.Spectrum, fromHz: Double, toHz: Double) {
        guard frame.binHz > 0, toHz > fromHz, !frame.magnitudes.isEmpty else { return }
        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress, height > 1 else { return }
            (base + width).update(from: base, count: width * (height - 1))
        }
        var row = [Float](repeating: 0, count: width)
        let hzPerPixel: Double = (toHz - fromHz) / Double(width)
        for x in 0..<width {
            let lo = Int((fromHz + Double(x) * hzPerPixel) / frame.binHz)
            let hi: Int = max(lo + 1, Int((fromHz + Double(x + 1) * hzPerPixel) / frame.binHz))
            var magnitude: Float = 0
            if lo >= 0 && lo < frame.magnitudes.count {
                for i in lo..<min(hi, frame.magnitudes.count) {
                    magnitude = max(magnitude, frame.magnitudes[i])
                }
            }
            row[x] = magnitude
        }
        let frameMax: Float = row.max() ?? 0
        let sorted: [Float] = row.sorted()
        let p20: Float = sorted[sorted.count / 5]
        floor = floor.map { $0 * 0.9 + p20 * 0.1 } ?? p20
        let noise: Float = floor ?? 0
        peak = max(frameMax, noise + (peak - noise) * 0.995, 1)
        let gain = Float(pow(10, gainDB / 20))
        let range: Float = max(peak - noise, Self.minRange)
        let levels: [Float] = row.map { ($0 - noise) / range * gain }
        for x in 0..<width {
            pixels[x] = Self.color(levels[x])
        }
        if spectrumLine.count != width {
            spectrumLine = levels
        } else {
            for x in 0..<width {
                let value: Float = levels[x]
                let old: Float = spectrumLine[x]
                spectrumLine[x] = value > old ? value : old * Self.decay + value * (1 - Self.decay)
            }
        }
    }
}
