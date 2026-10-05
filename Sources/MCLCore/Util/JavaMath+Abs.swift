extension JavaMath {

    /// `Math.abs(long)`: `Long.MIN_VALUE` stays **negative** (`-MIN` wraps back to `MIN`).
    /// Swift's `abs(Int64.min)` traps. The Java results of `SplitFromComment` depend on this
    /// (`UP 99999999999999999999` → empty), `BandNotes.near` and `SpotNavigator.next`
    /// (distance `MIN` is "smallest").
    static func abs(_ x: Int64) -> Int64 {
        x < 0 ? 0 &- x : x
    }
}
