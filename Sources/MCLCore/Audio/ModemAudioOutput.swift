import AVFoundation
import Foundation

/// A running transmit audio stream of a sound-card modem (the built-in RTTY modem's AFSK).
public protocol ModemAudioStream: AnyObject, Sendable {
    /// Stops the output (not from the pull callback).
    func stop()
}

/// The transmit audio of a sound-card modem on a sound output: an `AVAudioEngine` source node at the modem's rate
/// (mono float), the engine converts to the device's rate. `pull` fills each buffer on the render thread — it must be
/// fast and must not block for long. The device is chosen by its CoreAudio name (empty / not found = default).
///
/// Only the running app opens it (`HardwarePorts.live`); tests use a fake stream they pull themselves.
public final class ModemAudioOutput: ModemAudioStream, @unchecked Sendable {

    private let lock = NSLock()
    private var engine: AVAudioEngine?

    private init() {}

    /// Opens the output and starts pulling. Error: the device cannot be opened.
    public static func open(deviceName: String?, sampleRate: Double,
                            pull: @escaping @Sendable (UnsafeMutableBufferPointer<Float>) -> Void)
        throws(AudioIOError) -> ModemAudioOutput {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1,
                                         interleaved: false) else {
            throw AudioIOError("nepodporovaný formát " + String(sampleRate) + " Hz")
        }
        let engine = AVAudioEngine()
        if let id = CoreAudioDevices.deviceID(named: deviceName, input: false),
           let unit = engine.outputNode.audioUnit {
            let status = CoreAudioDevices.select(id, on: unit)
            guard status == noErr else {
                throw AudioIOError("nelze vybrat zařízení (OSStatus " + String(status) + ")")
            }
        }
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = buffers.first, let data = first.mData else { return noErr }
            let samples = data.assumingMemoryBound(to: Float.self)
            pull(UnsafeMutableBufferPointer(start: samples, count: Int(frameCount)))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw AudioIOError(error.localizedDescription)
        }
        let output = ModemAudioOutput()
        output.engine = engine
        return output
    }

    public func stop() {
        let engine: AVAudioEngine? = lock.withLock {
            let running = self.engine
            self.engine = nil
            return running
        }
        engine?.stop()
    }
}
