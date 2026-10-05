/// The entry window's Ctrl+PgUp/PgDn (`stepBand`, `EP:782-795`) up to the QSY it ends in (`qsy(toKHz, toMode)`,
/// `EP:611-621`): the kHz the frequency field shows and the Hz the rig is tuned to.
public enum BandStepping {

    public struct Target: Equatable, Sendable {
        /// The field text's value (`String.format("%.2f", toKHz)`).
        public let kHz: Double
        /// `Math.round(toKHz * 1000.0)` — the frequency handed to `qsy(hz, mode)`.
        public let hz: Int64
    }

    /// `stepBand(direction)`: the next band's last frequency, otherwise the start of the mode's segment
    /// (`TuningState.stepBand`); `nil` = nothing (no next band, no row).
    public static func target(tuning: TuningState, band: Band?, mode: Mode, allowed: [Band],
                              direction: Int) -> Target? {
        guard let kHz = tuning.stepBand(from: band, mode: mode, allowed: allowed, direction: direction) else {
            return nil
        }
        return Target(kHz: kHz, hz: qsyHz(kHz: kHz))
    }

    /// The frequency in Hz of `target` (the QSY of a band step).
    public static func qsyTarget(tuning: TuningState, band: Band?, mode: Mode, allowed: [Band],
                                 direction: Int) -> Int64? {
        target(tuning: tuning, band: band, mode: mode, allowed: allowed, direction: direction)?.hz
    }

    /// `qsy(toKHz, …)`'s conversion: `Math.round(toKHz * 1000.0)` (half up, `NaN` → 0, saturating).
    public static func qsyHz(kHz: Double) -> Int64 {
        JavaMath.round(kHz * 1000.0)
    }
}
