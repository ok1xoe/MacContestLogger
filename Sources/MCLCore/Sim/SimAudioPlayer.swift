import Foundation

/// Playback of the simulated band (Java `sim/SimAudioPlayer`): noise + scheduled CW signals mixed into the
/// default audio output. A signal is scheduled with a delay from "now".
///
/// A thin wrapper over the sound output (`SoundOutput`/`EngineOutput` = `AVAudioEngine`, default device): its own thread
/// `sim-audio` mixes blocks of 240 samples (20 ms, 16 bit mono LE, 12 kHz) and writes them with a blocking `write`
/// like the Java loop over `SourceDataLine`. The noise is Gaussian (polar method over the system generator, Java
/// `new Random().nextGaussian()`) through a mild low-pass. The output queue holds 4 blocks (80 ms), the Java line 8.
///
/// No playback test (Java has none; nothing in the tests plays to a device) — verified by hand.
/// Threads: `init` starts the audio engine and `close` waits up to 500 ms for the loop to end — both outside Swift's shared
/// pool; `play`/`clear`/`setNoiseLevel` are short under a lock.
public final class SimAudioPlayer: @unchecked Sendable {

    /// Java `SAMPLE_RATE` (12 kHz, `float` — input of `CwSynth.render`).
    public static let sampleRate: Float = 12_000
    static let block = 240 // 20 ms

    private struct Scheduled {
        let samples: [Float]
        let start: Int64
    }

    private let lock = NSLock()
    private let output: any SoundOutput
    private let finished = DispatchSemaphore(value: 0)
    /// State under `lock`.
    private var signals: [Scheduled] = []
    private var position: Int64 = 0
    private var noiseLevel: Double
    private var running = true
    private var closed = false

    /// Opens the default audio output and starts the loop. An unavailable output = `AudioIOError`
    /// (`Zvukové zařízení není dostupné: …`; Kotlin shows it in the status line).
    public convenience init(noiseLevel: Double) throws {
        try self.init(noiseLevel: noiseLevel) { format, device in
            try EngineOutput(format: format, deviceName: device)
        }
    }

    /// Core of `init` over any output.
    init(noiseLevel: Double, output: SoundOutputFactory) throws {
        self.noiseLevel = noiseLevel
        let format = WavFile.PcmFormat(sampleRate: Self.sampleRate, bits: 16, channels: 1, frameSize: 2)
        self.output = try output(format, nil)
        let thread = Thread { [self] in
            loop()
        }
        thread.name = "sim-audio"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func setNoiseLevel(_ level: Double) {
        lock.withLock { noiseLevel = level }
    }

    /// Schedules a signal after `delayMs` ms (Java `(long) (delayMs * SAMPLE_RATE / 1000)` in `float`).
    public func play(_ samples: [Float], delayMs: Int64) {
        let offset: Float = Float(delayMs) * Self.sampleRate / 1000
        lock.withLock {
            signals.append(Scheduled(samples: samples, start: position &+ JavaMath.d2l(Double(offset))))
        }
    }

    /// Discards scheduled signals (Esc).
    public func clear() {
        lock.withLock { signals.removeAll() }
    }

    /// One block: mixed signals from `position`, advancing the position and cleaning up finished ones (under the lock).
    private func mixBlock() -> (mix: [Float], noise: Double, running: Bool) {
        lock.withLock {
            var mix = [Float](repeating: 0, count: Self.block)
            for s in signals {
                for i in 0..<Self.block {
                    let idx: Int64 = position + Int64(i) - s.start
                    if idx >= 0 && idx < Int64(s.samples.count) {
                        mix[i] += s.samples[Int(idx)]
                    }
                }
            }
            let end: Int64 = position + Int64(Self.block)
            signals.removeAll { $0.start + Int64($0.samples.count) < end }
            position = end
            return (mix, noiseLevel, running)
        }
    }

    private func loop() {
        var noise = GaussianNoise()
        var buf = [UInt8](repeating: 0, count: Self.block * 2)
        var lp = 0.0
        while true {
            let (mix, level, active) = mixBlock()
            if !active {
                break
            }
            for i in 0..<Self.block {
                // Noise only mildly low-passed — sounds like a band, not like hissing.
                lp = lp * 0.6 + noise.next() * 0.4
                let v: Double = Double(mix[i]) + lp * level
                let scaled: Double = JavaMath.max(-32768, JavaMath.min(32767, v * 32767 * 0.5))
                let s: Int32 = JavaMath.d2i(scaled)
                buf[2 * i] = UInt8(truncatingIfNeeded: s)
                buf[2 * i + 1] = UInt8(truncatingIfNeeded: s >> 8)
            }
            do {
                try output.write(buf[...])
            } catch {
                break
            }
        }
        output.stopAndFlush()
        output.close()
        finished.signal()
    }

    /// Stops the loop and releases the output (waits at most 500 ms like Java `join(500)`; the loop closes the output itself
    /// once it finishes). A repeated call does nothing.
    public func close() {
        let first: Bool = lock.withLock {
            let was = closed
            closed = true
            running = false
            return !was
        }
        if first {
            _ = finished.wait(timeout: .now() + 0.5)
        }
    }
}

/// Java `nextGaussian` (polar method, second value of the pair in reserve) over the system generator.
private struct GaussianNoise {

    private var generator = SystemRandomNumberGenerator()
    private var spare: Double?

    mutating func next() -> Double {
        if let value = spare {
            spare = nil
            return value
        }
        var v1: Double
        var v2: Double
        var s: Double
        repeat {
            v1 = 2 * Double.random(in: 0..<1, using: &generator) - 1
            v2 = 2 * Double.random(in: 0..<1, using: &generator) - 1
            s = v1 * v1 + v2 * v2
        } while s >= 1 || s == 0
        let multiplier: Double = (-2 * log(s) / s).squareRoot()
        spare = v2 * multiplier
        return v1 * multiplier
    }
}
