import AVFoundation
import Foundation

/// What a voice message file looks like (Settings → Function Keys shows it next to the key).
public struct VoiceMessageFile: Equatable, Sendable {
    public let bytes: Int
    /// Playing time; `nil` when the voice keyer cannot read the file as a wav.
    public let seconds: Double?

    public init(bytes: Int, seconds: Double?) {
        self.bytes = bytes
        self.seconds = seconds
    }
}

/// Why a chosen audio file cannot become a voice message.
public enum VoiceImportError: Error, Equatable, Sendable {
    case unreadable(String)
    case tooBig
    case tooLong(Int)
    case unsupportedFormat
    case empty
}

/// A file checked and ready to be written as a voice message.
public struct VoiceImport: Equatable, Sendable {
    /// The bytes of the wav file to store.
    public let bytes: [UInt8]
    public let seconds: Double
    /// `true` when the source was converted to 16-bit mono 22,050 Hz wav (otherwise the bytes are the source's).
    public let converted: Bool
}

/// Validation, inspection and conversion of audio files that become voice messages. The voice keyer plays RIFF/WAVE
/// files (PCM, float, A-law, μ-law; mono or stereo, 4–192 kHz) — such a file is copied byte for byte; any other
/// audio file AVFoundation can read (AIFF, CAF, MP3, M4A…) and a wav the keyer cannot play are converted to the
/// recording format (16-bit mono PCM, 22,050 Hz).
public enum VoiceWavImport {

    /// Longest voice message accepted, seconds.
    public static let maxSeconds = 300
    /// Largest source file accepted, bytes.
    public static let maxBytes = 64 * 1_024 * 1_024

    /// The extensions the file panel offers.
    public static let extensions: [String] = ["wav", "wave", "aif", "aiff", "aifc", "caf", "mp3", "m4a"]

    /// What the voice keyer would make of `bytes`.
    public static func inspect(_ bytes: [UInt8]) -> VoiceMessageFile {
        guard let wav = WavFile.parse(bytes), isPlayable(wav) else {
            return VoiceMessageFile(bytes: bytes.count, seconds: nil)
        }
        return VoiceMessageFile(bytes: bytes.count, seconds: seconds(of: wav))
    }

    private static func seconds(of wav: WavFile) -> Double {
        Double(wav.data.count / max(1, wav.frameSize)) / Double(wav.sampleRate)
    }

    private static func isPlayable(_ wav: WavFile) -> Bool {
        // Signed PCM plays as it is; every other encoding is converted to 16 bit.
        let width: Int = wav.encoding == .pcmSigned ? wav.frameSize / max(1, wav.channels) : 2
        return (1...2).contains(wav.channels) && wav.sampleRate >= 4_000 && wav.sampleRate <= 192_000
            && (2...4).contains(width)
    }

    /// Reads and checks `url`.
    public static func prepare(_ url: URL) throws(VoiceImportError) -> VoiceImport {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes?[.size] as? Int, size > maxBytes { throw .tooBig }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
        let bytes = [UInt8](data)
        if let wav = WavFile.parse(bytes), isPlayable(wav) {
            let length = seconds(of: wav)
            if wav.data.isEmpty { throw .empty }
            if length > Double(maxSeconds) { throw .tooLong(maxSeconds) }
            return VoiceImport(bytes: bytes, seconds: length, converted: false)
        }
        return try convert(url)
    }

    /// AVFoundation → 16-bit mono 22,050 Hz wav.
    static func convert(_ url: URL) throws(VoiceImportError) -> VoiceImport {
        let rate = Double(SoundCard.recordSampleRate)
        do {
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let source = file.processingFormat
            guard file.length > 0 else { throw VoiceImportError.empty }
            let inSeconds = Double(file.length) / source.sampleRate
            if inSeconds > Double(maxSeconds) { throw VoiceImportError.tooLong(maxSeconds) }
            guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1,
                                             interleaved: true),
                  let converter = AVAudioConverter(from: source, to: target),
                  let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 16_384) else {
                throw VoiceImportError.unsupportedFormat
            }
            var pcm: [UInt8] = []
            let capacity = AVAudioFrameCount(rate)
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
                throw VoiceImportError.unsupportedFormat
            }
            var finished = false
            while !finished {
                output.frameLength = 0
                var failure: NSError?
                let status = converter.convert(to: output, error: &failure) { _, inputStatus in
                    do {
                        try file.read(into: input, frameCount: 16_384)
                    } catch {
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    if input.frameLength == 0 {
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    inputStatus.pointee = .haveData
                    return input
                }
                if status == .error { throw VoiceImportError.unsupportedFormat }
                if let samples = output.int16ChannelData?[0], output.frameLength > 0 {
                    samples.withMemoryRebound(to: UInt8.self, capacity: Int(output.frameLength) * 2) {
                        pcm.append(contentsOf: UnsafeBufferPointer(start: $0, count: Int(output.frameLength) * 2))
                    }
                }
                finished = status == .endOfStream || output.frameLength == 0
            }
            if pcm.isEmpty { throw VoiceImportError.empty }
            let length = Double(pcm.count / 2) / rate
            if length > Double(maxSeconds) { throw VoiceImportError.tooLong(maxSeconds) }
            let header = ContestRecorder.wavHeader(sampleRate: SoundCard.recordSampleRate, data: Int64(pcm.count))
            return VoiceImport(bytes: header + pcm, seconds: length, converted: true)
        } catch let error as VoiceImportError {
            throw error
        } catch {
            throw .unsupportedFormat
        }
    }
}
