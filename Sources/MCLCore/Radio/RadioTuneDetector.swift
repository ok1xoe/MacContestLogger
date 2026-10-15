import Foundation

/// Tells a radio tuned by its operator (the knob, the radio's own keys) from a frequency change the app asked for
/// (a QSY, a spot, the arrows): N1MM „Grab Focus From Other Apps When Radio Is Tuned" reacts only to the first.
///
/// The app announces each frequency it sends to a rig (`appTuned`); the next polled changes of that rig close to the
/// announced frequency (a rig may round it or shift it by its CW pitch) are the app's. Any other change of a rig's
/// polled frequency is the operator's. The first state of a rig (a connect) is never a tune.
public struct RadioTuneDetector: Equatable, Sendable {

    /// How far a polled frequency may be from the announced one and still be the app's (Hz).
    public static let toleranceHz: Int64 = 2_000
    /// How many polled changes an announcement covers (the frequency, then a mode's offset).
    public static let changesPerTune = 2

    private var expected: [Int64?] = [nil, nil]
    private var credits: [Int] = [0, 0]

    public init() {}

    /// The app sent `freqHz` to rig `rig` (0 / 1).
    public mutating func appTuned(rig: Int, freqHz: Int64) {
        guard expected.indices.contains(rig), freqHz > 0 else { return }
        expected[rig] = freqHz
        credits[rig] = Self.changesPerTune
    }

    /// The app sent rig `rig` something that may move its frequency to a value it does not know (a VFO swap, a raw
    /// CAT macro): its next polled changes are the app's.
    public mutating func appChanged(rig: Int) {
        guard expected.indices.contains(rig) else { return }
        expected[rig] = 0
        credits[rig] = Self.changesPerTune
    }

    /// A polled state of rig `rig`: `true` when its frequency changed and the app did not ask for it.
    public mutating func polled(rig: Int, previousHz: Int64?, nowHz: Int64?) -> Bool {
        guard expected.indices.contains(rig), let previousHz, let nowHz, previousHz > 0, nowHz > 0,
              previousHz != nowHz else { return false }
        if let target = expected[rig], credits[rig] > 0, target == 0 || abs(nowHz - target) <= Self.toleranceHz {
            credits[rig] -= 1
            if credits[rig] == 0 {
                expected[rig] = nil
            }
            return false
        }
        expected[rig] = nil
        credits[rig] = 0
        return true
    }
}
