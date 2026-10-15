// Adapted from RYRY's RTTYSignalDetector (https://github.com/ok1xoe/RYRY). Copyright 2026 OK1XOE, GNU LGPL v3
// (third-party/MMTTY/NOTICE.md).
import Foundation

/// Finds RTTY signals in the spectrum for the multi-channel receiver: pairs of peaks a shift apart (± tolerance)
/// above the noise floor. The MMTTY core's spectrum is logarithmic (≈ 3.4 units / dB). Frames are combined into a
/// slowly decaying peak hold — mark and space light up in turn, so one frame usually shows only one tone.
public struct BuiltinSignalDetector: Sendable {
    /// Minimum peak height above the noise floor (≈ 7 dB).
    public var threshold: Float = 24
    /// Relative tolerance of the peak spacing from the shift.
    public var tolerance = 0.15
    /// Decay of the held peak per frame.
    public var decay: Float = 3
    /// Maximum level difference of mark and space (otherwise not one signal).
    public var maxImbalance: Float = 60
    public private(set) var held: [Float] = []
    public private(set) var binHz = 0.0

    public init() {}

    public mutating func reset() {
        held = []
        binHz = 0
    }

    public mutating func update(_ frame: BuiltinRttyChannel.Spectrum) {
        if held.count != frame.magnitudes.count || binHz != frame.binHz {
            held = frame.magnitudes
            binHz = frame.binHz
            return
        }
        for index in held.indices {
            held[index] = max(frame.magnitudes[index], held[index] - decay)
        }
    }

    /// The marks (lower tones) of the signals found, strongest first.
    public func detect(shift: Double, fromHz: Double = 200, toHz: Double = 3000, maxCount: Int = 8) -> [Double] {
        Self.detect(magnitudes: held, binHz: binHz, shift: shift, fromHz: fromHz, toHz: toHz, maxCount: maxCount,
                    threshold: threshold, tolerance: tolerance, maxImbalance: maxImbalance)
    }

    public static func detect(magnitudes m: [Float], binHz: Double, shift: Double, fromHz: Double = 200,
                              toHz: Double = 3000, maxCount: Int = 8, threshold: Float = 24, tolerance: Double = 0.15,
                              maxImbalance: Float = 60) -> [Double] {
        guard binHz > 0, shift > 0, maxCount > 0, m.count > 4 else { return [] }
        let lo: Int = max(1, Int((fromHz / binHz).rounded(.down)))
        let hi: Int = min(m.count - 2, Int((toHz / binHz).rounded(.up)))
        guard hi - lo > 4 else { return [] }
        let sorted: [Float] = m[lo...hi].sorted()
        let level: Float = sorted[sorted.count / 2] + threshold
        var peaks: [(hz: Double, v: Float)] = []
        let merge: Double = shift / 3
        for i in lo...hi where m[i] >= level && m[i] >= m[i - 1] && m[i] > m[i + 1] {
            let a = Double(m[i - 1])
            let b = Double(m[i])
            let c = Double(m[i + 1])
            let den: Double = a - 2 * b + c
            let offset: Double = den != 0 ? max(-0.5, min(0.5, 0.5 * (a - c) / den)) : 0
            let hz: Double = (Double(i) + offset) * binHz
            if let last = peaks.last, hz - last.hz < merge {
                if m[i] > last.v {
                    peaks[peaks.count - 1] = (hz, m[i])
                }
            } else {
                peaks.append((hz, m[i]))
            }
        }
        var pairs: [(i: Int, j: Int, score: Float)] = []
        for i in peaks.indices {
            for j in peaks.indices where j > i {
                let distance: Double = peaks[j].hz - peaks[i].hz
                guard abs(distance - shift) <= shift * tolerance,
                      abs(peaks[i].v - peaks[j].v) <= maxImbalance else { continue }
                pairs.append((i, j, min(peaks[i].v, peaks[j].v)))
            }
        }
        pairs.sort { $0.score > $1.score }
        var used = Set<Int>()
        var spans: [ClosedRange<Double>] = []
        var marks: [Double] = []
        for pair in pairs where !used.contains(pair.i) && !used.contains(pair.j) {
            let span: ClosedRange<Double> = (peaks[pair.i].hz - shift / 2)...(peaks[pair.j].hz + shift / 2)
            guard !spans.contains(where: { $0.overlaps(span) }) else { continue }
            spans.append(span)
            used.insert(pair.i)
            used.insert(pair.j)
            marks.append((peaks[pair.i].hz + peaks[pair.j].hz) / 2 - shift / 2)
            if marks.count >= maxCount {
                break
            }
        }
        return marks
    }
}
