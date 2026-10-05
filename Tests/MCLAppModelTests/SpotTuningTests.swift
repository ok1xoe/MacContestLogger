import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Tuning to a spot (`AS:552-581`, `EP:205-219`): `tuneToSpot` QSYs the rig (the previous frequency rule), puts
/// the spot's call and the predicted exchange into the **active** entry window only, and turns the automatic split
/// on or off. Only a fake `rigctld` on 127.0.0.1 is reached; nothing transmits (no `T` line, no keyer).
@MainActor @Suite struct SpotTuningTests {

    static func spot(_ call: String, _ freqHz: Int, comment: String = "", spotter: String = "OK1RR") -> DxSpot {
        DxSpot(spotter: spotter, freqHz: freqHz, dxCall: call, comment: comment)
    }

    /// SO2V with the VFO B window on screen, CQ WW CW running, rig 1 on a fake daemon at 14 025 kHz.
    static func so2v() async throws -> (RigApp, FakeRigctld) {
        let fake = try FakeRigctld(freqHz: 14_025_000)
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2V"
            config.rig = fakeRigConfig(fake.port)
        }
        rigApp.model.vfoB.entry.isWindowShown = true
        try await rigApp.app.startCqWwCw()
        await rigApp.connect()
        await rigApp.settle()
        return (rigApp, fake)
    }

    @Test func tuneToSpotQsysAndPrefillsOnlyTheActiveWindow() async throws {
        let (rigApp, fake) = try await Self.so2v()
        let rig: MCLAppModel.RigModel = rigApp.rig
        let main: EntryModel = rigApp.entry
        let second: EntryModel = rigApp.model.vfoB.entry
        #expect(main.isActivePanel && !second.isActivePanel)

        rig.tuneToSpot(Self.spot("DL1ABC", 14_030_000))
        #expect(rig.tuning.tunedFreqHz == 14_030_000)
        #expect(rig.tuning.previousFreqHz == 14_025_000)
        #expect(main.form.call == "DL1ABC")
        #expect(main.callFromSpot)
        #expect(main.form.contestExchange["zone"] == "14")
        #expect(main.form.freqKHz == "14030.00")
        #expect(second.form.call.isEmpty)
        #expect(second.form.contestExchange["zone"] == nil)
        await runMainQueue()
        await rigApp.settle()
        #expect(fake.writes == ["F 14030000"])
        #expect(rigApp.keyer.keys.isEmpty)

        // The other window active: the next spot goes there.
        rig.activateVfo(1)
        await rigApp.settle()
        let w1aw: DxSpot = Self.spot("W1AW", 14_010_000)
        let predicted: String? = rigApp.model.spotAnalysis.current().predictExchange(w1aw)["zone"]
        #expect(predicted != nil)
        rig.tuneToSpot(w1aw)
        #expect(second.form.call == "W1AW")
        #expect(second.form.contestExchange["zone"] == predicted)
        #expect(main.form.call == "DL1ABC")
        await runMainQueue()
        await rigApp.settle()
        #expect(!fake.writes.contains { $0.hasPrefix("T ") })
        #expect(rigApp.keyer.keys.isEmpty)
    }

    /// The predicted exchange never overwrites with a blank value; a value the window already has is replaced (Kotlin
    /// `cexch[id] = value`).
    @Test func predictedExchangeReplacesTheField() async throws {
        let (rigApp, _) = try await Self.so2v()
        rigApp.entry.editContestField("zone", "99")
        rigApp.rig.tuneToSpot(Self.spot("DL1ABC", 14_030_000))
        #expect(rigApp.entry.form.contestExchange["zone"] == "14")
        // Outside a contest nothing is predicted.
        rigApp.model.contest.deactivate()
        rigApp.entry.wipe()
        rigApp.rig.tuneToSpot(Self.spot("W1AW", 14_010_000))
        #expect(rigApp.entry.form.call == "W1AW")
        #expect(rigApp.entry.form.contestExchange["zone"] == nil)
    }

    /// `applySplitFromSpot` through `tuneToSpot`: a spot's `UP 2` turns the split on, the next spot without one turns
    /// it off; with `autoSplit` off nothing happens. The rig is tuned first (Kotlin `cat.tune` also to the same
    /// frequency).
    @Test func tuneToSpotAppliesTheAutoSplit() async throws {
        let (rigApp, fake) = try await RigTuningTests.connected()
        let rig: MCLAppModel.RigModel = rigApp.rig
        rig.tuneToSpot(Self.spot("VP8X", 14_025_000, comment: "UP 2"))
        await rigApp.settle()
        rig.tuneToSpot(Self.spot("W1AW", 14_030_000, comment: "CQ"))
        await rigApp.settle()
        #expect(fake.writes == ["F 14025000", "S 1 VFOB", "I 14027000", "F 14030000", "S 0 VFOA"])
        rigApp.model.config.config.dxCluster.autoSplit = false
        rig.tuneToSpot(Self.spot("K1AA", 14_031_000, comment: "UP 5"))
        await rigApp.settle()
        #expect(fake.writes == ["F 14025000", "S 1 VFOB", "I 14027000", "F 14030000", "S 0 VFOA", "F 14031000"])
        #expect(!fake.writes.contains { $0.hasPrefix("T ") })
    }

    /// `spotForCall`: the first spot of the call, Kotlin-trimmed and ignoring case.
    @Test func spotForCallFindsTheBufferedSpot() async throws {
        let rigApp = try await RigApp.make()
        let buffer: SpotBuffer = rigApp.model.dxCluster.spots
        buffer.add(Self.spot("DL1ABC", 14_030_000))
        #expect(rigApp.rig.spotForCall(" dl1abc ")?.freqHz == 14_030_000)
        #expect(rigApp.model.spotNavigation.spotForCall("W1AW") == nil)
    }

    /// `qsy(freq, call:)`: the call goes into the active window as a call from a spot; a blank call is ignored.
    @Test func qsyWithACallPrefillsTheActiveWindow() async throws {
        let rigApp = try await RigApp.make()
        rigApp.rig.qsy(7_010_000, call: "OK2ABC")
        #expect(rigApp.entry.form.call == "OK2ABC")
        #expect(rigApp.entry.callFromSpot)
        rigApp.entry.callChanged("OK2ABD")
        #expect(!rigApp.entry.callFromSpot)
        rigApp.rig.qsy(7_011_000, call: " ")
        #expect(rigApp.entry.form.call == "OK2ABD")
    }
}
