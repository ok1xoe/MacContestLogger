import Foundation
@testable import MCLAppModel
@testable import MCLCore

/// A sound sink that only records (the simulator tests never create `SimAudioPlayer` and never touch an audio device).
final class RecordingSimAudio: SimAudioSink, @unchecked Sendable {
    struct Played: Equatable {
        let samples: Int
        let peak: Float
        let delayMs: Int64
    }

    private let lock = NSLock()
    private var recorded: [Played] = []
    private var clearCount = 0
    private var levels: [Double] = []
    private var closeThreads: [Bool] = []

    var plays: [Played] { lock.withLock { recorded } }
    var clears: Int { lock.withLock { clearCount } }
    var noiseLevels: [Double] { lock.withLock { levels } }
    var closes: Int { lock.withLock { closeThreads.count } }
    /// For every `close()`: whether it ran on the main thread.
    var closedOnMain: [Bool] { lock.withLock { closeThreads } }

    func play(_ samples: [Float], delayMs: Int64) {
        let peak: Float = samples.map { abs($0) }.max() ?? 0
        lock.withLock { recorded.append(Played(samples: samples.count, peak: peak, delayMs: delayMs)) }
    }

    func clear() {
        lock.withLock { clearCount += 1 }
    }

    func setNoiseLevel(_ level: Double) {
        lock.withLock { levels.append(level) }
    }

    func close() {
        lock.withLock { closeThreads.append(Thread.isMainThread) }
    }
}

/// The `HardwarePorts.makeSimAudio` of a test: hands out recording sinks (or fails once told to) and counts the calls.
final class SimAudioFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var failure: String?
    private var made: [RecordingSimAudio] = []
    private var noises: [Double] = []
    private let gate = NSCondition()
    private var held = false

    /// Opening the output blocks (on the simulator's lane) until `releaseOpen()`.
    func holdOpen() {
        gate.lock()
        held = true
        gate.unlock()
    }

    func releaseOpen() {
        gate.lock()
        held = false
        gate.broadcast()
        gate.unlock()
    }

    var sinks: [RecordingSimAudio] { lock.withLock { made } }
    var sink: RecordingSimAudio? { sinks.last }
    var requestedNoise: [Double] { lock.withLock { noises } }

    func fail(_ message: String?) {
        lock.withLock { failure = message }
    }

    func install(into environment: inout AppModel.Environment) {
        environment.hardware.makeSimAudio = { [self] noise in
            gate.lock()
            while held {
                gate.wait()
            }
            gate.unlock()
            let message: String? = lock.withLock { failure }
            if let message {
                throw AudioIOError(message)
            }
            let sink = RecordingSimAudio()
            lock.withLock {
                made.append(sink)
                noises.append(noise)
            }
            return sink
        }
    }
}

/// A deterministic random source (a counter), so the callers of a simulated session are the same in every run.
final class CountingPileupRandom: PileupRandom {
    private var counter: Int32 = 0

    func nextInt(bound: Int32) -> Int32 {
        counter = counter &+ 7
        return counter % bound
    }

    func nextDouble() -> Double {
        counter = counter &+ 1
        return Double(counter % 100) / 100.0
    }
}
