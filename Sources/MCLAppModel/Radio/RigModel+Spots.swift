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
}

/// Tuning to a spot (`AS:552-581`): the band map, the available multipliers and the spot navigation.
extension RigModel {

    /// Kotlin `tuneToSpot(spot)`: the predicted exchange (`prefillExchange`), `qsy(freq, call = dxCall)` and the
    /// automatic split of the spot's comment. Only the frequency, the mode, the split and the active entry window's
    /// fields change — nothing transmits.
    public func tuneToSpot(_ spot: DxSpot) {
        let exchange: JavaLinkedMap<String> = spotSources.predictExchange(spot)
        qsy(Int64(spot.freqHz), mode: nil, prefill: SpotPrefill(call: spot.dxCall, exchange: exchange))
        applySplitFromSpot(spot)
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
