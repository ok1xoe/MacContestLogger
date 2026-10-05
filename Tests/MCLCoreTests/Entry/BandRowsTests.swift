import Foundation
import Testing
@testable import MCLCore

/// `BAND_ROWS` of `ui/EntryPanel.kt:102-123`, dumped from the running v1.1.1 via reflection
/// (maintainer-only probe, lines `row`).
@Suite struct BandRowsTests {

    /// band, label, CW, PH, RY, DI (kHz; `nil` = the band has no segment for the column).
    static let measured: [(Band, String, Double?, Double?, Double?, Double?)] = [
        (.m160, "160", 1810.0, 1843.0, 1838.0, 1840.0),
        (.m80, "80", 3500.0, 3600.0, 3580.0, 3573.0),
        (.m60, "60", 5352.0, 5354.0, nil, 5357.0),
        (.m40, "40", 7000.0, 7060.0, 7040.0, 7074.0),
        (.m30, "30", 10100.0, nil, 10140.0, 10136.0),
        (.m20, "20", 14000.0, 14150.0, 14080.0, 14074.0),
        (.m17, "17", 18068.0, 18120.0, 18100.0, 18100.0),
        (.m15, "15", 21000.0, 21200.0, 21080.0, 21074.0),
        (.m12, "12", 24890.0, 24940.0, 24920.0, 24915.0),
        (.m10, "10", 28000.0, 28300.0, 28080.0, 28074.0),
        (.m6, "6", 50090.0, 50150.0, 50300.0, 50313.0),
        (.m2, "2", 144050.0, 144300.0, 144600.0, 144174.0),
        (.cm70, "70cm", 432050.0, 432200.0, 432600.0, 432174.0),
    ]

    @Test func tableMatchesKotlinVerbatim() {
        let javaRows: [BandRows.Row] = BandRows.all.filter { !$0.band.isMicrowave }
        #expect(javaRows.count == Self.measured.count)
        for (row, expected) in zip(javaRows, Self.measured) {
            #expect(row.band == expected.0)
            #expect(row.label == expected.1)
            #expect(row.cwKHz == expected.2)
            #expect(row.phKHz == expected.3)
            #expect(row.rttyKHz == expected.4)
            #expect(row.diKHz == expected.5)
        }
    }

    /// The five post-port microwave rows (IARU R1 narrow-band centres); the rest of the table is the Java one.
    @Test func microwaveRowsFollowTheJavaOnes() {
        let microwave: [BandRows.Row] = BandRows.all.filter { $0.band.isMicrowave }
        #expect(BandRows.all.suffix(5) == microwave[...])
        let expected: [(Band, String, Double, Double, Double?)] = [
            (.cm23, "23cm", 1296050.0, 1296200.0, 1296174.0), (.cm13, "13cm", 2320050.0, 2320200.0, nil),
            (.cm9, "9cm", 3400050.0, 3400200.0, nil), (.cm6, "6cm", 5760050.0, 5760200.0, nil),
            (.cm3, "3cm", 10368050.0, 10368200.0, nil),
        ]
        #expect(microwave.count == expected.count)
        for (row, e) in zip(microwave, expected) {
            #expect(row.band == e.0 && row.label == e.1)
            #expect(row.cwKHz == e.2 && row.phKHz == e.3 && row.diKHz == e.4 && row.rttyKHz == nil, "\(e.1)")
        }
        #expect(BandRows.startKHz(band: .cm3, column: .ph) == 10368200.0)
    }

    @Test func startKHzByColumn() {
        #expect(BandRows.startKHz(band: .m20, column: .cw) == 14000.0)
        #expect(BandRows.startKHz(band: .m20, column: .ph) == 14150.0)
        #expect(BandRows.startKHz(band: .m20, column: .ry) == 14080.0)
        #expect(BandRows.startKHz(band: .m20, column: .di) == 14074.0)
        #expect(BandRows.startKHz(band: .m30, column: .ph) == nil)
        #expect(BandRows.startKHz(band: .m60, column: .ry) == nil)
        #expect(BandRows.startKHz(band: .cm70, column: .di) == 432174.0)
    }

    @Test func everyBandHasExactlyOneRowInEnumOrder() {
        #expect(BandRows.all.map(\.band) == Band.allCases)
    }
}
