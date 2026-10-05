/// Randomness source of the pileup simulator — the part of Java `java.util.Random` used by `PileupSimulator`,
/// `PileupSimulator.callSource` and the UI (reply amplitude). A class so that one source can be shared by the
/// simulator, the callsign source and the UI (Kotlin shares one `simRandom` instance, `AppState.kt:1657,1705`).
///
/// Production: `SystemPileupRandom`; tests and the gate: `java.util.Random` bit by bit, so
/// for a given seed the same callsigns and times come out as in Java. Without `Sendable` — owned by the main thread.
public protocol PileupRandom: AnyObject {

    /// `nextInt(bound)`: uniformly `0 ..< bound`. The caller guarantees `bound > 0` (otherwise Java throws
    /// `IllegalArgumentException` before consuming any randomness — `PileupSimulator` checks this itself).
    func nextInt(bound: Int32) -> Int32

    /// `nextDouble()`: uniformly `[0, 1)`.
    func nextDouble() -> Double
}

/// Production source (Java `new Random()` without a seed): the system generator.
public final class SystemPileupRandom: PileupRandom {

    private var generator = SystemRandomNumberGenerator()

    public init() {}

    public func nextInt(bound: Int32) -> Int32 {
        precondition(bound > 0, "bound must be positive")
        return Int32.random(in: 0..<bound, using: &generator)
    }

    public func nextDouble() -> Double {
        Double.random(in: 0..<1, using: &generator)
    }
}
