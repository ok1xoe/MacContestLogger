import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM Available beyond v1.1.1: the saved columns, order and widths, every column sorting, the summary panel (its
/// bands, hidden, clicked), the focus-radio filter, Alt+A / Shift+Alt+A, the row marks, the middle click, the rotator
/// item and the two-radio actions. The rigs are inert or fakes on 127.0.0.1; nothing transmits.
@MainActor @Suite struct AvailMultN1mmTests {

    // MARK: - columns

    @Test func columnsOrderAndWidthsAreSaved() async throws {
        let spot = try await AvailMultModelTests.app()
        let avail: AvailMultModel = spot.model.availMult
        let dx: () -> DxClusterConfig = { spot.model.config.config.dxCluster }
        #expect(avail.columns == AvailableColumn.defaultOrder)
        avail.setColumn(.heard, visible: true)
        #expect(avail.columns.last == .heard)
        avail.setColumn(.snr, visible: false)
        avail.setColumn(.call, visible: false)
        #expect(!avail.columns.contains(.snr) && avail.columns.first == .call)
        avail.moveColumn(.heard, by: -1)
        avail.moveColumn(.call, by: -1)
        #expect(Array(avail.columns.suffix(2)) == [.heard, .pts])
        #expect(dx().availColumns == avail.columns.map(\.rawValue))
        // A drag changes the width live; its end saves it.
        avail.dragWidth(.freq, to: 180)
        #expect(avail.width(.freq) == 180)
        #expect(dx().availColumnWidths.isEmpty)
        avail.endWidthDrag()
        #expect(dx().availColumnWidths == ["freq": 180])
        #expect(avail.draggedWidths.isEmpty)
        avail.resetColumns()
        #expect(avail.columns == AvailableColumn.defaultOrder)
        #expect(dx().availColumns.isEmpty && dx().availColumnWidths.isEmpty)
    }

    @Test func everyHeaderSorts() async throws {
        let spot = try await AvailMultModelTests.app()
        let avail: AvailMultModel = spot.model.availMult
        avail.sort(by: .call)
        #expect(avail.snapshot().rows.map(\.call) == ["DL1ABC", "DL2XYZ", "OK1XYZ", "W1AW"])
        avail.sort(by: .call)
        #expect(avail.snapshot().rows.map(\.call) == ["W1AW", "OK1XYZ", "DL2XYZ", "DL1ABC"])
        // The Time column: every row has its arrival time.
        let shown: AvailMultModel.Snapshot = avail.snapshot()
        #expect(Set(shown.spottedAt.keys) == ["DL1ABC", "DL2XYZ", "OK1XYZ", "W1AW"])
        let w1aw: SpotRow = try #require(shown.rows.first { $0.call == "W1AW" })
        let arrived: Date = try #require(shown.spottedAt["W1AW"])
        #expect(avail.ageText(w1aw, in: shown, at: arrived.addingTimeInterval(185)) == "3m")
    }

    // MARK: - summary panel

    @Test func summaryBandsShowAndClick() async throws {
        let spot = try await AvailMultModelTests.app()
        let avail: AvailMultModel = spot.model.availMult
        // CQ WW: the contest's six HF bands.
        #expect(avail.summaryBands == [.m160, .m80, .m40, .m20, .m15, .m10])
        avail.setSummaryBand(.m2, on: true)
        avail.setSummaryBand(.m20, on: true)
        #expect(avail.summaryBands == [.m20, .m2])
        #expect(spot.model.config.config.dxCluster.availSummaryBands == ["20m", "2m"])
        avail.setSummaryBand(.m2, on: false)
        avail.setSummaryBand(.m20, on: false)
        #expect(avail.summaryBands.count == 6)
        #expect(avail.showSummary)
        avail.setShowSummary(false)
        #expect(!spot.model.config.config.dxCluster.availShowSummary)
        // A click shows only the band; a second click restores the bands before it.
        let before: Set<Band> = avail.bands
        avail.clickSummary(.m40)
        #expect(avail.bands == [.m40])
        #expect(avail.snapshot().rows.map(\.call) == ["OK1XYZ"])
        avail.clickSummary(.m40)
        #expect(avail.bands == before)
        #expect(avail.snapshot().rows.count == 4)
    }

    // MARK: - focus radio

    @Test func focusRadioShowsOnlyTheTunedBand() async throws {
        let spot = try await AvailMultModelTests.app()
        let avail: AvailMultModel = spot.model.availMult
        spot.model.rig.qsy(7_005_000)
        avail.focusRadioOnly = true
        #expect(avail.snapshot().rows.map(\.call) == ["OK1XYZ"])
        spot.model.rig.qsy(14_000_000)
        #expect(avail.snapshot().rows.map(\.call) == ["DL1ABC", "DL2XYZ", "W1AW"])
        avail.focusRadioOnly = false
        #expect(avail.snapshot().rows.count == 4)
    }

    // MARK: - Alt+A

    @Test func altAGrabsTheNextSpotAndWraps() async throws {
        let spot = try await AvailMultModelTests.app()
        let model: AppModel = spot.model
        let avail: AvailMultModel = model.availMult
        model.entry.runShortcut(.availNext)
        #expect(avail.grabbedCall == "OK1XYZ")
        #expect(model.entry.form.call == "OK1XYZ")
        #expect(model.rig.tuning.tunedFreqHz == 7_010_000)
        model.entry.runShortcut(.availNext)
        #expect(avail.grabbedCall == "DL1ABC")
        model.entry.runShortcut(.availPrevious)
        model.entry.runShortcut(.availPrevious)
        // Before the first row: the last one.
        #expect(avail.grabbedCall == "W1AW")
        #expect(model.entry.form.call == "W1AW")
        avail.grab(forward: true)
        #expect(avail.grabbedCall == "OK1XYZ")
        avail.clearSpots()
        await runMainQueue()
        avail.grab(forward: true)
        #expect(model.status.message == "Okno Dostupné: žádný spot")
        #expect(ShortcutAction.availNext.defaultKeys == "Alt+A")
        #expect(ShortcutAction.availPrevious.defaultKeys == "Alt+Shift+A")
    }

    // MARK: - marks, middle click, rotator

    @Test func skimmerSplitAndCallMarks() async throws {
        let spot = try await AvailMultModelTests.app()
        let avail: AvailMultModel = spot.model.availMult
        spot.model.dxCluster.spots.add(DxSpot(spotter: "DK8NE-#", freqHz: 14_028_000, dxCall: "JA1ABC",
                                              comment: "CW 21 dB 28 WPM CQ"))
        spot.model.dxCluster.spots.add(DxSpot(spotter: "OK1RR", freqHz: 14_002_000, dxCall: "VP8XX",
                                              comment: "UP 2"))
        await runMainQueue()
        let rows: [SpotRow] = avail.snapshot().rows
        let ja: SpotRow = try #require(rows.first { $0.call == "JA1ABC" })
        let vp: SpotRow = try #require(rows.first { $0.call == "VP8XX" })
        let jaMarks: AvailMultModel.Marks = avail.marks(ja)
        #expect(jaMarks.skimmer == "#")
        #expect(jaMarks.qsxHz == nil)
        #expect(AvailMultModel.callText("JA1ABC", special: true, marks: jaMarks).hasPrefix("JA1ABC"
            + SpecialCalls.mark + "#"))
        let vpMarks: AvailMultModel.Marks = avail.marks(vp)
        #expect(vpMarks.skimmer == nil)
        #expect(vpMarks.qsxHz == 14_004_000)
        #expect(AvailMultModel.freqText(vp.freqHz, qsxHz: vpMarks.qsxHz) == "14002.0 QSX 004")
        #expect(AvailMultModel.freqText(vp.freqHz, qsxHz: nil) == "14002.0")
        let spoken: String = AvailMultModel.spokenMarks(
            AvailMultModel.Marks(skimmer: "#", grayLine: true, qsxHz: 14_004_000), heard: true,
            translator: spot.model.language.translator)
        #expect(spoken == ", skimmer, na šedé zóně, split QSX 004, signál je ve vodopádu")
        #expect(AvailMultModel.callText("X", special: false,
                                        marks: AvailMultModel.Marks(skimmer: nil, grayLine: true, qsxHz: nil))
                == "X" + BandmapSpotInfo.grayLineMark)
    }

    @Test func middleClickDeletesTheHoveredSpot() async throws {
        let spot = try await AvailMultModelTests.app()
        let avail: AvailMultModel = spot.model.availMult
        #expect(!avail.removeHovered())
        avail.hoveredCall = "W1AW"
        #expect(avail.removeHovered())
        await runMainQueue()
        #expect(avail.hoveredCall == nil)
        #expect(!avail.snapshot().rows.contains { $0.call == "W1AW" })
    }

    @Test func rotatorItemTurnsToTheCall() async throws {
        let spot = try await AvailMultModelTests.app()
        let avail: AvailMultModel = spot.model.availMult
        var turned: [String] = []
        avail.rotorTurner = { call, _ in turned.append(call) }
        let row: SpotRow = try #require(avail.snapshot().rows.first { $0.call == "W1AW" })
        avail.turnRotor(row)
        #expect(turned == ["W1AW"])
    }

    @Test func theSpeakerColumnReadsTheWaterfall() async throws {
        let spot = try await AvailMultModelTests.app()
        let avail: AvailMultModel = spot.model.availMult
        let row: SpotRow = try #require(avail.snapshot().rows.first { $0.call == "W1AW" })
        #expect(!avail.isHeard(row, spectrum: avail.spectrum()))
        var bright = [Float](repeating: 0, count: 512)
        // W1AW 14 030 kHz with the dial at 14 029 kHz in USB: 1000 Hz audio.
        bright[171] = 1
        let spectrum = SignalHeard.Spectrum(rows: [bright], maxHz: 3_000, dialHz: 14_029_000, rawMode: "USB",
                                            cwPitch: 600)
        avail.spectrum = { spectrum }
        #expect(avail.isHeard(row, spectrum: avail.spectrum()))
        avail.sort(by: .heard)
        avail.sort(by: .heard)
        #expect(avail.snapshot().rows.first?.call == "W1AW")
    }

    // MARK: - two radios

    @Test func oneRadioHasNoOtherRadio() async throws {
        let spot = try await AvailMultModelTests.app()
        let avail: AvailMultModel = spot.model.availMult
        #expect(!avail.hasOtherRadio)
        let row: SpotRow = try #require(avail.snapshot().rows.first)
        avail.qsyOtherRadio(row)
        #expect(spot.model.status.message == "QSY druhého rádia: jen v režimu SO2V nebo SO2R")
    }

    /// SO2R: a spot on the other radio's band takes the focus there first; the other radio without CAT says so.
    @Test func so2rFocusFollowsTheSpot() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2R"
        }
        let rig: MCLAppModel.RigModel = rigApp.rig
        rig.qsy(14_025_000)
        #expect(rig.otherVfoIndex == 1)
        #expect(rig.otherVfoFreqHz == nil)
        #expect(!rig.focusRadio(forSpotHz: 7_012_000))
        rig.vfo.setInactiveFrequency(7_010_000, vfo: 1)
        #expect(rig.otherVfoFreqHz == 7_010_000)
        // A spot on the active radio's band stays there.
        #expect(!rig.focusRadio(forSpotHz: 14_030_000))
        #expect(rig.focusRadio(forSpotHz: 7_012_000))
        #expect(rig.vfo.activeVfo == 1)
        #expect(rig.focusVfoRequest == 1)
        rig.qsyOtherRadio(21_010_000)
        #expect(rigApp.status == "Rig 1: připoj TRX (CAT)")
        #expect(rig.vfo.vfoFreq[0] == 21_010_000)
    }

    /// SO2R with both rigs on fakes: the other rig is tuned on its own daemon, the active one is untouched.
    @Test func so2rQsyTunesTheOtherRig() async throws {
        let fake1 = try FakeRigctld(freqHz: 14_025_000)
        let fake2 = try FakeRigctld(freqHz: 7_010_000)
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2R"
            config.rig = fakeRigConfig(fake1.port, label: "Rig 1")
            config.rig2 = fakeRigConfig(fake2.port, label: "Rig 2")
        }
        let rig: MCLAppModel.RigModel = rigApp.rig
        await rigApp.connect(vfo: 0)
        rig.toggle(vfo: 1)
        await eventually("rig 2") { rig.cat2.state != nil }
        #expect(rig.otherVfoFreqHz == 7_010_000)
        rig.qsyOtherRadio(7_015_000)
        await rigApp.settle()
        #expect(fake2.writes == ["F 7015000"])
        #expect(fake1.writes.isEmpty)
        #expect(rig.vfo.activeVfo == 0)
        #expect(rigApp.status == "Rig 2: 7015.0 kHz")
    }

    /// SO2V: the other VFO goes through the rig's VFO B, the focus stays.
    @Test func so2vQsyUsesTheOtherVfo() async throws {
        let (rigApp, fake) = try await RigTuningTests.connected { config in
            config.radioMode = "SO2V"
        }
        let rig: MCLAppModel.RigModel = rigApp.rig
        rig.qsyOtherRadio(14_030_000)
        await rigApp.settle()
        #expect(fake.writes == ["V VFOB", "F 14030000", "V VFOA"])
        #expect(rig.vfo.activeVfo == 0)
        #expect(rig.vfo.vfoFreq[1] == 14_030_000)
        #expect(rigApp.status == "VFO B 14030.0 kHz")
    }
}
