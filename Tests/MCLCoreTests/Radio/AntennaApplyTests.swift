import Testing
@testable import MCLCore

/// `AntennaApply` against `AppState.autoSelectAntenna`/`nextAntenna`/`applyAntenna` (`AS:767-797`) with the identity
/// rules (a)–(c).
@Suite struct AntennaApplyTests {

    static let antennas: [AntennaEntry] = [
        AntennaEntry(code: 1, name: "Yagi 20", bands: "20m", sector: "0-180"),
        AntennaEntry(code: 2, name: "Dipole", bands: "20m,40m", sector: ""),
        AntennaEntry(code: 7, name: "Beverage", bands: "40m", sector: ""),
        AntennaEntry(code: 22, name: "Odd", bands: "15m", sector: ""),
        AntennaEntry(code: -3, name: "Neg", bands: "10m", sector: ""),
    ]

    @Test func planSendsTheOtrspAuxOfTheActiveVfoClampedTo0Through15() {
        let odd = AntennaApply.plan(entry: Self.antennas[3], activeVfo: 1, viaRig: true, rigConnected: true)
        #expect(odd.otrspAux == (2, 15))
        #expect(odd.rigAntenna == nil) // only codes 1…4 go to the rig
        let neg = AntennaApply.plan(entry: Self.antennas[4], activeVfo: 0, viaRig: true, rigConnected: true)
        #expect(neg.otrspAux == (1, 0))
        #expect(neg.rigAntenna == nil)
        let yagi = AntennaApply.plan(entry: Self.antennas[0], activeVfo: 0, viaRig: true, rigConnected: true)
        #expect(yagi.rigAntenna == 1)
        #expect(yagi.status.czech == "Anténa: Yagi 20 (kód 1)")
        #expect(AntennaApply.plan(entry: Self.antennas[0], activeVfo: 0, viaRig: false, rigConnected: true)
            .rigAntenna == nil)
        #expect(AntennaApply.plan(entry: Self.antennas[0], activeVfo: 0, viaRig: true, rigConnected: false)
            .rigAntenna == nil)
    }

    @Test func autoSelectPicksByAzimuthAndSkipsTheSameIndex() throws {
        var state = AntennaApply()
        let selected = state.autoSelect(band: .m20, azimuth: 90, antennas: Self.antennas, activeVfo: 0,
                                        viaRig: false, rigConnected: false)
        let byAzimuth = try #require(selected)
        #expect(byAzimuth.status.czech == "Anténa: Yagi 20 (kód 1)")
        #expect(state.currentIndex == 0)
        // Rule (c): the same index again does nothing.
        #expect(state.autoSelect(band: .m20, azimuth: 120, antennas: Self.antennas, activeVfo: 0, viaRig: false,
                                 rigConnected: false) == nil)
        // Without an azimuth the first candidate of the band.
        #expect(state.autoSelect(band: .m40, azimuth: nil, antennas: Self.antennas, activeVfo: 0, viaRig: false,
                                 rigConnected: false)?.status.czech == "Anténa: Dipole (kód 2)")
        #expect(state.autoSelect(band: .m160, azimuth: nil, antennas: Self.antennas, activeVfo: 0, viaRig: false,
                                 rigConnected: false) == nil)
        #expect(state.current?.name == "Dipole")
    }

    @Test func nextCyclesTheAntennasOfTheBand() {
        var state = AntennaApply()
        #expect(state.next(band: nil, antennas: Self.antennas, activeVfo: 0, viaRig: false, rigConnected: false)
                == .noBand)
        #expect(state.next(band: .m80, antennas: Self.antennas, activeVfo: 0, viaRig: false, rigConnected: false)
                == .none(.tr("Pro %s není v Nastavení → Antennas žádná anténa", .string("80m"))))
        guard case .apply(let first?) = state.next(band: .m40, antennas: Self.antennas, activeVfo: 0, viaRig: false,
                                                    rigConnected: false) else {
            Issue.record("expected an antenna")
            return
        }
        #expect(first.status.czech == "Anténa: Dipole (kód 2)")
        guard case .apply(let second?) = state.next(band: .m40, antennas: Self.antennas, activeVfo: 0, viaRig: false,
                                                     rigConnected: false) else {
            Issue.record("expected an antenna")
            return
        }
        #expect(second.status.czech == "Anténa: Beverage (kód 7)")
        #expect(state.currentIndex == 2)
    }

    /// Rule (b): after Settings write `config.antennas` the index is forgotten — `next` starts from the first
    /// candidate again and the same antenna is applied (its code is sent again), while the shown value stays.
    @Test func writingTheAntennasForgetsTheIndexButKeepsTheValue() {
        var state = AntennaApply()
        _ = state.autoSelect(band: .m40, azimuth: nil, antennas: Self.antennas, activeVfo: 0, viaRig: false,
                             rigConnected: false)
        #expect(state.currentIndex == 1)
        state.antennasChanged()
        #expect(state.currentIndex == nil)
        #expect(state.current?.name == "Dipole")
        let again = state.autoSelect(band: .m40, azimuth: nil, antennas: Self.antennas, activeVfo: 0, viaRig: false,
                                     rigConnected: false)
        #expect(again?.status.czech == "Anténa: Dipole (kód 2)")
    }

    @Test func applyIgnoresAnIndexOutOfRange() {
        var state = AntennaApply()
        #expect(state.apply(index: 9, antennas: Self.antennas, activeVfo: 0, viaRig: false, rigConnected: false) == nil)
        #expect(state.currentIndex == nil)
    }
}
