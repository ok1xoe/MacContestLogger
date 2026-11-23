import AudioToolbox
import AVFoundation
import CoreAudio
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

    /// `channels` 1 = the first input channel; 2 = the first two as interleaved left/right (a mono input on both).
    init(from input: AVAudioFormat, sampleRate: Double, channels: Int = 1) throws(AudioIOError) {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                                         channels: AVAudioChannelCount(channels == 2 ? 2 : 1), interleaved: true) else {
            throw AudioIOError("nepodporovaný formát " + String(sampleRate) + " Hz")
        }
        guard input.sampleRate > 0, input.channelCount > 0,
              let converter = AVAudioConverter(from: input, to: output) else {
            throw AudioIOError("nelze převést " + input.description)
        }
        if channels == 2 {
            // Left = input channel 0, right = input channel 1 (or 0 again for a mono input): no mixing.
            converter.channelMap = input.channelCount >= 2 ? [0, 1] : [0, 0]
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
                let count = Int(buffer.frameLength) * Int(outputFormat.channelCount)
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
    private let channels: Int
    private var converter: PcmStreamConverter?
    private var format: AVAudioFormat?

    init(sampleRate: Double, channels: Int = 1) {
        self.sampleRate = sampleRate
        self.channels = channels
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [UInt8] {
        if converter == nil || format != buffer.format {
            format = buffer.format
            converter = try? PcmStreamConverter(from: buffer.format, sampleRate: sampleRate, channels: channels)
        }
        return converter?.convert(buffer) ?? []
    }
}

/// What the render callback of the input unit needs (kept alive by `AudioInputEngine` between `start` and `stop`).
private final class InputContext: @unchecked Sendable {
    var unit: AudioUnit?
    let buffer: AVAudioPCMBuffer
    let bytesPerFrame: UInt32
    let converter: LazyConverter
    let queue: DispatchQueue
    let onPcm: @Sendable ([UInt8]) -> Void

    init(buffer: AVAudioPCMBuffer, bytesPerFrame: UInt32, converter: LazyConverter, queue: DispatchQueue,
         onPcm: @escaping @Sendable ([UInt8]) -> Void) {
        self.buffer = buffer
        self.bytesPerFrame = bytesPerFrame
        self.converter = converter
        self.queue = queue
        self.onPcm = onPcm
    }
}

/// The input unit calls this on the audio thread for every block: it pulls the block, converts it and hands the PCM
/// to the caller's queue.
private let inputRenderCallback: AURenderCallback = { refCon, flags, timestamp, bus, frames, _ in
    let context = Unmanaged<InputContext>.fromOpaque(refCon).takeUnretainedValue()
    guard let unit = context.unit, frames <= context.buffer.frameCapacity else {
        return noErr
    }
    let list = context.buffer.mutableAudioBufferList
    list.pointee.mBuffers.mDataByteSize = frames * context.bytesPerFrame
    let status = AudioUnitRender(unit, flags, timestamp, bus, frames, list)
    guard status == noErr else {
        return status
    }
    context.buffer.frameLength = frames
    let bytes = context.converter.convert(context.buffer)
    if !bytes.isEmpty {
        let queue = context.queue
        let onPcm = context.onPcm
        queue.async { onPcm(bytes) }
    }
    return noErr
}

/// Audio input from one CoreAudio device through an **input-only** HAL unit (Java `TargetDataLine` + reader thread):
/// the unit's render callback → `PcmStreamConverter` → `onPcm` on the caller's **own serial queue** (not on the
/// audio thread and not in Swift's shared pool). Device by CoreAudio name (`CoreAudioDevices.deviceID`, otherwise the
/// system default input).
///
/// Not `AVAudioEngine`: its graph also initialises the output side, which on some devices (a USB codec next to a
/// different default output) fails with `-10868` (`FormatNotSupported`) at `start()`. The HAL unit with the output
/// disabled has no such dependency (MCL-152).
///
/// For the app: microphone access needs `NSMicrophoneUsageDescription` in `Info.plist`
/// (without it macOS silences the input or rejects the start).
final class AudioInputEngine: @unchecked Sendable {

    private let sampleRate: Double
    private let channels: Int
    private let deviceName: String?
    private let queue: DispatchQueue
    private let onPcm: @Sendable ([UInt8]) -> Void
    private let lock = NSLock()
    private var unit: AudioUnit?
    private var context: Unmanaged<InputContext>?

    /// `channels` 2 = interleaved left/right PCM (`PcmStreamConverter`).
    init(sampleRate: Double, channels: Int = 1, deviceName: String?, queue: DispatchQueue,
         onPcm: @escaping @Sendable ([UInt8]) -> Void) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.deviceName = deviceName
        self.queue = queue
        self.onPcm = onPcm
    }

    /// Opens the input and starts sending PCM. Error = text for Java `… není dostupné: <text>`.
    func start() throws(AudioIOError) {
        lock.lock()
        defer { lock.unlock() }
        guard unit == nil else {
            return
        }
        guard let deviceID = CoreAudioDevices.deviceID(named: deviceName, input: true)
                ?? CoreAudioDevices.defaultInputDeviceID() else {
            throw AudioIOError("žádný zvukový vstup")
        }
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                    componentSubType: kAudioUnitSubType_HALOutput,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple,
                                                    componentFlags: 0, componentFlagsMask: 0)
        var created: AudioUnit?
        guard let component = AudioComponentFindNext(nil, &description),
              AudioComponentInstanceNew(component, &created) == noErr, let unit = created else {
            throw AudioIOError("nelze otevřít zvukový vstup")
        }
        do throws(AudioIOError) {
            let context = try configure(unit, deviceID: deviceID)
            let status: OSStatus = AudioUnitInitialize(unit)
            guard status == noErr else {
                throw AudioIOError("nelze inicializovat zvukový vstup (OSStatus " + String(status) + ")")
            }
            let started: OSStatus = AudioOutputUnitStart(unit)
            guard started == noErr else {
                AudioUnitUninitialize(unit)
                context.release()
                throw AudioIOError("nelze spustit zvukový vstup (OSStatus " + String(started) + ")")
            }
            self.unit = unit
            self.context = context
        } catch {
            AudioComponentInstanceDispose(unit)
            throw error
        }
    }

    /// Input enabled, output disabled, the device, the client format (the device's own rate and channels, 32-bit
    /// float, interleaved — the sample-rate conversion is `PcmStreamConverter`'s) and the render callback.
    private func configure(_ unit: AudioUnit, deviceID: AudioDeviceID) throws(AudioIOError) -> Unmanaged<InputContext> {
        func check(_ what: String, _ status: OSStatus) throws(AudioIOError) {
            if status != noErr {
                throw AudioIOError("nelze nastavit zvukový vstup: " + what + " (OSStatus " + String(status) + ")")
            }
        }
        var on: UInt32 = 1
        var off: UInt32 = 0
        try check("vstup", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, 4))
        try check("výstup", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, 4))
        var device = deviceID
        try check("zařízení", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                                    &device, UInt32(MemoryLayout<AudioDeviceID>.size)))
        var hardware = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check("formát zařízení", AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1,
                                                          &hardware, &size))
        guard hardware.mSampleRate > 0, hardware.mChannelsPerFrame > 0,
              let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | hardware.mChannelsPerFrame) else {
            throw AudioIOError("vstup nemá žádný kanál")
        }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hardware.mSampleRate,
                                   interleaved: true, channelLayout: layout)
        var client = format.streamDescription.pointee
        try check("formát", AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &client,
                                                 UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else {
            throw AudioIOError("nelze alokovat vyrovnávací paměť")
        }
        let context = Unmanaged.passRetained(InputContext(
            buffer: buffer, bytesPerFrame: client.mBytesPerFrame,
            converter: LazyConverter(sampleRate: sampleRate, channels: channels), queue: queue, onPcm: onPcm))
        context.takeUnretainedValue().unit = unit
        var callback = AURenderCallbackStruct(inputProc: inputRenderCallback, inputProcRefCon: context.toOpaque())
        let status: OSStatus = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                                                    &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        if status != noErr {
            context.release()
            throw AudioIOError("nelze nastavit zvukový vstup: callback (OSStatus " + String(status) + ")")
        }
        return context
    }

    /// Stops the input; no more PCM arrives (blocks already queued run to completion).
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let unit else {
            return
        }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        context?.release()
        self.unit = nil
        context = nil
    }
}
