import AVFoundation
import Foundation

/// Streaming conversion of audio input buffers to 16-bit LE mono PCM at a given rate (a replacement for the Java
/// `TargetDataLine` opened in the format `AudioCapture.FORMAT` / `SoundCard.RECORD_FORMAT`).
/// `AVAudioConverter` keeps the resampler state between calls, so consecutive buffers give a continuous stream.
/// From a multichannel input it takes the **first channel** (the converter's default channel map, no mixing — with SO2R
/// interfaces the left and right receiver must not merge). Samples are not bit-identical to Java (a different resampler) — outside the gate.
///
/// Called from one thread (the input node tap calls it sequentially), hence `@unchecked Sendable`.
final class PcmStreamConverter: @unchecked Sendable {

    let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let ratio: Double

    init(from input: AVAudioFormat, sampleRate: Double) throws(AudioIOError) {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1,
                                         interleaved: true) else {
            throw AudioIOError("nepodporovaný formát " + String(sampleRate) + " Hz")
        }
        guard input.sampleRate > 0, input.channelCount > 0,
              let converter = AVAudioConverter(from: input, to: output) else {
            throw AudioIOError("nelze převést " + input.description)
        }
        self.outputFormat = output
        self.converter = converter
        self.ratio = sampleRate / input.sampleRate
    }

    /// Converts one input buffer; returns 16-bit LE mono bytes (may be empty — the resampler holds part back).
    func convert(_ input: AVAudioPCMBuffer) -> [UInt8] {
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 64
        var bytes: [UInt8] = []
        var supplied = false
        while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
                return bytes
            }
            var error: NSError?
            let status = converter.convert(to: buffer, error: &error) { _, inputStatus in
                if supplied {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return input
            }
            if let samples = buffer.int16ChannelData, buffer.frameLength > 0 {
                let count = Int(buffer.frameLength)
                bytes.reserveCapacity(bytes.count + count * 2)
                for i in 0..<count {
                    let value = UInt16(bitPattern: samples[0][i])
                    bytes.append(UInt8(truncatingIfNeeded: value))
                    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
                }
            }
            if status != .haveData || buffer.frameLength < buffer.frameCapacity {
                return bytes
            }
        }
    }
}

/// A `PcmStreamConverter` built from the format of the tap's first buffer (and again when the format changes); an unconvertible
/// format is silently dropped (a Java read would give zero bytes). Called only from the tap thread.
final class LazyConverter: @unchecked Sendable {
    private let sampleRate: Double
    private var converter: PcmStreamConverter?
    private var format: AVAudioFormat?

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [UInt8] {
        if converter == nil || format != buffer.format {
            format = buffer.format
            converter = try? PcmStreamConverter(from: buffer.format, sampleRate: sampleRate)
        }
        return converter?.convert(buffer) ?? []
    }
}

/// Audio input via `AVAudioEngine` (Java `TargetDataLine` + reader thread): input node tap →
/// `PcmStreamConverter` → `onPcm` on the caller's **own serial queue** (not on the audio thread and not in
/// Swift's shared pool). Device by CoreAudio name (`CoreAudioDevices.deviceID`, otherwise default).
///
/// For the app: microphone access needs `NSMicrophoneUsageDescription` in `Info.plist`
/// (without it macOS silences the input or rejects the start).
final class AudioInputEngine: @unchecked Sendable {

    private let sampleRate: Double
    private let deviceName: String?
    private let queue: DispatchQueue
    private let onPcm: @Sendable ([UInt8]) -> Void
    private let lock = NSLock()
    private var engine: AVAudioEngine?

    init(sampleRate: Double, deviceName: String?, queue: DispatchQueue, onPcm: @escaping @Sendable ([UInt8]) -> Void) {
        self.sampleRate = sampleRate
        self.deviceName = deviceName
        self.queue = queue
        self.onPcm = onPcm
    }

    /// Opens the input and starts sending PCM. Error = text for Java `… není dostupné: <text>`.
    func start() throws(AudioIOError) {
        lock.lock()
        defer { lock.unlock() }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let id = CoreAudioDevices.deviceID(named: deviceName, input: true), let unit = input.audioUnit {
            let status = CoreAudioDevices.select(id, on: unit)
            guard status == noErr else {
                throw AudioIOError("nelze vybrat zařízení (OSStatus " + String(status) + ")")
            }
        }
        // Hardware format after a device switch: `outputFormat(forBus:)` may remain from the old device
        // and `installTap` with a mismatched format ends in an uncatchable NSException. Hence the tap with `format: nil`
        // (hardware format) and the converter is built from the format of the first buffer (and again if the format changes).
        let hardware = input.inputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0 else {
            throw AudioIOError("vstup nemá žádný kanál")
        }
        let converter = LazyConverter(sampleRate: sampleRate)
        let queue = self.queue
        let onPcm = self.onPcm
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            let bytes = converter.convert(buffer)
            if !bytes.isEmpty {
                queue.async { onPcm(bytes) }
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioIOError(error.localizedDescription)
        }
        self.engine = engine
    }

    /// Stops the input; no more PCM arrives (blocks already queued run to completion).
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let engine else {
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }
}
