import Foundation
import os

/// Continuous capture of audio from the sound card input (receiver output) for the waterfall, CW decoder and recording
/// (Java `audio/AudioCapture`). Samples go to listeners **in blocks of 1 024 samples** (2 048 bytes, Java
/// `line.read(buf)` reads a whole buffer) as `Double` −1…1 from its own serial queue `audio-capture`
/// (the Java reader thread); a listener must be fast or hand work off. Order within a block as in Java:
/// first all raw listeners (PCM for recording), then the sample listeners (each its own copy).
///
/// Input: `AVAudioEngine` + `AVAudioConverter` to 12 kHz Int16 mono (`AudioInputEngine`);
/// device by CoreAudio name, empty/`Default Audio Device`/not found = default.
///
/// Divergences: a listener is removed by a `ListenerID` token (Java `Consumer` by identity); after `close()` not even
/// a block in progress in the queue is delivered (Java could deliver the last block read).
public final class AudioCapture: @unchecked Sendable {

    /// Sampling rate of the input (16 bit mono LE).
    public static let sampleRate = 12_000
    /// Samples in one block for listeners.
    public static let block = 1024

    /// Identity of a listener for `removeListener`/`removeRawListener`.
    public struct ListenerID: Hashable, Sendable {
        fileprivate let raw: UInt64
    }

    private struct State {
        var listeners: [(id: UInt64, run: @Sendable ([Double]) -> Void)] = []
        var rawListeners: [(id: UInt64, run: @Sendable ([UInt8]) -> Void)] = []
        var nextID: UInt64 = 0
        var running = false
        /// Incremented on `close()` — blocks of the old start are discarded.
        var generation: UInt64 = 0
        var pending: [UInt8] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Java `synchronized` over `start`/`close` (the engine start is not done under `state`).
    private let lifecycle = NSLock()
    private var input: AudioInputEngine?
    private let queue = DispatchQueue(label: "audio-capture")

    public init() {}

    public func addListener(_ listener: @escaping @Sendable ([Double]) -> Void) -> ListenerID {
        state.withLock { s in
            let id = s.nextID
            s.nextID += 1
            s.listeners.append((id, listener))
            return ListenerID(raw: id)
        }
    }

    public func removeListener(_ id: ListenerID) {
        state.withLock { s in s.listeners.removeAll { $0.id == id.raw } }
    }

    /// Raw PCM data (16-bit LE mono) — for recording to wav.
    public func addRawListener(_ listener: @escaping @Sendable ([UInt8]) -> Void) -> ListenerID {
        state.withLock { s in
            let id = s.nextID
            s.nextID += 1
            s.rawListeners.append((id, listener))
            return ListenerID(raw: id)
        }
    }

    public func removeRawListener(_ id: ListenerID) {
        state.withLock { s in s.rawListeners.removeAll { $0.id == id.raw } }
    }

    public var isRunning: Bool {
        state.withLock { $0.running }
    }

    /// Opens the input (empty name = system default) and starts reading; a running input is left alone.
    /// Error: `Zvukový vstup není dostupný: …` (Java `IOException`). Blocks (CoreAudio start) — call
    /// outside Swift's shared pool.
    public func start(deviceName: String?) throws(AudioIOError) {
        lifecycle.lock()
        defer { lifecycle.unlock() }
        let generation: UInt64? = state.withLock { s in s.running ? nil : s.generation }
        guard let generation else {
            return
        }
        let engine = AudioInputEngine(sampleRate: Double(Self.sampleRate), deviceName: deviceName, queue: queue) {
            [weak self] pcm in
            self?.accept(pcm, generation: generation)
        }
        state.withLock { s in
            s.running = true
            s.pending.removeAll()
        }
        do {
            try engine.start()
        } catch {
            state.withLock { $0.running = false }
            throw AudioIOError("Zvukový vstup není dostupný: " + error.message)
        }
        input = engine
    }

    /// Stops the input (Java `close()`); `start` can open it again.
    public func close() {
        lifecycle.lock()
        defer { lifecycle.unlock() }
        state.withLock { s in
            s.running = false
            s.generation &+= 1
            s.pending.removeAll()
        }
        input?.stop()
        input = nil
    }

    /// Accepts PCM from the converter (queue `audio-capture`), assembles blocks of `block × 2` bytes and delivers them.
    func accept(_ pcm: [UInt8], generation: UInt64) {
        let size = Self.block * 2
        typealias Work = (blocks: [[UInt8]], raw: [@Sendable ([UInt8]) -> Void], samples: [@Sendable ([Double]) -> Void])
        let work: Work = state.withLock { s in
            guard s.running, s.generation == generation else {
                return ([], [], [])
            }
            s.pending.append(contentsOf: pcm)
            var blocks: [[UInt8]] = []
            var start = 0
            while s.pending.count - start >= size {
                blocks.append(Array(s.pending[start..<(start + size)]))
                start += size
            }
            s.pending.removeFirst(start)
            return (blocks, s.rawListeners.map(\.run), s.listeners.map(\.run))
        }
        for block in work.blocks {
            for listener in work.raw {
                listener(block)
            }
            for listener in work.samples {
                listener(Self.toSamples(block))
            }
        }
    }

    /// For tests: the "running" state without a device (PCM is then fed directly into `accept`). Returns the generation.
    func startWithoutDevice() -> UInt64 {
        state.withLock { s in
            s.running = true
            return s.generation
        }
    }

    /// 16-bit LE PCM → `Double` −1…1 (`v / 32768.0`, exact). An odd trailing byte is ignored.
    public static func toSamples(_ pcm: [UInt8]) -> [Double] {
        let count = pcm.count / 2
        var out = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let value = Int16(bitPattern: UInt16(pcm[2 * i]) | UInt16(pcm[2 * i + 1]) << 8)
            out[i] = Double(value) / 32768.0
        }
        return out
    }
}
