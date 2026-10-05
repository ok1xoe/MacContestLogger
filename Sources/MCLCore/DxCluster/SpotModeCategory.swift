import Foundation

/// Traffic category (CW / PHONE / DIGI) of a mode for the spot filters — Kotlin `modeCategory`
/// (`ui/AvailFilterDialog.kt:57`, v1.1.1). It reconciles contest modes (CW, SSB, DIGITAL…) with spot modes (CW,
/// FT8, RTTY…): `mode.trim().uppercase()` is `CW` → CW; `SSB`/`USB`/`LSB`/`PH`/`PHONE`/`FM`/`AM` → PHONE; anything
/// else (also an empty text) → DIGI. Measured by a maintainer-only probe (rows `modeCategory`).
public enum SpotModeCategory {

    public static let cw = "CW"
    public static let phone = "PHONE"
    public static let digi = "DIGI"

    /// Kotlin `modeCategory(mode)`.
    public static func of(_ mode: String) -> String {
        ContestActivation.modeCategory(mode)
    }
}
