import Foundation
import ModemKit
import RTTYModem
import RTTYSignalKit
import Testing

/// Decode accuracy at MacContestLogger's receive rate (12 kHz, the rate of the shared receiver capture), in the
/// 1024-sample blocks the capture delivers: noise, a mistuned signal pulled in by AFC, and a second signal next to the
/// wanted one. Synthetic audio only (deterministic noise).
@Suite struct DecodeAccuracyTests {

    static let rate = 12_000.0
    static let exchange = "CQ TEST OK1XOE OK1XOE\r\nDL1ABC 599 14 14\r\nTU OK1XOE TEST\r\n"

    /// Levenshtein distance of the decoded text to the sent one (character errors).
    static func errors(_ got: String, _ want: String) -> Int {
        let a = Array(got), b = Array(want)
        guard !a.isEmpty else { return b.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in stride(from: 1, through: b.count, by: 1) {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }

    /// Feeds the samples in capture-sized blocks and collects the text from the modem's events.
    static func decode(_ modem: RTTYModem, _ samples: [Float]) async -> String {
        var index = 0
        while index < samples.count {
            let end = min(index + 1024, samples.count)
            samples[index..<end].withUnsafeBufferPointer { modem.processRx($0) }
            index = end
        }
        modem.finishEvents()
        var text = ""
        for await event in modem.events {
            if case .rxText(let character, _) = event {
                text.append(character)
            }
        }
        return text
    }

    /// Clean to noisy: the character error rate stays low down to a usable contest signal.
    @Test(arguments: [(0.0, 0), (0.05, 0), (0.25, 3)])
    func characterErrorRateInNoise(noiseRms: Double, maxErrors: Int) async throws {
        var samples = RTTYSignalGenerator(sampleRate: Self.rate, amplitude: 0.3).generate(text: Self.exchange)
        var noise = NoiseGenerator(seed: 0x5EED)
        noise.addNoise(to: &samples, rms: Float(noiseRms))
        let modem = try RTTYModem(sampleRate: Self.rate)
        let text = await Self.decode(modem, samples)
        #expect(Self.errors(text, Self.exchange) <= maxErrors, "\(text)")
    }

    /// A caller 40 Hz off the mark is pulled in by AFC and decoded; the tuning follows it.
    @Test func afcPullsInAnOffFrequencyCaller() async throws {
        let samples = RTTYSignalGenerator(sampleRate: Self.rate, markHz: 2165, amplitude: 0.3)
            .generate(text: "RYRYRYRYRY " + Self.exchange, leadIn: 2)
        let modem = try RTTYModem(sampleRate: Self.rate)
        let text = await Self.decode(modem, samples)
        #expect(text.contains("DL1ABC 599 14"), "\(text)")
        guard case .double(let mark)? = modem.get(parameter: "mark") else {
            Issue.record("no mark")
            return
        }
        #expect(abs(mark - 2165) < 15, "mark \(mark)")
    }

    /// Two signals 600 Hz apart: each decoder tuned to its own mark reads only its own station.
    @Test func twoSignalsTwoDecoders() async throws {
        let one = RTTYSignalGenerator(sampleRate: Self.rate, markHz: 1275, amplitude: 0.25).generate(text: "DE OK1AAA OK1AAA K\r\n")
        let two = RTTYSignalGenerator(sampleRate: Self.rate, markHz: 2125, amplitude: 0.25).generate(text: "DE DL2BBB DL2BBB K\r\n")
        let mixed = (0..<max(one.count, two.count)).map { i in
            (i < one.count ? one[i] : 0) + (i < two.count ? two[i] : 0)
        }
        let low = try RTTYModem(sampleRate: Self.rate)
        try low.set(parameter: "afc", value: .bool(false))
        try low.set(parameter: "mark", value: .double(1275))
        let high = try RTTYModem(sampleRate: Self.rate)
        try high.set(parameter: "afc", value: .bool(false))
        let lowText = await Self.decode(low, mixed)
        let highText = await Self.decode(high, mixed)
        #expect(lowText.contains("OK1AAA") && !lowText.contains("DL2BBB"), "\(lowText)")
        #expect(highText.contains("DL2BBB") && !highText.contains("OK1AAA"), "\(highText)")
    }

    /// The modulator's own audio, fed back at 12 kHz, decodes to the sent text (the loopback the built-in modem
    /// uses for its TX echo).
    @Test func transmitLoopbackAt12kHz() async throws {
        let tx = try RTTYModem(sampleRate: Self.rate)
        tx.queueTx(text: "CQ OK1XOE TEST")
        tx.beginTx(tune: false)
        var audio: [Float] = []
        var block = [Float](repeating: 0, count: 512)
        var stopping = false
        for _ in 0..<2_000 {
            let status = block.withUnsafeMutableBufferPointer { tx.generateTx(into: $0) }
            audio += block
            if status == .finished { break }
            if tx.txPending == 0 && !stopping {
                stopping = true
                tx.stopTx()
            }
        }
        let rx = try RTTYModem(sampleRate: Self.rate)
        let text = await Self.decode(rx, audio + [Float](repeating: 0, count: 6_000))
        #expect(text.contains("CQ OK1XOE TEST"), "\(text)")
    }
}
