import AVFoundation
import Foundation
import Testing
@testable import MCLCore

/// `AudioCapture` without a microphone (Java does not test these parts — "Newly written"): conversion of synthetic
/// `AVAudioPCMBuffer` to 12 kHz Int16 mono (`PcmStreamConverter`) and assembling blocks of 1,024 samples for
/// listeners (`accept`). The `AVAudioEngine` input node is not opened in the tests.
@Suite struct AudioCaptureTests {

    /// A Float32 non-interleaved buffer: channel 0 a sine of `hz` with amplitude `amplitude`, other channels silence.
    static func sine(rate: Double, channels: AVAudioChannelCount, frames: Int, hz: Double, amplitude: Float,
                     phase: Int = 0) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let data = buffer.floatChannelData!
        for i in 0..<frames {
            let t = Double(phase + i) / rate
            data[0][i] = amplitude * Float(sin(2 * Double.pi * hz * t))
            for c in 1..<Int(channels) {
                data[c][i] = 0
            }
        }
        return buffer
    }

    static func samples(_ pcm: [UInt8]) -> [Int16] {
        stride(from: 0, to: pcm.count - 1, by: 2).map { Int16(bitPattern: UInt16(pcm[$0]) | UInt16(pcm[$0 + 1]) << 8) }
    }

    /// Zero crossings from below upward → frequency.
    static func frequency(_ s: [Int16], rate: Double) -> Double {
        var crossings: [Int] = []
        for i in 1..<s.count where s[i - 1] < 0 && s[i] >= 0 {
            crossings.append(i)
        }
        guard let first = crossings.first, let last = crossings.last, crossings.count > 1 else { return 0 }
        return Double(crossings.count - 1) * rate / Double(last - first)
    }

    @Test func convertsStereo48kFloatTo12kMonoInt16() throws {
        let input = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let converter = try PcmStreamConverter(from: input, sampleRate: 12_000)
        #expect(converter.outputFormat.sampleRate == 12_000)
        #expect(converter.outputFormat.channelCount == 1)
        #expect(converter.outputFormat.commonFormat == .pcmFormatInt16)
        var pcm: [UInt8] = []
        // 10 buffers of 4,800 frames = 1 s, continuous phase across buffer boundaries.
        for k in 0..<10 {
            pcm += converter.convert(Self.sine(rate: 48_000, channels: 2, frames: 4_800, hz: 1_000, amplitude: 0.5,
                                               phase: k * 4_800))
        }
        #expect(pcm.count % 2 == 0)
        let s = Self.samples(pcm)
        // The resampler holds only a few samples of delay.
        #expect(s.count > 11_800 && s.count <= 12_000)
        let tail: [Int16] = Array(s.suffix(6_000))
        let peak: Int16 = tail.map { $0 == .min ? .max : abs($0) }.max() ?? 0
        #expect(peak > 15_500 && peak < 17_000) // 0,5 × 32 768 ≈ 16 384
        #expect(abs(Self.frequency(tail, rate: 12_000) - 1_000) < 2)
    }

    @Test func takesFirstChannelOfMultichannelInput() throws {
        let input = AVAudioFormat(standardFormatWithSampleRate: 12_000, channels: 2)!
        let converter = try PcmStreamConverter(from: input, sampleRate: 12_000)
        let pcm = converter.convert(Self.sine(rate: 12_000, channels: 2, frames: 2_400, hz: 600, amplitude: 0.25))
        let s = Self.samples(pcm)
        #expect(s.count == 2_400)
        let peak: Int16 = s.map { abs($0) }.max() ?? 0
        #expect(peak > 8_000 && peak <= 8_192)
    }

    @Test func sameRateMonoIsScaledExactly() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 12_000, channels: 1)!
        let converter = try PcmStreamConverter(from: format, sampleRate: 12_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)!
        buffer.frameLength = 4
        let values: [Float] = [0, 0.5, -0.5, -1]
        for (i, v) in values.enumerated() {
            buffer.floatChannelData![0][i] = v
        }
        #expect(Self.samples(converter.convert(buffer)) == [0, 16_384, -16_384, -32_768])
    }

    /// A tap with `format: nil`: a converter from the format of the first buffer, a new one on a format change.
    @Test func lazyConverterFollowsBufferFormat() {
        let converter = LazyConverter(sampleRate: 12_000)
        let a = converter.convert(Self.sine(rate: 12_000, channels: 1, frames: 1_200, hz: 600, amplitude: 0.25))
        #expect(a.count == 2_400)
        var b: [UInt8] = []
        for k in 0..<4 {
            b += converter.convert(Self.sine(rate: 48_000, channels: 2, frames: 4_800, hz: 600, amplitude: 0.25,
                                             phase: k * 4_800))
        }
        // A new 48 kHz → 12 kHz converter holds ~230 samples of resampler delay.
        #expect(b.count > 4_400 * 2 && b.count <= 4_800 * 2, "\(b.count)")
    }

    @Test func rejectsEmptyInputFormat() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 0, channels: 1)
        if let format {
            #expect(throws: AudioIOError.self) { try PcmStreamConverter(from: format, sampleRate: 12_000) }
        }
    }

    final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    @Test func listenersGetWholeBlocksRawFirst() {
        let capture = AudioCapture()
        let seen = Collected()
        let raw = capture.addRawListener { seen.add("raw \($0.count) \($0.first ?? 0)") }
        let samples = capture.addListener { seen.add("samples \($0.count) \($0.first ?? 0)") }
        let generation = capture.startWithoutDevice()
        #expect(capture.isRunning)
        // 1,000 + 1,500 + 2,000 bytes = 4,500 → two blocks of 2,048, the remainder 404 waits.
        let pcm: [UInt8] = (0..<4_500).map { UInt8(truncatingIfNeeded: $0 / 2048 + 1) }
        capture.accept(Array(pcm[0..<1_000]), generation: generation)
        #expect(seen.all.isEmpty)
        capture.accept(Array(pcm[1_000..<2_500]), generation: generation)
        capture.accept(Array(pcm[2_500..<4_500]), generation: generation)
        let one = AudioCapture.toSamples([1, 1])[0]
        let two = AudioCapture.toSamples([2, 2])[0]
        #expect(seen.all == ["raw 2048 1", "samples 1024 \(one)", "raw 2048 2", "samples 1024 \(two)"])

        capture.removeRawListener(raw)
        capture.accept([UInt8](repeating: 3, count: 2_048 - 404), generation: generation)
        #expect(seen.all.count == 5)
        #expect(seen.all.last?.hasPrefix("samples 1024") == true)
        capture.removeListener(samples)
    }

    @Test func closeDropsPendingAndStaleBlocks() {
        let capture = AudioCapture()
        let seen = Collected()
        _ = capture.addRawListener { seen.add("raw \($0.count)") }
        let generation = capture.startWithoutDevice()
        capture.accept([UInt8](repeating: 0, count: 2_000), generation: generation)
        capture.close()
        #expect(!capture.isRunning)
        capture.accept([UInt8](repeating: 0, count: 4_096), generation: generation)
        let next = capture.startWithoutDevice()
        #expect(next != generation)
        capture.accept([UInt8](repeating: 0, count: 4_096), generation: generation)
        #expect(seen.all.isEmpty)
        capture.accept([UInt8](repeating: 0, count: 2_048), generation: next)
        #expect(seen.all == ["raw 2048"])
    }
}
