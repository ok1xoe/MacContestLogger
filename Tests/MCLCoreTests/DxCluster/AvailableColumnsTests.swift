import Foundation
import Testing
@testable import MCLCore

/// N1MM Available beyond v1.1.1: the chosen columns and their widths, the sort of every column, the summary panel's
/// bands and best band, the speaker column's look at the waterfall, and the other VFO's frequency.
@Suite struct AvailableColumnsTests {

    static func row(_ call: String, _ freqHz: Int, mode: String = "CW", mults: Int = 0, snr: Int? = nil,
                    spotter: String = "S", points: Int = 1) -> SpotRow {
        SpotRow(call: call, freqHz: freqHz, azimuth: nil, mode: mode, newMultCount: mults, dupe: false, snr: snr,
                points: points, spotter: spotter)
    }

    static let rows: [SpotRow] = [
        row("OK1A", 14_010_000, mode: "SSB", mults: 1, snr: 12, spotter: "W3LPL"),
        row("DL1B", 7_010_000, mults: 0, spotter: "DK0XX"),
        row("AA1C", 21_020_000, mode: "FT8", mults: 2, snr: 30, spotter: "VE3"),
        row("JA1D", 14_020_000, mults: 0, snr: 5, spotter: "AB1"),
    ]

    // MARK: - columns

    @Test func savedColumnsKeepTheirOrderWithoutUnknownsOrRepeats() {
        #expect(AvailableColumn.visible([]) == AvailableColumn.defaultOrder)
        #expect(AvailableColumn.visible(["bogus"]) == AvailableColumn.defaultOrder)
        #expect(AvailableColumn.visible(["pts", "call", "pts", "x", "heard"]) == [.pts, .call, .heard])
        // The call always shows.
        #expect(AvailableColumn.visible(["freq", "time"]) == [.call, .freq, .time])
        #expect(AvailableColumn.chooserOrder([.call, .pts]).prefix(2) == [.call, .pts])
        #expect(AvailableColumn.chooserOrder([.call, .pts]).count == AvailableColumn.allCases.count)
        #expect(!AvailableColumn.defaultOrder.contains(.heard))
    }

    @Test func widthsAreClamped() {
        #expect(AvailableColumn.call.width(in: [:]) == 130)
        #expect(AvailableColumn.call.width(in: ["call": 5]) == AvailableColumn.widthRange.lowerBound)
        #expect(AvailableColumn.call.width(in: ["call": 9_999]) == AvailableColumn.widthRange.upperBound)
        #expect(AvailableColumn.freq.width(in: ["freq": 150]) == 150)
    }

    // MARK: - sort

    @Test func freqDirAndPtsKeepTheLegacyOrder() {
        for (column, legacy) in [(AvailableColumn.freq, AvailableMults.SortColumn.freq), (.dir, .dir), (.pts, .pts)] {
            for ascending in [true, false] {
                #expect(AvailableMults.sorted(Self.rows, by: column, ascending: ascending)
                        == AvailableMults.sorted(Self.rows, by: legacy, ascending: ascending))
            }
        }
    }

    @Test func everyOtherColumnSorts() {
        func calls(_ column: AvailableColumn, _ ascending: Bool = true,
                   facts: (SpotRow) -> AvailableRowFacts = { _ in AvailableRowFacts() }) -> [String] {
            AvailableMults.sorted(Self.rows, by: column, ascending: ascending, facts: facts).map(\.call)
        }
        #expect(calls(.call) == ["AA1C", "DL1B", "JA1D", "OK1A"])
        #expect(calls(.call, false) == ["OK1A", "JA1D", "DL1B", "AA1C"])
        #expect(calls(.mode) == ["DL1B", "JA1D", "AA1C", "OK1A"])
        #expect(calls(.spotter) == ["JA1D", "DL1B", "AA1C", "OK1A"])
        #expect(calls(.mult, false) == ["AA1C", "OK1A", "JA1D", "DL1B"])
        // A row without an SNR goes last both ways.
        #expect(calls(.snr) == ["JA1D", "OK1A", "AA1C", "DL1B"])
        #expect(calls(.snr, false) == ["AA1C", "OK1A", "JA1D", "DL1B"])
        // Time ascending = the newest spot first; an unknown time last.
        let base = Date(timeIntervalSince1970: 1_000_000)
        let times: [String: Date] = ["OK1A": base, "DL1B": base.addingTimeInterval(300),
                                     "AA1C": base.addingTimeInterval(60)]
        let facts: (SpotRow) -> AvailableRowFacts = { AvailableRowFacts(spottedAt: times[$0.call]) }
        #expect(calls(.time, facts: facts) == ["DL1B", "AA1C", "OK1A", "JA1D"])
        #expect(calls(.time, false, facts: facts) == ["OK1A", "AA1C", "DL1B", "JA1D"])
        let heard: (SpotRow) -> AvailableRowFacts = { AvailableRowFacts(heard: $0.call == "JA1D") }
        #expect(calls(.heard, false, facts: heard).first == "JA1D")
    }

    // MARK: - summary panel

    @Test func summaryBandsComeFromTheChoiceTheContestOrHf() {
        #expect(AvailableMults.summaryBands(configured: ["2m", "20m", "bogus"], contestBands: [.m40])
                == [.m20, .m2])
        #expect(AvailableMults.summaryBands(configured: [], contestBands: [.cm70, .m2, .m6]) == [.m6, .m2, .cm70])
        #expect(AvailableMults.summaryBands(configured: [], contestBands: []) == AvailableMults.matrixBands)
    }

    @Test func theBestBandHasTheMostMultsThenQs() {
        let matrix: [Band?: AvailableMults.Counts] = [
            .m20: .init(mults: 1, qs: 5, total: 6), .m40: .init(mults: 1, qs: 7, total: 7),
            .m15: .init(mults: 0, qs: 9, total: 9), .m10: .init(mults: 3, qs: 3, total: 3),
        ]
        #expect(AvailableMults.bestBand(matrix, bands: [.m40, .m20, .m15]) == .m40)
        #expect(AvailableMults.bestBand(matrix, bands: [.m40, .m20, .m10]) == .m10)
        #expect(AvailableMults.bestBand([:], bands: [.m20]) == nil)
    }

    // MARK: - speaker column

    @Test func audioToneIsTheInverseOfTheWaterfallsBandFrequency() {
        for mode in ["CW", "CWR", "USB", "LSB", "RTTY", "PKTUSB"] {
            for audio in [300.0, 650.0, 2_100.0] {
                let rf: Int64 = AudioToRf.rfHz(dialHz: 14_025_000, rawMode: mode, audioHz: audio, cwPitch: 600)
                #expect(SignalHeard.audioHz(rfHz: rf, dialHz: 14_025_000, rawMode: mode, cwPitch: 600) == audio,
                        "\(mode) \(audio)")
            }
        }
    }

    @Test func aBrightBinNearTheToneIsHeard() {
        var row = [Float](repeating: 0.05, count: 512)
        row[239] = 0.8 // 1400 Hz of 0…3000 Hz
        #expect(SignalHeard.isHeard(rows: [row], audioHz: 1_400, maxHz: 3_000))
        #expect(SignalHeard.isHeard(rows: [row], audioHz: 1_410, maxHz: 3_000))
        #expect(!SignalHeard.isHeard(rows: [row], audioHz: 1_600, maxHz: 3_000))
        #expect(!SignalHeard.isHeard(rows: [row], audioHz: -10, maxHz: 3_000))
        #expect(!SignalHeard.isHeard(rows: [row], audioHz: 3_000, maxHz: 3_000))
        #expect(!SignalHeard.isHeard(rows: [], audioHz: 1_400, maxHz: 3_000))
        // Only the newest rows count.
        let quiet = [Float](repeating: 0, count: 512)
        let old: [[Float]] = Array(repeating: quiet, count: SignalHeard.rowsToCheck) + [row]
        #expect(!SignalHeard.isHeard(rows: old, audioHz: 1_400, maxHz: 3_000))
    }

    /// A 700 Hz tone through the real waterfall: in CW (pitch 600) the spot 100 Hz above the dial is heard, one
    /// 1.5 kHz away and one outside the passband are not; without a dial nothing is.
    @Test func aToneInTheWaterfallIsHeardOnItsSpot() {
        let rate = 12_000.0
        let waterfall = Waterfall(sampleRate: rate, maxHz: 3_000, rows: 20)
        let samples: [Double] = (0..<(Waterfall.fftSize * 4)).map { 0.5 * sin(2 * Double.pi * 700 * Double($0) / rate) }
        #expect(waterfall.add(samples))
        let rows: [[Float]] = waterfall.latestRows(SignalHeard.rowsToCheck)
        #expect(rows.count == SignalHeard.rowsToCheck)
        let spectrum = SignalHeard.Spectrum(rows: rows, maxHz: waterfall.maxHz, dialHz: 14_025_000, rawMode: "CW",
                                            cwPitch: 600)
        #expect(spectrum.hears(freqHz: 14_025_100))
        #expect(!spectrum.hears(freqHz: 14_026_600))
        #expect(!spectrum.hears(freqHz: 14_030_000))
        let noDial = SignalHeard.Spectrum(rows: rows, maxHz: waterfall.maxHz, dialHz: 0, rawMode: "CW", cwPitch: 600)
        #expect(!noDial.hears(freqHz: 14_025_100))
        #expect(waterfall.latestRows(0).isEmpty)
    }

    // MARK: - the other VFO

    @Test func theInactiveVfoTakesAFrequency() {
        var vfo = VfoState(radioMode: "SO2R")
        vfo.setInactiveFrequency(7_010_000, vfo: 1)
        #expect(vfo.vfoFreq == [0, 7_010_000])
        // Not the active one, nothing ≤ 0, nothing out of range.
        vfo.setInactiveFrequency(14_000_000, vfo: 0)
        vfo.setInactiveFrequency(0, vfo: 1)
        vfo.setInactiveFrequency(3_500_000, vfo: 2)
        #expect(vfo.vfoFreq == [0, 7_010_000])
    }
}
