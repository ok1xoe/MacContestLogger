/// The self-spot anchor and the auto-prefill of one entry panel (Kotlin `ui/EntryPanel.kt` of v1.1.1: `spotBaseFreqHz`
/// and `callFromSpot` `:150-153`, the `prefillCall` effect `:204-211`, the anchor effect `:235-239`, the tuning effect
/// `:240-256`). Pure state; the panel feeds it its call text and the shared tuned frequency.
///
/// The Compose effects run in declaration order within one composition — the app calls `callChanged` before
/// `tunedChanged`, and `tunedChanged` once at start with the initial frequency (the first composition runs the tuning
/// effect too, so a spot within 100 Hz pre-fills an empty field right away).
///
/// - Anchor: the tuned frequency when the call turns non-blank (only when the anchor is 0); 0 when it turns blank.
/// - Tuning with a non-blank call: when the call was typed (`!callFromSpot`), the anchor is set and the distance is
///   at least the threshold → self-spot the call **at the anchor** and **clear the call** (kept Kotlin behaviour: you
///   tuned away to another station).
/// - Tuning with a blank call to `f > 0`: the nearest spot within 100 Hz fills the call, `callFromSpot = true`.
/// - `callFromSpot` is cleared by typing, wipe and logging (`EP:345, 659, 667, 1105`) — `typed()`.
///
/// Kotlin runs the tuning effect in **every** panel, the inactive SO2V/SO2R one included (no `active` guard,
/// `EP:241`); which panels feed this is the app's decision.
public struct SelfSpotTracker: Equatable, Sendable {

    /// The auto-prefill tolerance (`nearestWithin(f, 100L)`).
    public static let prefillToleranceHz = 100

    /// What the panel must do after a frequency change.
    public enum Action: Equatable, Sendable {
        /// `selfSpot(call, anchor)` (`SpotActions.storeSpot`) and clear the call field.
        case selfSpot(call: String, atHz: Int64)
        /// Put this call into the empty field (`call = it.dxCall()`).
        case prefill(call: String)
    }

    /// `spotBaseFreqHz`: where the call was entered (0 = none).
    public private(set) var anchorHz: Int64 = 0
    /// `callFromSpot`: the call came from the band map / a spot, so it is never self-spotted.
    public private(set) var callFromSpot = false
    /// The last `call.isNotBlank()` seen (the key of the anchor effect).
    private var callPresent = false

    public init() {}

    /// The anchor effect (`LaunchedEffect(call.isNotBlank())`): acts only when the call turns blank or non-blank.
    public mutating func callChanged(_ call: String, tunedFreqHz: Int64) {
        let present: Bool = !KotlinText.isBlank(call)
        guard present != callPresent else { return }
        callPresent = present
        if present {
            if anchorHz == 0 { anchorHz = tunedFreqHz }
        } else {
            anchorHz = 0
        }
    }

    /// The `prefillCall` effect (a spot clicked in the band map, `tuneToSpot`): the field gets the call from a spot.
    /// Call `callChanged` with the new text afterwards.
    public mutating func prefilledFromSpot() {
        callFromSpot = true
    }

    /// Typing into the call field, wipe and logging: the call is the operator's again.
    public mutating func typed() {
        callFromSpot = false
    }

    /// The tuning effect (`LaunchedEffect(state.tunedFreqHz)`) with the call field text, the configured threshold
    /// (`selfSpotThresholdHz`) and `SpotBuffer.nearestWithin`. The tracker already reflects the field after the
    /// action (cleared or filled), so the following `callChanged` is a no-op.
    public mutating func tunedChanged(_ freqHz: Int64, call: String, thresholdHz: Int64,
                                      nearest: (_ freqHz: Int, _ toleranceHz: Int) -> DxSpot?) -> Action? {
        if !KotlinText.isBlank(call) {
            guard !callFromSpot, anchorHz > 0 else { return nil }
            guard JavaMath.abs(freqHz &- anchorHz) >= thresholdHz else { return nil }
            let action = Action.selfSpot(call: call, atHz: anchorHz)
            // `call = ""` → the anchor effect resets the anchor on the next composition.
            callPresent = false
            anchorHz = 0
            return action
        }
        guard freqHz > 0, let spot = nearest(Int(truncatingIfNeeded: freqHz), Self.prefillToleranceHz) else {
            return nil
        }
        callFromSpot = true
        // `call = it.dxCall()` → the anchor effect anchors at this frequency on the next composition.
        callChanged(spot.dxCall, tunedFreqHz: freqHz)
        return .prefill(call: spot.dxCall)
    }
}
