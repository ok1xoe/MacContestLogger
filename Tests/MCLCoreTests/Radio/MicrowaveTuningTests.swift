import Foundation
import Testing
@testable import MCLCore

/// Post-port microwave bands in tuning, the call field commands, the spots and the filters.
@Suite struct MicrowaveTuningTests {

    // MARK: - band stepping (Ctrl+PgUp/PgDn)

    @Test func contestBandsStepIntoTheMicrowaves() throws {
        let allowed: [Band] = TuningState.bandsForStepping(contestBands: [.cm70, .cm23, .cm3])
        #expect(allowed == [.cm70, .cm23, .cm3])
        let tuning = TuningState()
        let up = try #require(BandStepping.target(tuning: tuning, band: .cm70, mode: .cw, allowed: allowed,
                                                  direction: 1))
        #expect(up.kHz == 1_296_050.0 && up.hz == 1_296_050_000)
        let next = try #require(BandStepping.target(tuning: tuning, band: .cm23, mode: .ssb, allowed: allowed,
                                                    direction: 1))
        #expect(next.hz == 10_368_200_000)
        // 3cm RTTY has no segment: the CW start is used, as for every band without a column.
        let digital = try #require(BandStepping.target(tuning: tuning, band: .cm23, mode: .rtty, allowed: allowed,
                                                       direction: 1))
        #expect(digital.hz == 10_368_050_000)
    }

    @Test func aTransverterTurnsTheMicrowaveStepIntoAnIntermediateFrequency() throws {
        let allowed: [Band] = [.cm70, .cm23]
        let target = try #require(BandStepping.target(tuning: TuningState(), band: .cm70, mode: .cw,
                                                      allowed: allowed, direction: 1))
        let transverter = TransverterEntry(name: "23cm", ifLowKHz: 144_000, ifHighKHz: 146_000,
                                           offsetKHz: 1_152_000, enabled: true)
        #expect(TransverterRig.toRig(target.hz, [transverter]) == 144_050_000)
        // Without a transverter the rig would get the real frequency.
        #expect(TransverterRig.toRig(target.hz, []) == 1_296_050_000)
    }

    @Test func outsideAContestSteppingStopsAtTenMetres() {
        let bands: [Band] = TuningState.bandsForStepping(contestBands: nil)
        #expect(!bands.contains { $0.isMicrowave })
        #expect(bands.last == .m10)
    }

    // MARK: - call field commands

    @Test func aFullMicrowaveFrequencyInTheCallFieldIsAQsy() throws {
        #expect(try CallFieldCommands.parse("1296200", currentFreqHz: 14_074_000) == .qsy(freqHz: 1_296_200_000))
        #expect(try CallFieldCommands.parse("10368100", currentFreqHz: 144_300_000) == .qsy(freqHz: 10_368_100_000))
    }

    /// A short kHz offset is added to the lower band edge, so on 3 cm `368.1` is 10 000.368 MHz (not 10 368.1 MHz);
    /// the full frequency in kHz is the way to a microwave frequency.
    @Test func aShortOffsetIsRelativeToTheLowerBandEdge() throws {
        #expect(try CallFieldCommands.parse("368.1", currentFreqHz: 10_368_050_000) == .qsy(freqHz: 10_000_368_100))
        #expect(try CallFieldCommands.parse("+100", currentFreqHz: 1_296_200_000) == .qsy(freqHz: 1_296_300_000))
    }

    // MARK: - spots

    @Test func spotsOnMicrowaveFrequenciesHaveTheirBand() throws {
        func band(_ line: String) throws -> Band? {
            try #require(DxSpotParser.parse(line)).band
        }
        #expect(try band("DX de OK1ABC:  10489750.0  A71BX  QO-100 NB  1234Z") == .cm3)
        #expect(try band("DX de OK1ABC:  2400250.0  A71BX  uplink  1234Z") == .cm13)
        #expect(try band("DX de OK1ABC:  1427750.0  A71BX  between  1234Z") == nil)
        #expect(try band("DX de OK1ABC:  739750.0  A71BX  LNB IF  1234Z") == nil)
    }

    @Test func spotNavigatorStaysOnTheMicrowaveBand() {
        let spots: [DxSpot] = [
            DxSpot(spotter: "S", freqHz: 10_368_300_000, dxCall: "OK2A", comment: ""),
            DxSpot(spotter: "S", freqHz: 1_296_300_000, dxCall: "OK2B", comment: ""),
            DxSpot(spotter: "S", freqHz: 10_368_900_000, dxCall: "OK2C", comment: ""),
        ]
        let next = SpotNavigator.next(spots, freqHz: 10_368_100_000, direction: 1) { _ in true }
        #expect(next?.dxCall == "OK2A")
        // No band at all (outside every band): nothing is filtered by band.
        #expect(SpotNavigator.next(spots, freqHz: 1_427_000_000, direction: -1) { _ in true }?.dxCall == "OK2B")
    }

    @Test func theSpotFilterAndMatrixKnowTheMicrowaveBands() {
        let rows: [SpotRow] = [
            AvailableMultsTests.row("A", 432_200_000), AvailableMultsTests.row("B", 1_296_200_000, mults: 1),
            AvailableMultsTests.row("C", 2_400_250_000), AvailableMultsTests.row("D", 1_427_750_000),
        ]
        let kept = AvailableMults.filter(rows: rows, bands: [.cm70, .cm23], modes: [])
        #expect(kept.map(\.call) == ["A", "B"])
        let matrix = AvailableMults.matrix(rows: rows)
        #expect(matrix[.cm23]?.total == 1 && matrix[.cm13]?.total == 1 && matrix[nil]?.total == 1)
    }

    // MARK: - the rest that depends on the band order

    @Test func bandNotesAndStatisticsOrderMicrowavesAfterSeventyCentimetres() {
        #expect(Band.allCases.sorted { $0.lowHz < $1.lowHz } == Band.allCases)
    }
}
