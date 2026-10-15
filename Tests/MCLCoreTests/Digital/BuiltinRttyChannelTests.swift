import Foundation
@testable import MCLCore
import RTTYSignalKit
import Testing

/// The built-in RTTY modem's receiver behind fldigi's calls: the growing RX buffer, the tuning as fldigi's carrier,
/// the modes, and the transmission (`^r`, clear, abort, the echo of the own text). Synthetic audio only.
@Suite struct BuiltinRttyChannelTests {

    static func signal(_ text: String, markHz: Double = 2125, shiftHz: Double = 170, baud: Double = 45.45) -> [Double] {
        RTTYSignalGenerator(sampleRate: BuiltinRttyChannel.sampleRate, baud: baud, markHz: markHz, shiftHz: shiftHz,
                            amplitude: 0.3)
            .generate(text: text).map { Double($0) }
    }

    /// Feeds audio in the capture's blocks of 1024 samples.
    static func feed(_ channel: BuiltinRttyChannel, _ samples: [Double]) {
        var index = 0
        while index < samples.count {
            let end = min(index + 1024, samples.count)
            channel.receive(Array(samples[index..<end]))
            index = end
        }
    }

    /// Pulls the transmit audio until the transmission ends (at most `limit` samples).
    static func transmitted(_ channel: BuiltinRttyChannel, limit: Int = 600_000) -> [Float] {
        var audio: [Float] = []
        var buffer = [Float](repeating: 0, count: 512)
        while audio.count < limit {
            let active = buffer.withUnsafeMutableBufferPointer { channel.generate(into: $0, level: 1) }
            audio += buffer
            if !active {
                break
            }
        }
        return audio
    }

    @Test func decodedTextIsReadLikeFldigisBuffer() {
        let channel = BuiltinRttyChannel()
        #expect(channel.rxLength == 0)
        Self.feed(channel, Self.signal("CQ TEST DL1ABC\r\n"))
        let length: Int32 = channel.rxLength
        let text: String = channel.rxText(start: 0, length: length)
        #expect(text.contains("CQ TEST DL1ABC\n"), "\(text)")
        #expect(!text.contains("\r"))
        #expect(channel.rxText(start: 3, length: 4) == String(text.dropFirst(3).prefix(4)))
        Self.feed(channel, Self.signal("599 14\r\n"))
        #expect(channel.rxLength > length, "the length only grows")
        #expect(channel.rxText(start: length, length: 100).contains("599 14"))
    }

    @Test func carrierIsTheCentreAndTuningMovesTheDecoder() {
        let channel = BuiltinRttyChannel()
        #expect(channel.tuning.centreHz == 2210)
        channel.update { $0.afc = false }
        channel.setCentre(1385)
        #expect(channel.tuning.markHz == 1300)
        Self.feed(channel, Self.signal("TEST OK2ZZ OK2ZZ\r\n", markHz: 1300))
        #expect(channel.rxText(start: 0, length: 999).contains("OK2ZZ"))
        channel.update { $0.shiftHz = 850 }
        #expect(channel.tuning.shiftHz == 850)
        #expect(channel.tuning.markHz == 1300)
        channel.setCentre(2900)
        #expect(channel.tuning.markHz + channel.tuning.shiftHz <= 3000, "the space stays in the passband")
    }

    @Test func modesAreRttySpeeds() throws {
        let channel = BuiltinRttyChannel()
        #expect(channel.modeName == "RTTY")
        try channel.setMode("RTTY-75")
        #expect(channel.tuning.baud == 75)
        #expect(channel.modeName == "RTTY-75")
        #expect(throws: BuiltinRttyChannel.Unsupported.self) { try channel.setMode("BPSK31") }
        #expect(channel.tuning.baud == 75)
    }

    @Test func transmissionEndsAfterTheTextWithCaretR() {
        let channel = BuiltinRttyChannel()
        channel.addTx(" CQ TEST OK1XOE ^r")
        #expect(channel.trxState == "RX")
        #expect(channel.txOn())
        #expect(!channel.txOn(), "already on")
        #expect(channel.trxState == "TX")
        let audio: [Float] = Self.transmitted(channel)
        #expect(audio.count < 600_000, "the transmission ended")
        #expect(channel.trxState == "TX", "TX until the output has stopped and PTT is released")
        channel.finishTx()
        #expect(channel.trxState == "RX")
        let echo: String = channel.rxText(start: 0, length: channel.rxLength)
        #expect(echo.contains("CQ TEST OK1XOE"), "the own text is echoed: \(echo)")
        let decoder = BuiltinRttyChannel()
        Self.feed(decoder, audio.map { Double($0) } + [Double](repeating: 0, count: 6_000))
        #expect(decoder.rxText(start: 0, length: decoder.rxLength).contains("CQ TEST OK1XOE"))
    }

    @Test func receiveIsIgnoredWhileTransmitting() {
        let channel = BuiltinRttyChannel()
        channel.txOn()
        Self.feed(channel, Self.signal("DL1ABC DL1ABC\r\n"))
        #expect(channel.rxLength == 0)
        #expect(channel.abort())
        channel.finishTx()
        #expect(!channel.abort(), "nothing to abort")
    }

    @Test func abortAndClearDropTheQueue() {
        let channel = BuiltinRttyChannel()
        channel.addTx("RYRYRYRYRYRYRYRYRYRYRYRYRYRYRYRYRYRY ^r")
        channel.txOn()
        var buffer = [Float](repeating: 0, count: 512)
        _ = buffer.withUnsafeMutableBufferPointer { channel.generate(into: $0, level: 1) }
        #expect(channel.abort())
        let active = buffer.withUnsafeMutableBufferPointer { channel.generate(into: $0, level: 1) }
        #expect(!active)
        #expect(buffer.allSatisfy { $0 == 0 })
        channel.finishTx()
        // A held transmission (no ^r) keeps idling after the text was cleared.
        channel.addTx("TEXT THAT IS DROPPED")
        channel.clearTx()
        channel.txOn()
        let audio: [Float] = Self.transmitted(channel, limit: 60_000)
        #expect(audio.count >= 60_000, "a transmission without ^r idles until it is ended")
        channel.addTx("^r")
        _ = Self.transmitted(channel)
        channel.finishTx()
        #expect(!channel.rxText(start: 0, length: channel.rxLength).contains("DROPPED"))
    }

    @Test func levelScalesTheOutput() {
        let channel = BuiltinRttyChannel()
        channel.addTx("RY^r")
        channel.txOn()
        var peak: Float = 0
        var block = [Float](repeating: 0, count: 512)
        for _ in 0..<24 {
            _ = block.withUnsafeMutableBufferPointer { channel.generate(into: $0, level: 0.25) }
            peak = max(peak, block.map { abs($0) }.max() ?? 0)
        }
        #expect(peak > 0.05 && peak < 0.3, "\(peak)")
    }

    @Test func setupDefaultsAndStorage() {
        var setup = BuiltinModemSetup()
        #expect(!setup.flag(.linkedTuning))
        #expect(setup.flag(.pttViaCat))
        #expect(setup.outputLevel == 0.5)
        setup.set(.linkedTuning, flag: true)
        setup.set(.outputDevice, "USB Audio")
        setup.set(.outputLevel, "500")
        #expect(setup.values == ["linkedTuning": "true", "outputDevice": "USB Audio", "outputLevel": "500"])
        #expect(setup.outputLevel == 1)
        #expect(setup.outputDevice(side: 1) == "USB Audio", "radio 2 falls back to radio 1's output")
        setup.set(.linkedTuning, flag: false)
        #expect(setup.values["linkedTuning"] == nil, "defaults are not stored")
        var digital = DigitalConfig()
        digital.engine = .builtin
        #expect(digital.endpoint(0) == (DigitalConfig.builtinHost, 1))
        #expect(digital.endpoint(1) == (DigitalConfig.builtinHost, 2))
        #expect(digital.hasSecondFldigi)
    }
}
