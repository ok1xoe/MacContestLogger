import Foundation

/// The sound-card CW monitor's audio: a sine tone keyed by the same element sequence the keyer sends, each mark
/// shaped with raised-cosine edges (no clicks), as 16-bit signed little-endian mono PCM.
public enum CwToneRenderer {

    public static let sampleRate = 24_000
    public static let format = WavFile.PcmFormat(sampleRate: Float(sampleRate), bits: 16, channels: 1, frameSize: 2)
    /// The rise and fall time of a mark.
    public static let rampMs = 4.0

    /// `leadingSilenceMs` (the PTT delay of DTR/RTS keying) goes before the first mark; `volume` is 0…1.
    public static func render(_ elements: [CwElement], pitchHz: Int, volume: Double,
                              leadingSilenceMs: Double = 0) -> [UInt8] {
        let rate = Double(sampleRate)
        let amplitude: Double = min(max(volume, 0), 1) * 32_000
        let step: Double = 2 * Double.pi * Double(max(100, pitchHz)) / rate
        var samples: [Int16] = []
        var clock: Double = leadingSilenceMs
        var written = 0
        samples.reserveCapacity(Int((CwElements.duration(elements) + leadingSilenceMs) * rate / 1_000) + 1)
        func samplesUntil(_ ms: Double) -> Int {
            Int((ms * rate / 1_000).rounded())
        }
        samples.append(contentsOf: repeatElement(0, count: samplesUntil(clock)))
        written = samples.count
        for element in elements {
            let end: Int = samplesUntil(clock + element.ms)
            let count: Int = max(0, end - written)
            if element.keyDown && amplitude > 0 {
                let ramp: Int = min(Int(rampMs * rate / 1_000), count / 2)
                for i in 0..<count {
                    var gain = 1.0
                    if ramp > 0 && i < ramp {
                        gain = 0.5 - 0.5 * cos(Double.pi * Double(i) / Double(ramp))
                    } else if ramp > 0 && i >= count - ramp {
                        gain = 0.5 - 0.5 * cos(Double.pi * Double(count - 1 - i) / Double(ramp))
                    }
                    let phase: Double = step * Double(written + i)
                    samples.append(Int16((amplitude * gain * sin(phase)).rounded()))
                }
            } else {
                samples.append(contentsOf: repeatElement(0, count: count))
            }
            written += count
            clock += element.ms
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(samples.count * 2)
        for sample in samples {
            let bits = UInt16(bitPattern: sample)
            bytes.append(UInt8(bits & 0xFF))
            bytes.append(UInt8(bits >> 8))
        }
        return bytes
    }
}
