/// Band columns CW/PH/RY/DI of the entry panel and the segment start frequencies (kHz, IARU R1).
/// Verbatim `BAND_ROWS` of `ui/EntryPanel.kt:102-123`; `nil` = the band has no segment for that mode
/// (30 m has no phone, 60 m is not used for RTTY) and the grid cell is not clickable.
public enum BandRows {

    /// Grid column (Kotlin `cwKHz`, `phKHz`, `rttyKHz`, `diKHz`).
    public enum Column: CaseIterable, Sendable {
        case cw, ph, ry, di
    }

    public struct Row: Equatable, Sendable {
        public let band: Band
        public let label: String
        public let cwKHz: Double?
        public let phKHz: Double?
        public let rttyKHz: Double?
        public let diKHz: Double?

        public func startKHz(_ column: Column) -> Double? {
            switch column {
            case .cw: cwKHz
            case .ph: phKHz
            case .ry: rttyKHz
            case .di: diKHz
            }
        }
    }

    public static let all: [Row] = [
        Row(band: .m160, label: "160", cwKHz: 1810.0, phKHz: 1843.0, rttyKHz: 1838.0, diKHz: 1840.0),
        Row(band: .m80, label: "80", cwKHz: 3500.0, phKHz: 3600.0, rttyKHz: 3580.0, diKHz: 3573.0),
        // 60 m: the narrow 5351.5–5366.5 kHz allocation; no RTTY there.
        Row(band: .m60, label: "60", cwKHz: 5352.0, phKHz: 5354.0, rttyKHz: nil, diKHz: 5357.0),
        Row(band: .m40, label: "40", cwKHz: 7000.0, phKHz: 7060.0, rttyKHz: 7040.0, diKHz: 7074.0),
        // WARC bands have no contests; 30 m also has no phone segment.
        Row(band: .m30, label: "30", cwKHz: 10100.0, phKHz: nil, rttyKHz: 10140.0, diKHz: 10136.0),
        Row(band: .m20, label: "20", cwKHz: 14000.0, phKHz: 14150.0, rttyKHz: 14080.0, diKHz: 14074.0),
        Row(band: .m17, label: "17", cwKHz: 18068.0, phKHz: 18120.0, rttyKHz: 18100.0, diKHz: 18100.0),
        Row(band: .m15, label: "15", cwKHz: 21000.0, phKHz: 21200.0, rttyKHz: 21080.0, diKHz: 21074.0),
        Row(band: .m12, label: "12", cwKHz: 24890.0, phKHz: 24940.0, rttyKHz: 24920.0, diKHz: 24915.0),
        Row(band: .m10, label: "10", cwKHz: 28000.0, phKHz: 28300.0, rttyKHz: 28080.0, diKHz: 28074.0),
        Row(band: .m6, label: "6", cwKHz: 50090.0, phKHz: 50150.0, rttyKHz: 50300.0, diKHz: 50313.0),
        Row(band: .m2, label: "2", cwKHz: 144050.0, phKHz: 144300.0, rttyKHz: 144600.0, diKHz: 144174.0),
        Row(band: .cm70, label: "70cm", cwKHz: 432050.0, phKHz: 432200.0, rttyKHz: 432600.0, diKHz: 432174.0),
        // Post-port microwave rows (IARU R1 narrow-band centres of activity); no RTTY, only 23 cm has a digital
        // segment, so those cells are not clickable.
        Row(band: .cm23, label: "23cm", cwKHz: 1296050.0, phKHz: 1296200.0, rttyKHz: nil, diKHz: 1296174.0),
        Row(band: .cm13, label: "13cm", cwKHz: 2320050.0, phKHz: 2320200.0, rttyKHz: nil, diKHz: nil),
        Row(band: .cm9, label: "9cm", cwKHz: 3400050.0, phKHz: 3400200.0, rttyKHz: nil, diKHz: nil),
        Row(band: .cm6, label: "6cm", cwKHz: 5760050.0, phKHz: 5760200.0, rttyKHz: nil, diKHz: nil),
        Row(band: .cm3, label: "3cm", cwKHz: 10368050.0, phKHz: 10368200.0, rttyKHz: nil, diKHz: nil),
    ]

    /// Start of the segment of `band` for `column`; `nil` = none.
    public static func startKHz(band: Band, column: Column) -> Double? {
        all.first { $0.band == band }?.startKHz(column)
    }
}
