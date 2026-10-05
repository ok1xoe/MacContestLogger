import AVFoundation
import CoreAudio
import Foundation

/// Playback output (Java `SourceDataLine`): `write` blocks until the block fits in the device queue,
/// `stopAndFlush` discards what remains in the queue, `drain` waits for playback to finish, `close` releases the output.
protocol SoundOutput: AnyObject {
    func write(_ chunk: ArraySlice<UInt8>) throws
    func stopAndFlush()
    func drain()
    func close()
}

/// Opens an output for the stream format and device name (Java `getLine` + `open` + `start`).
typealias SoundOutputFactory = (_ format: WavFile.PcmFormat, _ deviceName: String?) throws -> any SoundOutput

/// Output via `AVAudioEngine` + `AVAudioPlayerNode`. PCM blocks are converted to `Float32`
/// and scheduled; at most `maxQueued` blocks wait in the queue (the Java line buffer), so `write` blocks
/// the caller (the voice keyer queue) and cancellation takes effect after at most that many blocks.
/// Device by CoreAudio name on the output node's audio unit, otherwise default.
///
/// Safeguard against hanging (Java could hang forever on a disconnected device): waiting for queue space
/// and for playback to finish has a limit of the scheduled audio length + 5 s.
final class EngineOutput: SoundOutput {

    static let maxQueued = 4

    private let format: WavFile.PcmFormat
    private let avFormat: AVAudioFormat
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let slots = DispatchSemaphore(value: EngineOutput.maxQueued)
    private let pending = DispatchGroup()
    private var scheduledSeconds = 0.0

    init(format: WavFile.PcmFormat, deviceName: String?) throws {
        self.format = format
        let width = format.channels > 0 ? format.frameSize / format.channels : 0
        guard format.sampleRate > 0, format.channels > 0, (1...4).contains(width),
              let avFormat = AVAudioFormat(standardFormatWithSampleRate: Double(format.sampleRate),
                                           channels: AVAudioChannelCount(format.channels)) else {
            throw AudioIOError("Zvukové zařízení není dostupné: nepodporovaný formát "
                               + String(format.sampleRate) + " Hz, " + String(format.bits) + " bit, "
                               + String(format.channels) + " kanálů")
        }
        self.avFormat = avFormat
        if let id = CoreAudioDevices.deviceID(named: deviceName, input: false), let unit = engine.outputNode.audioUnit {
            let status = CoreAudioDevices.select(id, on: unit)
            guard status == noErr else {
                throw AudioIOError("Zvukové zařízení není dostupné: OSStatus " + String(status))
            }
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: avFormat)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw AudioIOError("Zvukové zařízení není dostupné: " + error.localizedDescription)
        }
        player.play()
    }

    func write(_ chunk: ArraySlice<UInt8>) throws {
        let frames = chunk.count / format.frameSize
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        Self.fill(channels, from: chunk, format: format, frames: frames)
        let seconds = Double(frames) / Double(format.sampleRate)
        let limit = DispatchTime.now() + seconds * Double(Self.maxQueued) + 5
        guard slots.wait(timeout: limit) == .success else {
            throw AudioIOError("Zvukové zařízení neodpovídá")
        }
        scheduledSeconds += seconds
        pending.enter()
        let slots = self.slots
        let pending = self.pending
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            slots.signal()
            pending.leave()
        }
    }

    /// Signed LE PCM (sample width = frame / channels) → `Float32` per channel, `v / 2^(container bits − 1)`.
    static func fill(_ channels: UnsafePointer<UnsafeMutablePointer<Float>>, from chunk: ArraySlice<UInt8>,
                     format: WavFile.PcmFormat, frames: Int) {
        let width = format.frameSize / format.channels
        let scale = Float(1) / Float(sign: .plus, exponent: width * 8 - 1, significand: 1)
        var index = chunk.startIndex
        for frame in 0..<frames {
            for channel in 0..<format.channels {
                var value: Int32 = 0
                for byte in 0..<width {
                    value |= Int32(chunk[index + byte]) << (8 * (byte + 4 - width))
                }
                index += width
                channels[channel][frame] = Float(value >> (8 * (4 - width))) * scale
            }
        }
    }

    func stopAndFlush() {
        player.stop()
    }

    func drain() {
        _ = pending.wait(timeout: DispatchTime.now() + scheduledSeconds + 5)
    }

    func close() {
        player.stop()
        engine.stop()
    }
}
