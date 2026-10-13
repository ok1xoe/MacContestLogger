import Foundation
import MCLCore

/// What a spot hands to the active entry window (Kotlin `prefillCall` and `prefillExchange`, `AS:525-531`).
struct SpotPrefill {
    let call: String
    let exchange: JavaLinkedMap<String>
}

/// The spot side of the rigs: the buffer and the analysis a spot is read from.
struct SpotSources {
    /// The shared spot buffer (Kotlin `dxCluster.spots`); `nil` before the app wires it.
    var buffer: SpotBuffer?
    /// Kotlin `contest.predictExchange(spot)`: the predicted multiplier fields of the spotted station.
    var predictExchange: @MainActor (DxSpot) -> JavaLinkedMap<String> = { _ in JavaLinkedMap() }
    /// N1MM „Always use packet spot mode": the spot's mode by the analysis (`nil` = unknown).
    var spotMode: @MainActor (DxSpot) -> Mode? = { _ in nil }
    /// A random integer in the range (N1MM „Randomize incoming spot frequencies"; tests inject their own).
    var draw: @MainActor (ClosedRange<Int>) -> Int = { Int.random(in: $0) }
}

/// Tuning to a spot (`AS:552-581`): the band map, the available multipliers and the spot navigation.
extension RigModel {

    /// Kotlin `tuneToSpot(spot)`: the predicted exchange (`prefillExchange`), `qsy(freq, call = dxCall)` and the
    /// automatic split of the spot's comment. Only the frequency, the mode, the split and the active entry window's
    /// fields change — nothing transmits.
    ///
    /// `fillCall: false` (a single click in the band map with the N1MM call-frame on) tunes without touching the
    /// entry fields: the call shows in the call-frame. With „Always use packet spot mode" the spot's mode is set on
    /// the rig and in the active entry window too. With „Randomize incoming spot frequencies" the radio lands a small
    /// random offset off a cluster spot (`SpotFrequencyJitter`; own spots are exact).
    public func tuneToSpot(_ spot: DxSpot, fillCall: Bool = true) {
        let prefill: SpotPrefill? = fillCall
            ? SpotPrefill(call: spot.dxCall, exchange: spotSources.predictExchange(spot)) : nil
        let mode: Mode? = config.config.dxCluster.spotModeOnTune ? spotSources.spotMode(spot) : nil
        qsy(Int64(spot.freqHz) + Int64(jitterHz(spot)), mode: mode, prefill: prefill)
        if let mode {
            notifyEntries { entry in
                if entry.isActivePanel {
                    entry.applySpotMode(mode)
                }
            }
        }
        applySplitFromSpot(spot)
    }

    /// The random offset of tuning to `spot` (0 when the option is off or for an own spot).
    func jitterHz(_ spot: DxSpot) -> Int {
        guard config.config.dxCluster.randomizeSpotFrequencies, !spot.selfSpotted else { return 0 }
        let mode: Mode? = spotSources.spotMode(spot)
        let commentMode: String = SpotModeParser.fromComment(spot.comment) ?? ""
        let phone: Bool = mode == .ssb || mode == .am || mode == .fm || ["SSB", "USB", "LSB", "PH"].contains(commentMode)
        return SpotFrequencyJitter.offsetHz(phone: phone, draw: spotSources.draw)
    }

    /// The predicted exchange of a spot (the call-frame taken with the space bar).
    func predictedExchange(_ spot: DxSpot) -> JavaLinkedMap<String> {
        spotSources.predictExchange(spot)
    }

    /// Kotlin `spotForCall(call)`: the first spot in the buffer whose call equals the Kotlin-trimmed `call` ignoring
    /// case.
    public func spotForCall(_ call: String) -> DxSpot? {
        let wanted: String = KotlinStrings.trim(call)
        return spotSources.buffer?.snapshot().first { KotlinStrings.equalsIgnoreCase($0.dxCall, wanted) }
    }

    /// The prefill effects of the active entry window (`EP:205-219`): the call (a blank one does nothing) and the
    /// non-blank exchange values. Kotlin keeps them until a window is active; here they go to the window active now.
    func prefillActiveEntry(_ prefill: SpotPrefill) {
        var target: EntryModel?
        notifyEntries { entry in
            if target == nil && entry.isActivePanel {
                target = entry
            }
        }
        guard let target else { return }
        target.prefillCall(prefill.call)
        target.prefillExchange(prefill.exchange)
    }
}
