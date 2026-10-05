import Testing
@testable import MCLCore

/// `SoundCard.playPcm` — **only over a fake output, never a sound device**.
@Suite struct SoundCardPcmTests {

    final class Recorder: @unchecked Sendable {
        var formats: [WavFile.PcmFormat] = []
        var devices: [String?] = []
        var output = SoundCardTests.FakeOutput()

        func make(_ format: WavFile.PcmFormat, _ device: String?) throws -> any SoundOutput {
            formats.append(format)
            devices.append(device)
            return output
        }
    }

    struct Unavailable: Error, CustomStringConvertible {
        var description: String { "device gone" }
    }

    @Test func captureFormatIs12kHz16BitMono() {
        #expect(WavFile.PcmFormat.capture
                == WavFile.PcmFormat(sampleRate: 12_000, bits: 16, channels: 1, frameSize: 2))
    }

    @Test func writesAllBytesInBlocksThenDrainsAndCloses() throws {
        let recorder = Recorder()
        let pcm: [UInt8] = (0..<10_000).map { UInt8(truncatingIfNeeded: $0) }
        try SoundCard.playPcm(pcm, format: .capture, deviceName: nil, cancelled: { false }, output: recorder.make)
        #expect(recorder.formats == [.capture])
        #expect(recorder.devices == [nil])
        #expect(recorder.output.bytes == pcm)
        #expect(recorder.output.chunks == [4_096, 4_096, 1_808])
        #expect(recorder.output.events == ["drain", "close"])
    }

    /// Only whole frames are played (Kotlin `buf.size - buf.size % 2`).
    @Test func trailingHalfSampleIsDropped() throws {
        let recorder = Recorder()
        try SoundCard.playPcm([1, 2, 3], format: .capture, deviceName: nil, cancelled: { false }, output: recorder.make)
        #expect(recorder.output.bytes == [1, 2])
    }

    /// Like Kotlin the output opens even for an empty segment (an unavailable device is reported).
    @Test func emptySegmentStillOpensTheOutput() throws {
        let recorder = Recorder()
        try SoundCard.playPcm([], format: .capture, deviceName: nil, cancelled: { false }, output: recorder.make)
        #expect(recorder.formats.count == 1)
        #expect(recorder.output.events == ["drain", "close"])
    }

    @Test func cancelBetweenBlocksStopsAndFlushes() throws {
        let recorder = Recorder()
        var checks = 0
        try SoundCard.playPcm([UInt8](repeating: 0, count: 10_000), format: .capture, deviceName: nil,
                              cancelled: { checks += 1; return checks > 2 }, output: recorder.make)
        #expect(recorder.output.chunks == [4_096])
        #expect(recorder.output.events == ["stopAndFlush", "close"])
    }

    @Test func cancelledBeforeTheStartOpensNothing() throws {
        try SoundCard.playPcm([1, 2], format: .capture, deviceName: nil, cancelled: { true },
                              output: SoundCardTests.forbidden)
    }

    @Test func outputErrorsBecomeAudioErrors() {
        #expect(throws: AudioIOError("device gone")) {
            try SoundCard.playPcm([1, 2], format: .capture, deviceName: nil, cancelled: { false }) { _, _ in
                throw Unavailable()
            }
        }
        let typed = AudioIOError("Zvukové zařízení není dostupné: x")
        #expect(throws: typed) {
            try SoundCard.playPcm([1, 2], format: .capture, deviceName: nil, cancelled: { false }) { _, _ in
                throw typed
            }
        }
    }
}
