import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// Port of `voice/SoundCardTest` (3 tests, same names) and the file side of playback and recording against the
/// maintainer-only probe (`PLAY.*`, `REC.wav`).
///
/// **No sound to a device and no microphone:** playback always goes via an output stand-in (`FakeOutput`,
/// which fails the test if someone who should not tries to open it), recording is verified only over the file
/// writer (`WavRecordingFile`) with synthetic PCM. Device enumeration is verified without calling CoreAudio.
@Suite struct SoundCardTests {

    /// A record of output stand-in calls.
    final class FakeOutput: SoundOutput, @unchecked Sendable {
        var events: [String] = []
        var chunks: [Int] = []
        var bytes: [UInt8] = []

        func write(_ chunk: ArraySlice<UInt8>) throws {
            chunks.append(chunk.count)
            bytes.append(contentsOf: chunk)
        }

        func stopAndFlush() { events.append("stopAndFlush") }
        func drain() { events.append("drain") }
        func close() { events.append("close") }
    }

    final class Factory: @unchecked Sendable {
        var opened: [(format: WavFile.PcmFormat, device: String?)] = []
        let output = FakeOutput()

        func make(_ format: WavFile.PcmFormat, _ device: String?) throws -> any SoundOutput {
            opened.append((format, device))
            return output
        }
    }

    /// An output that must not be opened.
    static func forbidden(_ format: WavFile.PcmFormat, _ device: String?) throws -> any SoundOutput {
        Issue.record("the output should not have been opened (\(format))")
        return FakeOutput()
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sc-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return URL(fileURLWithPath: dir.path).resolvingSymlinksInPath()
    }

    static func java(_ id: String) -> [[String]] {
        ProbeRows.rows(AudioIoMeasured.rows, id)
    }

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
    }

    /// A 16-bit mono 22,050 Hz wav with data (header like Java `WaveFileWriter`).
    static func wav(_ pcm: [UInt8], rate: Int32 = SoundCard.recordSampleRate) -> Data {
        Data(ContestRecorder.wavHeader(sampleRate: rate, data: Int64(pcm.count)) + pcm)
    }

    // MARK: - Java tests

    /// Java `deviceListingNeverThrows` over building the listing, **without CoreAudio**: the real enumeration
    /// (`AudioObjectGetPropertyData` → `coreaudiod`) is not called in tests — on CI machines without sound
    /// CoreAudio can hang for minutes and would block a thread of the shared pool (and tests do not touch audio devices).
    @Test func deviceListingNeverThrows() {
        // Java's pseudo-device is always first, duplicates (even the pseudo-device) are omitted.
        #expect(SoundCard.devices([]) == ["Default Audio Device"])
        #expect(SoundCard.devices(["B", "A", "B", "Default Audio Device", "A"])
            == ["Default Audio Device", "B", "A"])
    }

    @Test func notAWavIsReportedAsIoError() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bogus = dir.appendingPathComponent("cq.wav")
        try "tohle není wav".write(to: bogus, atomically: true, encoding: .utf8)

        #expect(throws: AudioIOError("Nepodporovaný formát wav: cq.wav")) {
            try SoundCard.play(try JavaPath(bogus.path), deviceName: "", cancelled: { false }, output: Self.forbidden)
        }
    }

    @Test func cancelledBeforeStartPlaysNothing() throws {
        // A valid wav (silence); cancelled at once → returns without waiting and the output is not even opened.
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wav = dir.appendingPathComponent("silence.wav")
        try Self.wav([UInt8](repeating: 0, count: Int(SoundCard.recordSampleRate) * 2)).write(to: wav)

        try SoundCard.play(try JavaPath(wav.path), deviceName: "", cancelled: { true }, output: Self.forbidden)
    }

    // MARK: - Files against Java

    /// File bytes of the probe (`playCase`) — the same building blocks.
    enum Build {
        static func le32(_ v: Int) -> [UInt8] { withUnsafeBytes(of: UInt32(truncatingIfNeeded: v).littleEndian, Array.init) }
        static func le16(_ v: Int) -> [UInt8] { withUnsafeBytes(of: UInt16(truncatingIfNeeded: v).littleEndian, Array.init) }
        static func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }

        /// Concatenates parts one after another — instead of a chain of `+` over arrays, which an older compiler in CI
        /// (Xcode 16) cannot type-check in time.
        static func cat(_ parts: [UInt8]...) -> [UInt8] {
            var out: [UInt8] = []
            for part in parts {
                out += part
            }
            return out
        }

        static func chunk(_ id: String, _ body: [UInt8]) -> [UInt8] {
            let pad: [UInt8] = body.count % 2 == 1 ? [0] : []
            return cat(ascii(id), le32(body.count), body, pad)
        }

        static func fmt(_ tag: Int, _ ch: Int, _ rate: Int, _ bits: Int, _ extra: [UInt8] = []) -> [UInt8] {
            let block = ch * bits / 8
            return cat(le16(tag), le16(ch), le32(rate), le32(rate * block), le16(block), le16(bits), extra)
        }

        static func riff(_ chunks: [UInt8]...) -> [UInt8] {
            let body: [UInt8] = chunks.flatMap { $0 }
            return cat(ascii("RIFF"), le32(4 + body.count), ascii("WAVE"), body)
        }

        static func pattern(_ n: Int) -> [UInt8] {
            (0..<n).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) }
        }

        static func extensible(_ validBits: Int, _ sub: Int) -> [UInt8] {
            let guid: [UInt8] = [0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xaa, 0, 0x38, 0x9b, 0x71]
            return cat(le16(22), le16(validBits), le32(4), le16(sub), guid)
        }

        static func be32(_ v: Int) -> [UInt8] { withUnsafeBytes(of: UInt32(v).bigEndian, Array.init) }

        /// `nil` = do not create the file; `[]` an empty file.
        static func cases() -> [(String, [UInt8]?)] {
            let pcm16 = pattern(400)
            let good = riff(chunk("fmt ", fmt(1, 1, 22050, 16)), chunk("data", pcm16))
            let truncated: [UInt8] = Array(riff(chunk("fmt ", fmt(1, 1, 22050, 16)), chunk("data", pattern(1000)))
                .prefix(44 + 10))
            var list: [(String, [UInt8]?)] = [
                ("text.wav", Array("tohle není wav".utf8)),
                ("empty.wav", []),
                ("missing.wav", nil),
                ("riff4.wav", ascii("RIFF")),
                ("riffOnly.wav", cat(ascii("RIFF"), le32(4), ascii("WAVE"))),
                ("noFmt.wav", riff(chunk("data", pcm16))),
                ("noData.wav", riff(chunk("fmt ", fmt(1, 1, 22050, 16)))),
                ("adpcm.wav", riff(chunk("fmt ", fmt(2, 1, 22050, 4)), chunk("data", pcm16))),
                ("tag0.wav", riff(chunk("fmt ", fmt(0, 1, 22050, 16)), chunk("data", pcm16))),
                ("rifx.wav", cat(ascii("RIFX"), Array(good.dropFirst(4)))),
                ("pcm16.wav", good),
                ("pcm16stereo.wav", riff(chunk("fmt ", fmt(1, 2, 44100, 16)), chunk("data", pcm16))),
                ("pcm8.wav", riff(chunk("fmt ", fmt(1, 1, 8000, 8)), chunk("data", pcm16))),
                ("pcm24.wav", riff(chunk("fmt ", fmt(1, 1, 22050, 24)), chunk("data", pattern(399)))),
                ("pcm32.wav", riff(chunk("fmt ", fmt(1, 1, 22050, 32)), chunk("data", pcm16))),
                ("float32.wav", riff(chunk("fmt ", fmt(3, 1, 22050, 32)), chunk("data", pcm16))),
                ("float64.wav", riff(chunk("fmt ", fmt(3, 1, 22050, 64)), chunk("data", pcm16))),
                ("alaw.wav", riff(chunk("fmt ", fmt(6, 1, 8000, 8, le16(0))), chunk("data", pcm16))),
                ("ulaw.wav", riff(chunk("fmt ", fmt(7, 1, 8000, 8, le16(0))), chunk("data", pcm16))),
                ("ext16.wav", riff(chunk("fmt ", fmt(0xFFFE, 1, 22050, 16, extensible(16, 1))), chunk("data", pcm16))),
                ("extFloat.wav", riff(chunk("fmt ", fmt(0xFFFE, 1, 22050, 32, extensible(32, 3))), chunk("data", pcm16))),
                ("extAdpcm.wav", riff(chunk("fmt ", fmt(0xFFFE, 1, 22050, 16, extensible(16, 2))), chunk("data", pcm16))),
            ]
            let more: [(String, [UInt8]?)] = [
                ("dataBeforeFmt.wav", riff(chunk("data", pcm16), chunk("fmt ", fmt(1, 1, 22050, 16)))),
                ("fmt18.wav", riff(chunk("fmt ", fmt(1, 1, 22050, 16, le16(0))), chunk("data", pcm16))),
                ("listFirst.wav", riff(chunk("LIST", ascii("INFOxxxx")), chunk("fmt ", fmt(1, 1, 22050, 16)),
                                       chunk("data", pcm16))),
                ("truncated.wav", truncated),
                ("oddData.wav", riff(chunk("fmt ", fmt(1, 1, 22050, 16)), chunk("data", pattern(5)))),
                ("zeroCh.wav", riff(chunk("fmt ", fmt(1, 0, 22050, 16)), chunk("data", pcm16))),
                ("zeroRate.wav", riff(chunk("fmt ", fmt(1, 1, 0, 16)), chunk("data", pcm16))),
                ("bits12.wav", riff(chunk("fmt ", fmt(1, 1, 22050, 12)), chunk("data", pcm16))),
                ("au.wav", cat(ascii(".snd"), be32(24), be32(400), be32(3), be32(22050), be32(1), pcm16)),
            ]
            list += more
            return list
        }
    }

    /// Java `AudioFormat.getSampleRate()` as text (`22050.0`).
    static func javaFloat(_ value: Float) -> String {
        value == value.rounded() ? String(Int(value)) + ".0" : String(value)
    }

    @Test func playFilesMatchJava() throws {
        let root = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("play")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("dir.wav"), withIntermediateDirectories: true)
        var files: [String: [UInt8]?] = [:]
        for (name, bytes) in Build.cases() {
            files[name] = bytes
            if let bytes {
                try Data(bytes).write(to: dir.appendingPathComponent(name))
            }
        }
        let fails = Self.java("PLAY.fail")
        let parses = Self.java("PLAY.parses")
        #expect(fails.count + parses.count == files.count + 1) // + dir.wav
        for row in fails {
            let path = try JavaPath(dir.appendingPathComponent(row[0]).path)
            let expected = AudioIOError(row[2].replacingOccurrences(of: "<dir>", with: root.path), javaClass: row[1])
            #expect(throws: expected, "\(row[0])") {
                try SoundCard.play(path, deviceName: nil, cancelled: { true }, output: Self.forbidden)
            }
        }
        for row in parses {
            let name = row[0]
            let bytes: [UInt8] = try #require(files[name] ?? nil)
            guard let wav = WavFile.parse(bytes) else {
                // Divergence: Java also reads AU with the .wav extension, here only RIFF/WAVE.
                #expect(name == "au.wav", "\(name) was not parsed")
                continue
            }
            let got: [String] = [wav.encoding.rawValue, Self.javaFloat(wav.sampleRate), String(wav.bits),
                                 String(wav.channels), String(wav.frameSize), "false", String(wav.frameLength)]
            #expect(got == Array(row[1...7]), "\(name)")
            let (format, stream) = wav.playable()
            let kind = wav.encoding == .pcmSigned ? "direct" : "convert"
            let digest: String = Self.hex(SHA256.hash(data: Data(stream)))
            var conv: String = "\(kind) \(stream.count) \(digest)"
            if kind == "convert" {
                conv += " " + Self.hex(stream)
                #expect(format.bits == 16 && format.frameSize == 2 * wav.channels)
            }
            #expect(conv == row[8], "\(name)")
        }
    }

    // MARK: - Playback over an output stand-in

    static func playFake(_ pcm: [UInt8], rate: Int32 = 22_050, device: String? = "X",
                         cancelAfter: Int = .max) throws -> Factory {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("m.wav")
        try wav(pcm, rate: rate).write(to: file)
        let factory = Factory()
        var checks = 0
        try SoundCard.play(try JavaPath(file.path), deviceName: device, cancelled: {
            checks += 1
            return checks > cancelAfter
        }, output: factory.make)
        return factory
    }

    @Test func playsInBlocksOf4096BytesThenDrains() throws {
        let pcm = Build.pattern(10_000)
        let factory = try Self.playFake(pcm, device: "Moje karta")
        #expect(factory.opened.count == 1)
        #expect(factory.opened.first?.device == "Moje karta")
        #expect(factory.opened.first?.format == WavFile.PcmFormat(sampleRate: 22_050, bits: 16, channels: 1, frameSize: 2))
        #expect(factory.output.chunks == [4096, 4096, 1808])
        #expect(factory.output.bytes == pcm)
        #expect(factory.output.events == ["drain", "close"])
    }

    @Test func cancelBetweenBlocksStopsAndFlushes() throws {
        let factory = try Self.playFake(Build.pattern(10_000), cancelAfter: 2)
        #expect(factory.output.chunks == [4096, 4096])
        #expect(factory.output.events == ["stopAndFlush", "close"])
    }

    @Test func emptyDataNeverOpensOutput() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("e.wav")
        try Self.wav([]).write(to: file)
        try SoundCard.play(try JavaPath(file.path), deviceName: nil, cancelled: { false }, output: Self.forbidden)
    }

    @Test func blockIsWholeFramesFor24Bit() throws {
        let header = Build.riff(Build.chunk("fmt ", Build.fmt(1, 1, 22050, 24)), Build.chunk("data", Build.pattern(9_000)))
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("w24.wav")
        try Data(header).write(to: file)
        let factory = Factory()
        try SoundCard.play(try JavaPath(file.path), deviceName: nil, cancelled: { false }, output: factory.make)
        #expect(factory.output.chunks == [4095, 4095, 810])
    }

    @Test func playerReadsDeviceNameOnEveryPlay() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("cq.wav")
        try "tohle není wav".write(to: file, atomically: true, encoding: .utf8)
        let reads = Counter()
        let out = SoundCard.player(deviceName: { reads.increment(); return "" }, output: Self.forbidden)
        let path = try JavaPath(file.path)
        #expect(throws: AudioIOError("Nepodporovaný formát wav: cq.wav")) { try out(path, { false }) }
        #expect(throws: AudioIOError("Nepodporovaný formát wav: cq.wav")) { try out(path, { false }) }
        #expect(reads.value == 2)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    /// Conversion of PCM to `Float32` for `AVAudioPlayerNode` (16 and 24 bit, negative values, channels).
    @Test func engineOutputConvertsSignedPcmToFloat() {
        let frames = 2
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { left.deallocate(); right.deallocate() }
        var channels: [UnsafeMutablePointer<Float>] = [left, right]
        let pcm16: [UInt8] = [0x00, 0x40, 0x00, 0x80, 0xFF, 0x7F, 0xFF, 0xFF]
        channels.withUnsafeMutableBufferPointer { pointers in
            EngineOutput.fill(UnsafePointer(pointers.baseAddress!), from: pcm16[...],
                              format: WavFile.PcmFormat(sampleRate: 8000, bits: 16, channels: 2, frameSize: 4), frames: 2)
        }
        #expect([left[0], right[0], left[1], right[1]] == [0.5, -1, Float(32767) / 32768, Float(-1) / 32768])
        let pcm24: [UInt8] = [0x00, 0x00, 0x40, 0x01, 0x00, 0x80]
        channels.withUnsafeMutableBufferPointer { pointers in
            EngineOutput.fill(UnsafePointer(pointers.baseAddress!), from: pcm24[...],
                              format: WavFile.PcmFormat(sampleRate: 8000, bits: 24, channels: 1, frameSize: 3), frames: 2)
        }
        #expect([left[0], left[1]] == [0.5, Float(-8_388_607) / 8_388_608])
    }

    // MARK: - Recording (file writer only, synthetic PCM)

    @Test func recordingFileMatchesJavaWaveFileWriter() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rows = Self.java("REC.wav")
        #expect(rows.count == 3)
        for row in rows {
            let count = Int(row[0])!
            let path = dir.appendingPathComponent("r\(count).wav").path
            let writer = WavRecordingFile(path: path, sampleRate: SoundCard.recordSampleRate)
            try writer.open()
            let pcm = Build.pattern(count)
            // In chunks, as they come from the converter.
            var offset = 0
            while offset < pcm.count {
                let end = min(pcm.count, offset + 1000)
                writer.append(Array(pcm[offset..<end]))
                offset = end
            }
            #expect(writer.finish() == nil)
            #expect(writer.finish() == nil)
            let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
            #expect([String(bytes.count), Self.hex(bytes.prefix(44)), Self.hex(SHA256.hash(data: Data(bytes)))]
                    == Array(row[1...3]), "REC.wav \(count)")
        }
    }

    @Test func recordingFileReportsOpenFailure() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("chybí").appendingPathComponent("x.wav.recording").path
        #expect(throws: AudioIOError(path + " (No such file or directory)", javaClass: "java.io.FileNotFoundException")) {
            try WavRecordingFile(path: path, sampleRate: 22_050).open()
        }
    }
}
