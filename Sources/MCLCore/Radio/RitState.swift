/// RIT as v1.1.1 keeps it (`AppState.ritHz`, `setRit`, `stepRit` — `AS:2320-2340`, clearing after a log `AS:2797`).
/// `ritHz` is the value the application last set successfully, not the rig's state: the model sets it only
/// when `rig.setRit` succeeded (`applied`).
public struct RitState: Sendable, Equatable {

    public static let limitHz = 9_999

    /// `ritHz` (0 = off).
    public private(set) var ritHz: Int = 0

    public init() {}

    /// `setRit`: `offsetHz.coerceIn(-9_999, 9_999)` — the value sent to the rig.
    public static func clamp(_ offsetHz: Int) -> Int {
        Swift.min(Swift.max(offsetHz, -limitHz), limitHz)
    }

    /// `stepRit` (`AS:2333-2334`): `setRit(ritHz + direction * tuneStepHz(mode).toInt())` — Kotlin `Int` arithmetic
    /// (wrapping), then clamped. The result is the offset to send.
    public func step(direction: Int, stepHz: Int64) -> Int {
        let step = Int32(truncatingIfNeeded: stepHz)
        let delta = Int32(truncatingIfNeeded: direction) &* step
        return Self.clamp(Int(Int32(truncatingIfNeeded: ritHz) &+ delta))
    }

    /// The rig accepted `offsetHz` (already clamped): it becomes the current RIT.
    public mutating func applied(_ offsetHz: Int) {
        ritHz = offsetHz
    }

    /// After a QSO is logged (`AS:2797`): `if (ritHz != 0 && config.isRitClearAfterLog) setRit(0)` — `true` = send
    /// `setRit(0)`.
    public func clearAfterLog(enabled: Bool) -> Bool {
        ritHz != 0 && enabled
    }
}
