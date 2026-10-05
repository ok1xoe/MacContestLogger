import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// VFO B, split, swap, RIT, SO2V/SO2R with OTRSP and the antennas (`AS:767-797, 957-981, 2239-2354`).
@MainActor @Suite struct RigVfoTests {

    static func enter(_ rigApp: RigApp, _ text: String, ctrl: Bool = false) async {
        rigApp.entry.callChanged(text)
        rigApp.entry.handle(.enter(ctrl: ctrl, step: .logQso(ctrlEnter: ctrl)))
        await rigApp.settle()
    }

    // MARK: - VFO B, split, swap

    /// Without CAT every VFO operation says `tr("%s: připoj TRX (CAT) — …")` and nothing is logged.
    @Test func vfoOperationsNeedCat() async throws {
        let rigApp = try await RigApp.make()
        let texts: [(String, String)] = [
            ("SPLIT", "Split"), ("NOSPLIT", "Split"), ("SWAP", "SWAP"), ("/7010", "VFO B"),
        ]
        for (command, label) in texts {
            await Self.enter(rigApp, command)
            #expect(rigApp.status == label + ": připoj TRX (CAT) — bez něj druhé VFO ani split nejdou", "\(command)")
        }
        await Self.enter(rigApp, "RIT 100")
        #expect(rigApp.status == "RIT: připoj TRX (CAT)")
        rigApp.entry.runShortcut(.copyToVfoB)
        #expect(rigApp.status == "VFO B: připoj TRX (CAT) — bez něj druhé VFO ani split nejdou")
        #expect(rigApp.model.logbook.rows.isEmpty)
    }

    /// Split, VFO B, swap and copy with their Kotlin texts (verbatim where Kotlin does not translate).
    @Test func splitSwapAndCopyTexts() async throws {
        let (rigApp, fake) = try await RigTuningTests.connected()
        await Self.enter(rigApp, "SPLIT")
        #expect(rigApp.status == "Split zapnut (vysílám na VFO B)")
        await Self.enter(rigApp, "14027", ctrl: true)
        #expect(rigApp.status == "Split: vysílám na 14027.0 kHz")
        await Self.enter(rigApp, "NOSPLIT")
        #expect(rigApp.status == "Split vypnut")
        await Self.enter(rigApp, "SWAP")
        #expect(rigApp.status == "VFO A ↔ B prohozena")
        await Self.enter(rigApp, "/7010")
        #expect(rigApp.status == "VFO B 7010.0 kHz")
        rigApp.entry.runShortcut(.copyToVfoB)
        await rigApp.settle()
        #expect(rigApp.status == "VFO B 14025.0 kHz")
        rigApp.entry.runShortcut(.splitOn)
        await rigApp.settle()
        #expect(rigApp.status == "Split zapnut (vysílám na VFO B)")
        #expect(fake.writes == [
            "S 1 VFOB", "S 1 VFOB", "I 14027000", "S 0 VFOA", "G XCHG", "V VFOB", "F 7010000", "V VFOA",
            "V VFOB", "F 14025000", "V VFOA", "S 1 VFOB",
        ])
        #expect(rigApp.model.logbook.rows.isEmpty)
        // A rejected command: `"$label: ${it.message}"`.
        fake.reject("S")
        await Self.enter(rigApp, "SPLIT")
        #expect(rigApp.status == "Split: rigctld odmítl zapnutí splitu: RPRT -1")
    }

    /// Ctrl+Alt+S decides by the last polled state.
    @Test func toggleSplitFollowsThePolledState() async throws {
        let fake = try FakeRigctld()
        fake.setSplit(true, txHz: 14_030_000)
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port)
        }
        await rigApp.connect()
        #expect(rigApp.rig.activeState?.split == true)
        rigApp.entry.runShortcut(.splitToggle)
        await rigApp.settle()
        #expect(rigApp.status == "Split vypnut")
        // The poll has not run since: the state still says split, so the toggle turns it off again.
        rigApp.entry.runShortcut(.splitToggle)
        await rigApp.settle()
        #expect(fake.writes == ["S 0 VFOA", "S 0 VFOA"])
    }

    /// Alt+F7: a prompt; a frequency or an offset splits, blank turns split off, anything else is invalid.
    @Test func promptSplit() async throws {
        let (rigApp, fake) = try await RigTuningTests.connected()
        let dialogs: DialogsModel = rigApp.model.dialogs
        rigApp.entry.runShortcut(.splitPrompt)
        #expect(dialogs.textPrompt?.title == .verbatim("Split"))
        #expect(dialogs.textPrompt?.hint == ContestMessage(RigTexts.splitPromptHint))
        dialogs.submitPrompt("14028")
        await rigApp.settle()
        #expect(rigApp.status == "Split: vysílám na 14028.0 kHz")
        rigApp.entry.runShortcut(.splitPrompt)
        dialogs.submitPrompt(" ")
        await rigApp.settle()
        #expect(rigApp.status == "Split vypnut")
        rigApp.entry.runShortcut(.splitPrompt)
        dialogs.submitPrompt("xyz")
        #expect(rigApp.status == "Split: neplatná frekvence „xyz“")
        #expect(fake.writes == ["S 1 VFOB", "I 14028000", "S 0 VFOA"])
    }

    /// The auto split of a spot (the spot windows call it): a spot's split turns it on, the next spot without one turns off
    /// only that split.
    @Test func autoSplitFromSpots() async throws {
        let (rigApp, fake) = try await RigTuningTests.connected()
        let rig: MCLAppModel.RigModel = rigApp.rig
        rig.applySplitFromSpot(DxSpot(spotter: "DL1AA", freqHz: 14_025_000, dxCall: "VP8X", comment: "UP 2"))
        await rigApp.settle()
        #expect(rigApp.status == "Split: vysílám na 14027.0 kHz")
        rig.applySplitFromSpot(DxSpot(spotter: "DL1AA", freqHz: 14_030_000, dxCall: "W1AW", comment: "CQ"))
        await rigApp.settle()
        #expect(rigApp.status == "Split vypnut")
        rig.applySplitFromSpot(DxSpot(spotter: "DL1AA", freqHz: 14_031_000, dxCall: "K1AA", comment: ""))
        rig.applySplitFromSpot(DxSpot(spotter: "DL1AA", freqHz: 14_200_000, dxCall: "K2AA", comment: "SSB UP"))
        await rigApp.settle()
        #expect(fake.writes == ["S 1 VFOB", "I 14027000", "S 0 VFOA", "S 1 VFOB", "I 14205000"])
        rigApp.model.config.config.dxCluster.autoSplit = false
        rig.applySplitFromSpot(DxSpot(spotter: "DL1AA", freqHz: 14_031_000, dxCall: "K1AA", comment: ""))
        await rigApp.settle()
        #expect(fake.writes.count == 5)
    }

    // MARK: - RIT

    /// Starts CQ WW CW and logs DL1ABC.
    static func logAQso(_ rigApp: RigApp) async throws {
        try await rigApp.app.startCqWwCw()
        rigApp.entry.callChanged("DL1ABC")
        rigApp.entry.editContestField("zone", "14")
        rigApp.entry.submit()
        await rigApp.entry.settle()
        await rigApp.model.logbook.settleMutations()
        await rigApp.settle()
        #expect(rigApp.model.logbook.rows.map(\.call) == ["DL1ABC"])
    }

    /// RIT steps by the mode's step, the texts are Kotlin's verbatim ones; `ritHz` changes only when the rig
    /// accepted; a logged QSO clears it (`isRitClearAfterLog`).
    @Test func ritStepsClearsAndIsClearedAfterALog() async throws {
        let (rigApp, fake) = try await RigTuningTests.connected()
        let rig: MCLAppModel.RigModel = rigApp.rig
        rigApp.entry.runShortcut(.ritUp)
        await rigApp.settle()
        #expect(rigApp.status == "RIT +20 Hz")
        #expect(rig.rit.ritHz == 20)
        rigApp.entry.runShortcut(.ritDown)
        await rigApp.settle()
        #expect(rigApp.status == "RIT vypnut")
        await Self.enter(rigApp, "RIT -150")
        #expect(rigApp.status == "RIT -150 Hz")
        await Self.enter(rigApp, "RIT 20000")
        #expect(rig.rit.ritHz == 9_999)
        // A free QSO logged: RIT 0 after the write.
        let before: Int = fake.writes.count
        try await Self.logAQso(rigApp)
        #expect(Array(fake.writes.dropFirst(before)) == ["J 0", "U RIT 0"])
        #expect(rig.rit.ritHz == 0)
        #expect(rigApp.status == "RIT vypnut")
        #expect(!rigApp.model.logbook.deferredEffects.contains(.clearRit))
        // A rejected RIT keeps the last value.
        fake.reject("J")
        rigApp.entry.runShortcut(.ritUp)
        await rigApp.settle()
        #expect(rigApp.status == "RIT: rigctld odmítl nastavení RIT: RPRT -1")
        #expect(rig.rit.ritHz == 0)
    }

    /// The clearing after a log happens only with RIT on and the option on (`AS:2797`).
    @Test func ritIsClearedAfterALogOnlyWhenEnabled() async throws {
        let (rigApp, fake) = try await RigTuningTests.connected { config in
            config.ritClearAfterLog = false
        }
        rigApp.rig.setRit(100)
        await rigApp.settle()
        try await Self.logAQso(rigApp)
        #expect(fake.writes == ["J 100", "U RIT 1"])
        #expect(rigApp.rig.rit.ritHz == 100)
    }

    // MARK: - SO2V / SO2R

    /// OTRSP opens at start-up in SO2R; switching the rig focuses it (`TX2`, `RX2`), stereo `RX2S`; rig 2 has
    /// its own session and configuration; back to SO1V closes OTRSP and returns to VFO A.
    @Test func so2rSwitchesOverOtrsp() async throws {
        let fake1 = try FakeRigctld(freqHz: 14_025_000)
        let fake2 = try FakeRigctld(freqHz: 7_010_000)
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2R"
            config.otrspPort = "/dev/fake-otrsp"
            config.rig = fakeRigConfig(fake1.port, label: "Rig 1")
            config.rig2 = fakeRigConfig(fake2.port, label: "Rig 2")
        }
        let rig: MCLAppModel.RigModel = rigApp.rig
        await rigApp.settle()
        #expect(rigApp.model.peripherals.otrspOpen)
        #expect(rigApp.hardware.events == ["otrsp open /dev/fake-otrsp"])
        #expect(rig.vfo.so2r && rig.vfo.twoEntryWindows)
        await rigApp.connect(vfo: 0)
        rig.toggle(vfo: 1)
        await eventually("rig 2") { rig.cat2.state != nil }
        #expect(rig.status(vfo: 1) == "TRX: 7010.0 kHz  CW")
        #expect(rig.rigConfig(vfo: 1).modelLabel == "Rig 2")
        rigApp.entry.runShortcut(.switchRadio)
        #expect(rig.vfo.activeVfo == 1)
        #expect(rig.focusVfoRequest == 1)
        #expect(rigApp.status == "Aktivní rig 2")
        rigApp.entry.runShortcut(.so2rStereo)
        #expect(rigApp.status == "SO2R: stereo (oba rigy)")
        rigApp.entry.runShortcut(.so2rStereo)
        #expect(rigApp.status == "SO2R: poslech jen aktivního rigu")
        // Rig 2 is the active rig now: a QSY goes to its daemon.
        rig.qsy(7_012_000)
        await rigApp.settle()
        #expect(fake2.writes == ["F 7012000"])
        #expect(fake1.writes.isEmpty)
        #expect(rigApp.hardware.events == [
            "otrsp open /dev/fake-otrsp", "otrsp TX2", "otrsp RX2", "otrsp RX2S", "otrsp RX2",
        ])
        // Settings → SO1V: OTRSP closes, VFO A (rig 1) is active again.
        rigApp.model.config.config.radioMode = "SO1V"
        rig.syncRadioModeFromConfig()
        await rigApp.settle()
        #expect(rig.vfo.activeVfo == 0)
        #expect(!rigApp.model.peripherals.otrspOpen)
        #expect(rigApp.hardware.events.last == "otrsp close")
    }

    /// SO2R without a controller and with one that cannot be opened.
    @Test func so2rWithoutOtrsp() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2R"
        }
        rigApp.rig.activateVfo(1)
        #expect(rigApp.status == "Aktivní rig 2 (bez OTRSP kontroléru)")
        let failing = try await RigApp.make(configure: { config, _ in
            config.radioMode = "SO2R"
            config.otrspPort = "/dev/fake-otrsp"
        }, adjust: { _ in })
        failing.hardware.failOtrsp("OTRSP: nelze otevřít port /dev/fake-otrsp")
        failing.rig.syncRadioModeFromConfig()
        await failing.settle()
        #expect(failing.status == "SO2R: OTRSP: nelze otevřít port /dev/fake-otrsp")
        #expect(!failing.model.peripherals.otrspOpen)
    }

    /// SO2V: the active VFO over CAT (`V VFOA/VFOB`), each VFO keeps its frequency.
    @Test func so2vSelectsTheRigsVfo() async throws {
        let (rigApp, fake) = try await RigTuningTests.connected { config in
            config.radioMode = "SO2V"
        }
        let rig: MCLAppModel.RigModel = rigApp.rig
        rigApp.model.vfoB.entry.isWindowShown = true
        rig.activateVfo(1)
        await rigApp.settle()
        #expect(rigApp.status == "Aktivní VFO B")
        rig.qsy(14_030_000)
        rig.activateVfo(0)
        await rigApp.settle()
        #expect(rigApp.status == "Aktivní VFO A")
        #expect(rig.tuning.tunedFreqHz == 14_025_000)
        // VFO B's frequency is restored, then the VFO B window, now the active one, follows the rig's last reported
        // state (Kotlin `LaunchedEffect(state.cat.state, modeLocked, active)`): the fake still reports 14 025 kHz.
        rig.activateVfo(1)
        #expect(rig.vfo.vfoFreq[1] == 14_030_000)
        #expect(rigApp.model.vfoB.entry.form.freqKHz == "14025.00")
        #expect(rig.tuning.tunedFreqHz == 14_025_000)
        await rigApp.settle()
        #expect(fake.writes == ["V VFOB", "F 14030000", "V VFOA", "V VFOB"])
        fake.reject("V")
        rig.activateVfo(0)
        await rigApp.settle()
        #expect(rigApp.status == "SO2V: rigctld odmítl výběr VFO A: RPRT -1")
    }

    // MARK: - antennas

    static let antennas: [AntennaEntry] = [
        AntennaEntry(code: 1, name: "Yagi", bands: "20m", sector: "0-90"),
        AntennaEntry(code: 2, name: "Dipól", bands: "14", sector: ""),
        AntennaEntry(code: 3, name: "Vertikál", bands: "40m", sector: ""),
    ]

    /// Rules (a)–(c): the band's antenna on a band change, the next one cycles by index, a Settings write forgets
    /// the index (the same antenna is applied again), the rig's connector over CAT with `isAntennaViaRig`.
    @Test func antennasFollowTheBandAndTheIndexRules() async throws {
        let (rigApp, fake) = try await RigTuningTests.connected { config in
            config.antennas = Self.antennas
            config.antennaViaRig = true
        }
        let rig: MCLAppModel.RigModel = rigApp.rig
        // The connect's first state selected the 20 m antenna (no azimuth: the first).
        #expect(rig.antenna.current?.name == "Yagi")
        #expect(rigApp.status == "Anténa: Yagi (kód 1)")
        rigApp.entry.runShortcut(.nextAntenna)
        #expect(rigApp.status == "Anténa: Dipól (kód 2)")
        rigApp.entry.runShortcut(.nextAntenna)
        #expect(rig.antenna.currentIndex == 0)
        rig.qsy(7_010_000)
        #expect(rigApp.status == "Anténa: Vertikál (kód 3)")
        // (c) back on 40 m after a band without an antenna: the same index, nothing is applied.
        rig.qsy(21_010_000)
        rigApp.model.status.clear()
        rig.qsy(7_012_000)
        #expect(rigApp.status == "")
        rig.qsy(14_025_000)
        #expect(rigApp.status == "Anténa: Yagi (kód 1)")
        // (b) a Settings write forgets the index; the shown antenna stays.
        rig.resetAntennaIndex()
        #expect(rig.antenna.currentIndex == nil)
        #expect(rig.antenna.current?.name == "Yagi")
        // After the reset the band's first antenna applies again (its index is no longer known).
        rigApp.entry.runShortcut(.nextAntenna)
        #expect(rigApp.status == "Anténa: Yagi (kód 1)")
        await rigApp.settle()
        #expect(fake.writes.filter { $0.hasPrefix("Y ") } == ["Y 1 0", "Y 2 0", "Y 1 0", "Y 3 0", "Y 1 0", "Y 1 0"])
        rig.qsy(3_510_000)
        rigApp.entry.runShortcut(.nextAntenna)
        #expect(rigApp.status == "Pro 80m není v Nastavení → Antennas žádná anténa")
    }

    /// OTRSP gets the antenna's BCD code on `AUX` (port = active VFO + 1, code clamped to 0…15); without the
    /// entity's coordinates there is no azimuth and the band's first antenna is taken.
    @Test func antennaOverOtrsp() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.antennas = [
                AntennaEntry(code: 20, name: "West", bands: "20m", sector: "180-359"),
                AntennaEntry(code: 4, name: "East", bands: "20m", sector: "0-180"),
            ]
            config.station.gridSquare = "JO70"
            config.radioMode = "SO2R"
            config.otrspPort = "/dev/fake-otrsp"
        }
        await rigApp.settle()
        rigApp.entry.callChanged("W1AW")
        // The test DXCC data has no coordinates (Kotlin `hasLatLon()` false).
        #expect(rigApp.rig.azimuthTo("W1AW") == nil)
        rigApp.entry.setFrequency("14025")
        #expect(rigApp.status == "Anténa: West (kód 20)")
        await rigApp.settle()
        #expect(rigApp.hardware.events.last == "otrsp AUX115")
    }
}
