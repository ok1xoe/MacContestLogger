import Testing
@testable import MCLCore

/// Port of the Java `BandNotesTest` (1 test, same name).
@Suite struct BandNotesTests {

    private let beacon = BandNote(band: "", freqKHz: 14_100.0, text: "NCDXF majáky")
    private let whole = BandNote(band: "20m", freqKHz: 0, text: "Run nad 14 040")
    private let dx = BandNote(band: "", freqKHz: 3_510.0, text: "DX okno")
    private var all: [BandNote] { [beacon, whole, dx] }

    @Test func perBandAndNear() {
        #expect(BandNotes.forBand(all, band: .m20) == [whole, beacon])
        #expect(BandNotes.forBand(all, band: .m80) == [dx])
        #expect(BandNotes.near(all, freqHz: 14_100_300, toleranceHz: 500) == beacon)
        #expect(BandNotes.near(all, freqHz: 14_102_000, toleranceHz: 500) == nil)
    }
}
