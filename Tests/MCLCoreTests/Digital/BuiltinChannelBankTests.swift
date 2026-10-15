import Foundation
@testable import MCLCore
import RTTYSignalKit
import Testing

/// The multi-channel receiver (RYRY's channels, N1MM's RTTY browser): signals found in the spectrum get their own
/// decoders, at most the configured count; off = nothing decoded. Synthetic audio only.
@Suite struct BuiltinChannelBankTests {

    static func signal(_ text: String, markHz: Double) -> [Float] {
        RTTYSignalGenerator(sampleRate: 12_000, markHz: markHz, amplitude: 0.2)
            .generate(text: "RYRYRYRYRYRYRYRYRYRY " + text + " " + text + "\r\n", leadIn: 1.5)
    }

    static func mixed(_ parts: [[Float]]) -> [Double] {
        var out = [Double](repeating: 0, count: parts.map(\.count).max() ?? 0)
        for part in parts {
            for (index, sample) in part.enumerated() {
                out[index] += Double(sample)
            }
        }
        var noise = NoiseGenerator(seed: 7)
        for index in out.indices {
            out[index] += Double(noise.gaussian()) * 0.01
        }
        return out
    }

    static func run(_ source: BuiltinRttyChannel, _ bank: BuiltinChannelBank, _ audio: [Double]) {
        var index = 0
        while index < audio.count {
            let block = Array(audio[index..<min(index + 1024, audio.count)])
            source.receive(block)
            bank.feed(block)
            index += 1024
        }
        bank.flush()
    }

    @Test func signalsInTheSpectrumGetTheirOwnDecoders() {
        let source = BuiltinRttyChannel()
        let bank = BuiltinChannelBank(source: source)
        var config = BuiltinChannelBank.Config()
        config.enabled = true
        config.maxChannels = 8
        bank.configure(config)
        let audio: [Double] = Self.mixed([Self.signal("DE OK1AAA", markHz: 915),
                                          Self.signal("DE DL2BBB", markHz: 1515),
                                          Self.signal("DE W3CCC", markHz: 2215)])
        Self.run(source, bank, audio)
        let rows: [BuiltinChannelBank.Row] = bank.snapshot
        #expect(rows.count == 3, "\(rows.map(\.markHz))")
        let texts: String = rows.map(\.text).joined(separator: "|")
        for call in ["OK1AAA", "DL2BBB", "W3CCC"] {
            #expect(texts.contains(call), "\(call): \(texts)")
        }
        for row in rows {
            #expect([915.0, 1515, 2215].contains { abs($0 - row.markHz) < 20 }, "\(row.markHz)")
        }
        #expect(bank.dropped == 0)
    }

    @Test func theLimitAndOffAreKept() {
        let source = BuiltinRttyChannel()
        let bank = BuiltinChannelBank(source: source)
        var config = BuiltinChannelBank.Config()
        config.enabled = true
        config.maxChannels = 1
        bank.configure(config)
        let audio: [Double] = Self.mixed([Self.signal("DE OK1AAA", markHz: 915),
                                          Self.signal("DE DL2BBB", markHz: 1815)])
        Self.run(source, bank, audio)
        #expect(bank.snapshot.count == 1)
        config.enabled = false
        bank.configure(config)
        bank.flush()
        #expect(bank.snapshot.isEmpty)
        Self.run(source, bank, audio)
        #expect(bank.snapshot.isEmpty, "off: nothing decoded")
    }

    @Test func detectorFindsATonePair() {
        var magnitudes = [Float](repeating: 10, count: 1024)
        let binHz = 6_000.0 / 1024
        magnitudes[Int(1000 / binHz)] = 80
        magnitudes[Int(1170 / binHz)] = 78
        let marks: [Double] = BuiltinSignalDetector.detect(magnitudes: magnitudes, binHz: binHz, shift: 170)
        #expect(marks.count == 1)
        #expect(abs((marks.first ?? 0) - 1000) < 10)
        #expect(BuiltinSignalDetector.detect(magnitudes: magnitudes, binHz: binHz, shift: 850).isEmpty)
    }
}
