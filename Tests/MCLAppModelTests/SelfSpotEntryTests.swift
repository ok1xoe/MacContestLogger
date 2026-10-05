import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The self-spot and the auto-prefill of the entry windows (`EP:150-153, 235-256`; ledger: the tracker's
/// call order, the tuning effect in both windows, a wipe and a tune in one step). No rig is connected: the tuning is
/// the shared state only, CAT never answers and nothing transmits.
@MainActor @Suite struct SelfSpotEntryTests {

    static func spots(_ rigApp: RigApp) -> [DxSpot] {
        rigApp.model.dxCluster.spots.snapshot()
    }

    /// Tunes and lets the tuning effect run (Kotlin: after the recomposition).
    static func tune(_ rigApp: RigApp, _ hz: Int64) async {
        rigApp.rig.qsy(hz)
        await runMainQueue()
    }

    /// A typed call is anchored where it was entered; tuning at least `selfSpotThresholdHz` away stores it there as
    /// my own spot and clears the field. Below the threshold nothing happens.
    @Test func tuningAwayFromATypedCallSelfSpotsIt() async throws {
        let rigApp = try await RigApp.make { config, _ in config.dxCluster.selfSpotThresholdHz = 2_500 }
        await Self.tune(rigApp, 14_025_000)
        rigApp.entry.callChanged("OK1ABC")
        // The field shows 10 Hz steps and feeds the rounded value back (`EP:189-196`): 14 027.49 kHz.
        await Self.tune(rigApp, 14_027_490)
        #expect(rigApp.entry.form.call == "OK1ABC")
        #expect(Self.spots(rigApp).isEmpty)
        await Self.tune(rigApp, 14_027_500)
        #expect(rigApp.entry.form.call.isEmpty)
        let stored: [DxSpot] = Self.spots(rigApp)
        #expect(stored == [DxSpot(spotter: "OK1XOE", freqHz: 14_025_000, dxCall: "OK1ABC", comment: "self",
                                  selfSpotted: true)])
        // The anchor went with the call: a new call is anchored at the new frequency.
        rigApp.entry.callChanged("OK1ABD")
        await Self.tune(rigApp, 14_029_000)
        #expect(rigApp.entry.form.call == "OK1ABD")
    }

    /// A call from a spot is never self-spotted; typing makes it the operator's again, still anchored where the spot's
    /// call came in (the anchor effect runs only when the call turns non-blank — Kotlin).
    @Test func aCallFromASpotIsNotSelfSpotted() async throws {
        let rigApp = try await RigApp.make()
        rigApp.rig.tuneToSpot(DxSpot(spotter: "OK1RR", freqHz: 14_030_000, dxCall: "DL1ABC", comment: ""))
        await runMainQueue()
        #expect(rigApp.entry.callFromSpot)
        await Self.tune(rigApp, 14_040_000)
        #expect(rigApp.entry.form.call == "DL1ABC")
        #expect(Self.spots(rigApp).isEmpty)
        rigApp.entry.callChanged("DL1ABD")
        #expect(!rigApp.entry.callFromSpot)
        await Self.tune(rigApp, 14_045_000)
        #expect(rigApp.entry.form.call.isEmpty)
        #expect(Self.spots(rigApp).map(\.dxCall) == ["DL1ABD"])
        #expect(Self.spots(rigApp).first?.freqHz == 14_030_000)
    }

    /// With an empty field, tuning onto a spot within 100 Hz fills its call (a call from a spot); 110 Hz away does not.
    @Test func tuningOntoASpotPrefillsAnEmptyField() async throws {
        let rigApp = try await RigApp.make()
        rigApp.model.dxCluster.spots.add(DxSpot(spotter: "OK1RR", freqHz: 14_010_100, dxCall: "W1AW", comment: ""))
        await Self.tune(rigApp, 14_009_990)
        #expect(rigApp.entry.form.call.isEmpty)
        await Self.tune(rigApp, 14_010_000)
        #expect(rigApp.entry.form.call == "W1AW")
        #expect(rigApp.entry.callFromSpot)
        // Tuning away does not self-spot a call from a spot.
        await Self.tune(rigApp, 14_020_000)
        #expect(rigApp.entry.form.call == "W1AW")
        #expect(Self.spots(rigApp).count == 1)
    }

    /// Wipe and logging clear `callFromSpot` (`EP:345`): a call typed after a wipe self-spots.
    @Test func wipeMakesTheCallTheOperatorsAgain() async throws {
        let rigApp = try await RigApp.make()
        rigApp.rig.qsy(7_010_000, call: "OK2ABC")
        await runMainQueue()
        #expect(rigApp.entry.callFromSpot)
        rigApp.entry.wipe()
        #expect(!rigApp.entry.callFromSpot)
        rigApp.entry.callChanged("OK2ABD")
        await Self.tune(rigApp, 7_020_000)
        #expect(Self.spots(rigApp).map(\.dxCall) == ["OK2ABD"])
    }

    /// A wipe and a tune in one step (Alt+Q: the CQ frequency, then `wipe()`, `EP:902`): Kotlin's effects run after
    /// the event and see the call already blank — the wiped call is not self-spotted.
    @Test func wipeAndTuneInOneStepDoesNotSelfSpot() async throws {
        let rigApp = try await RigApp.make()
        await Self.tune(rigApp, 14_040_000)
        rigApp.model.operating.onCqSent(14_040_000)
        await Self.tune(rigApp, 14_025_000)
        rigApp.entry.setFrequency("14025")
        rigApp.entry.callChanged("OK1ABC")
        rigApp.entry.runShortcut(.jumpCq)
        await runMainQueue()
        #expect(rigApp.rig.tuning.tunedFreqHz == 14_040_000)
        #expect(rigApp.entry.form.call.isEmpty)
        #expect(Self.spots(rigApp).isEmpty)
    }

    /// A window off screen runs no tuning effect (Kotlin has no VFO B composition then): tuning onto a spot while the
    /// VFO B window is hidden leaves its call blank when it opens, and its typed call is never self-spotted.
    @Test func aHiddenWindowRunsNoTuningEffect() async throws {
        let rigApp = try await RigApp.make { config, _ in config.radioMode = "SO2V" }
        let second: EntryModel = rigApp.model.vfoB.entry
        #expect(!second.isWindowShown)
        rigApp.model.dxCluster.spots.add(DxSpot(spotter: "OK1RR", freqHz: 14_035_000, dxCall: "DL1ABC", comment: ""))
        await Self.tune(rigApp, 14_035_000)
        #expect(rigApp.entry.form.call == "DL1ABC")
        second.isWindowShown = true
        #expect(second.form.call.isEmpty)
        second.isWindowShown = false
        second.callChanged("OK1VFB")
        await Self.tune(rigApp, 14_045_000)
        #expect(second.form.call == "OK1VFB")
        #expect(Self.spots(rigApp).map(\.dxCall) == ["DL1ABC"])
    }

    /// The tuning effect runs in **both** windows (Kotlin has no `active` guard there): in SO2V a call
    /// typed in the inactive window is self-spotted when the shared frequency moves away.
    @Test func theInactiveWindowSelfSpotsToo() async throws {
        let rigApp = try await RigApp.make { config, _ in config.radioMode = "SO2V" }
        let second: EntryModel = rigApp.model.vfoB.entry
        second.isWindowShown = true
        #expect(rigApp.entry.isActivePanel && !second.isActivePanel)
        await Self.tune(rigApp, 14_025_000)
        second.callChanged("OK1VFB")
        await Self.tune(rigApp, 14_030_000)
        #expect(second.form.call.isEmpty)
        #expect(Self.spots(rigApp).map(\.dxCall) == ["OK1VFB"])
        // The auto-prefill fills both empty windows.
        rigApp.model.dxCluster.spots.add(DxSpot(spotter: "OK1RR", freqHz: 14_035_000, dxCall: "DL1ABC", comment: ""))
        await Self.tune(rigApp, 14_035_050)
        #expect(rigApp.entry.form.call == "DL1ABC")
        #expect(second.form.call == "DL1ABC")
    }
}
