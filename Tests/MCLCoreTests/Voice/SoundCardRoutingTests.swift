import Foundation
import Testing
@testable import MCLCore

/// N1MM's SO2R DVK routing: a mono message played only on the left or the right channel (the other silent) over a
/// fake output — no sound device.
@Suite struct SoundCardRoutingTests {

    @Test func monoBecomesOneSidedStereo() {
        let mono = WavFile.PcmFormat(sampleRate: 22_050, bits: 16, channels: 1, frameSize: 2)
        let stream: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        let left = SoundCard.routed(stream, format: mono, channel: 1)
        #expect(left.format.channels == 2 && left.format.frameSize == 4)
        #expect(left.stream == [0x01, 0x02, 0, 0, 0x03, 0x04, 0, 0])
        let right = SoundCard.routed(stream, format: mono, channel: 2)
        #expect(right.stream == [0, 0, 0x01, 0x02, 0, 0, 0x03, 0x04])
        let both = SoundCard.routed(stream, format: mono, channel: 0)
        #expect(both.format == mono && both.stream == stream)
        let stereo = WavFile.PcmFormat(sampleRate: 22_050, bits: 16, channels: 2, frameSize: 4)
        #expect(SoundCard.routed(stream, format: stereo, channel: 1).stream == stream)
    }

    @Test func thePlayerRoutesTheMessage() throws {
        let dir = try SoundCardTests.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("cq.wav")
        try SoundCardTests.wav([0x10, 0x00, 0x20, 0x00]).write(to: file)
        let factory = SoundCardTests.Factory()
        let out = SoundCard.player(deviceName: { "Radio 2" }, gain: { 1 }, channel: { 2 }, output: factory.make)
        try out(try JavaPath(file.path), { false })
        #expect(factory.opened.first?.format.channels == 2)
        #expect(factory.opened.first?.device == "Radio 2")
        #expect(factory.output.bytes == [0, 0, 0x10, 0x00, 0, 0, 0x20, 0x00])
    }
}
