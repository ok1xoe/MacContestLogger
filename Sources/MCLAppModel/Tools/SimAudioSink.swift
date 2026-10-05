import Foundation
import MCLCore

/// The sound of the pileup simulator (Kotlin `SimAudioPlayer`): the band noise and the scheduled CW signals.
/// A port, so that the simulator runs without any audio hardware: `HardwarePorts.live` plays through `SimAudioPlayer`,
/// every inert environment gets `SilentSimAudio`, tests pass a recording fake.
public protocol SimAudioSink: AnyObject, Sendable {
    /// Schedules a signal after `delayMs` ms.
    func play(_ samples: [Float], delayMs: Int64)
    /// Discards the scheduled signals (Esc).
    func clear()
    func setNoiseLevel(_ level: Double)
    /// Releases the output; may block (up to 500 ms for the real player), so the model calls it only on its own lane.
    func close()
}

extension SimAudioPlayer: SimAudioSink {}

/// The inert sink: the simulator runs logically (replies, the QSO check, the counters), nothing is played.
public final class SilentSimAudio: SimAudioSink {

    public init() {}

    public func play(_ samples: [Float], delayMs: Int64) {}

    public func clear() {}

    public func setNoiseLevel(_ level: Double) {}

    public func close() {}
}
