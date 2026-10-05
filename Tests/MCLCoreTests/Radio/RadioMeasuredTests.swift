import Testing
@testable import MCLCore

/// `radio/` and `DxSpot` against tables measured on Java (`RadioMeasured`, probes
/// a maintainer-only probe and `radio/ProbeRadio.java`): overflow
/// of `long`/`int` on external inputs, Unicode digits and spaces, band edges,
/// a sector across 0/360, `select`/`next` and `SpotNavigator`.
@Suite struct RadioMeasuredTests {

    // MARK: - Reading tables

    /// Columns of rows with the given `id` (without it), probe escaping unpacked.
    private static func rows(_ table: String, _ id: String) -> [[String]] {
        var result: [[String]] = []
        for line in table.split(separator: "\n", omittingEmptySubsequences: false) {
            let cols: [Substring] = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.first.map(String.init) == id else { continue }
            result.append(cols.dropFirst().map { unescape(String($0)) })
        }
        return result
    }

    /// The inverse of the probe's `esc`: `\uXXXX` (UTF-16 unit), `\t`, `\n`, `\r`, `\\`.
    private static func unescape(_ text: String) -> String {
        let units: [UInt16] = Array(text.utf16)
        var out: [UInt16] = []
        var i = 0
        while i < units.count {
            let unit = units[i]
            guard unit == 0x5C, i + 1 < units.count else {
                out.append(unit)
                i += 1
                continue
            }
            switch units[i + 1] {
            case 0x75: // u
                let hex = String(decoding: units[(i + 2)..<(i + 6)], as: UTF16.self)
                out.append(UInt16(hex, radix: 16)!)
                i += 6
            case 0x74: out.append(0x09); i += 2 // t
            case 0x6E: out.append(0x0A); i += 2 // n
            case 0x72: out.append(0x0D); i += 2 // r
            default: out.append(units[i + 1]); i += 2
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    private static func int(_ text: String) -> Int {
        Int(text)!
    }

    /// `Optional[123]` / `Optional.empty` from Java `Optional<Long>`.
    private static func optionalInt(_ text: String) -> Int? {
        if text == "Optional.empty" { return nil }
        return Int(text.dropFirst("Optional[".count).dropLast())!
    }

    /// A band by the Java constant name (`M20`, `CM70`); `<null>` → `nil`.
    private static func band(_ name: String) -> Band? {
        Band.javaV111Cases.first { String(describing: $0).uppercased() == name }
    }

    private static func optionalBand(_ text: String) -> Band? {
        if text == "Optional.empty" { return nil }
        return band(String(text.dropFirst("Optional[".count).dropLast()))!
    }

    private static func describe(_ band: Band?) -> String {
        band.map { "Optional[\(String(describing: $0).uppercased())]" } ?? "Optional.empty"
    }

    // MARK: - SplitFromComment

    @Test func splitFromCommentMatchesJava() {
        let research = Self.rows(RadioMeasured.research, "SPLIT.parse")
        #expect(research.count == 206)
        for (index, row) in research.enumerated() {
            // The last two probe rows: a bare `UP` with `defaultUp` 0 and 200,000.
            let defaultUp: Int = index == 204 ? 0 : index == 205 ? 200_000 : 1000
            let comment: String = index == 205 ? "UP" : row[1]
            let actual = SplitFromComment.parse(comment, spotFreqHz: Self.int(row[0]), defaultUpHz: defaultUp)
            #expect(actual == Self.optionalInt(row[2]), "spot \(row[0]) \(comment) default \(defaultUp)")
        }
        let radio = Self.rows(RadioMeasured.radio, "SPLIT.parse")
        #expect(radio.count == 183)
        for row in radio {
            let comment: String? = row[1] == "<null>" ? nil : row[1]
            let actual = SplitFromComment.parse(comment, spotFreqHz: Self.int(row[0]), defaultUpHz: Self.int(row[2]))
            #expect(actual == Self.optionalInt(row[3]), "spot \(row[0]) \(row[1]) default \(row[2])")
        }
    }

    // MARK: - FrequencySteps

    @Test func stepAndWarcMatchJava() {
        let steps = Self.rows(RadioMeasured.research, "FS.stepHz")
        #expect(steps.count == 11)
        for row in steps {
            let mode: Mode? = row[0] == "null" ? nil : Mode(rawValue: row[0])!
            #expect(FrequencySteps.stepHz(mode) == Self.int(row[1]), "\(row[0])")
        }
        let warc = Self.rows(RadioMeasured.research, "FS.isWarc")
        #expect(warc.count == Band.javaV111Cases.count)
        for row in warc {
            #expect(FrequencySteps.isWarc(Self.band(row[0])!) == (row[1] == "true"), "\(row[0])")
        }
    }

    @Test func wheelMatchesJava() {
        let research = Self.rows(RadioMeasured.research, "FS.wheel")
        #expect(research.count == 140)
        for row in research {
            let f = Self.int(row[0])
            let n = Self.int(row[1])
            let alt = row[2] == "true"
            let ctrl = row[3] == "true"
            #expect(FrequencySteps.wheel(f, mode: .cw, notches: n, alt: alt, ctrl: ctrl) == Self.int(row[4]), "\(row)")
            #expect(FrequencySteps.wheel(f, mode: nil, notches: n, alt: alt, ctrl: ctrl) == Self.int(row[5]), "\(row)")
        }
        let radio = Self.rows(RadioMeasured.radio, "FS.wheel")
        #expect(radio.count == 68)
        for row in radio {
            let n = Self.int(row[1])
            let alt = row[2] == "true"
            let ctrl = row[3] == "true"
            // `Integer.MAX_VALUE` clicks with Alt are 2^31 loop steps — measured in Java,
            // in Swift (debug) the test would take tens of seconds. `Integer.MIN_VALUE` is tested
            // (`Math.abs` negative → the loop does not run).
            if n == Int(Int32.max) && (alt || ctrl) { continue }
            let actual = FrequencySteps.wheel(Self.int(row[0]), mode: .ssb, notches: n, alt: alt, ctrl: ctrl)
            #expect(actual == Self.int(row[4]), "\(row)")
        }
    }

    @Test func roundToMatchesJava() {
        let radio = Self.rows(RadioMeasured.radio, "FS.roundTo")
        #expect(radio.count == 12)
        for row in radio where !row[3].hasPrefix("EXC") {
            let actual = FrequencySteps.roundTo(Self.int(row[0]), unitHz: Self.int(row[1]), direction: Self.int(row[2]))
            #expect(actual == Self.int(row[3]), "\(row)")
        }
        // Step 0 is `ArithmeticException: / by zero` in Java, a trap in Swift (`JavaMath.floorDiv`);
        // `wheel` never sends step 0 to `roundTo`.
        #expect(radio.last?[3] == "EXC ArithmeticException: / by zero")
    }

    @Test func nextBandMatchesJava() {
        let contest: [Band] = [.m10, .m160, .m80, .m40, .m20, .m15]
        let research = Self.rows(RadioMeasured.research, "FS.nextBand")
        #expect(research.count == 32)
        for row in research {
            let current = Self.band(row[0])
            let direction = Self.int(row[1])
            #expect(Self.describe(FrequencySteps.nextBand(current, allowed: contest, direction: direction)) == row[2])
            #expect(Self.describe(FrequencySteps.nextBand(current, allowed: [.m20], direction: direction)) == row[3])
            #expect(Self.describe(FrequencySteps.nextBand(current, allowed: [], direction: direction)) == row[4])
        }
        let dupes: [Band] = [.m20, .m40, .m20, .m40]
        let radio = Self.rows(RadioMeasured.radio, "FS.nextBand")
        #expect(radio.count == 42)
        for row in radio {
            let current = Self.band(row[0])
            let direction = Self.int(row[1])
            let label = "\(row[0]) \(row[1])"
            #expect(Self.describe(FrequencySteps.nextBand(current, allowed: contest, direction: direction)) == row[2], "\(label)")
            #expect(Self.describe(FrequencySteps.nextBand(current, allowed: dupes, direction: direction)) == row[3], "\(label)")
            #expect(
                Self.describe(FrequencySteps.nextBand(current, allowed: Band.javaV111Cases, direction: direction)) == row[4],
                "\(label)"
            )
        }
    }

    // MARK: - AntennaSelector

    @Test func coversMatchesJava() {
        let rows = Self.rows(RadioMeasured.research, "ANT.covers") + Self.rows(RadioMeasured.radio, "ANT.covers")
        #expect(rows.count == 25 + 28)
        for row in rows {
            let entry = AntennaEntry(code: 1, name: "A", bands: row[0], sector: "")
            let covered: [String] = Band.javaV111Cases.filter { AntennaSelector.covers(entry, $0) }.map(\.adif)
            #expect(covered.joined(separator: " ") == row[1], "\(row[0].unicodeScalars.map(\.value))")
        }
    }

    @Test func inSectorMatchesJava() {
        let rows = Self.rows(RadioMeasured.research, "ANT.inSector") + Self.rows(RadioMeasured.radio, "ANT.inSector")
        #expect(rows.count == 165 + 180)
        for row in rows {
            #expect(AntennaSelector.inSector(row[0], Self.int(row[1])) == (row[2] == "true"), "\(row)")
        }
    }

    private static let yagiUs = AntennaEntry(code: 1, name: "Yagi USA", bands: "20m,15m", sector: "270-360")
    private static let yagiJa = AntennaEntry(code: 2, name: "Yagi JA", bands: "14, 21", sector: "0-90")
    private static let dipole = AntennaEntry(code: 9, name: "Dipole", bands: "7, 10", sector: "")
    private static let blank = AntennaEntry(code: 3, name: "Blank sector", bands: "20m", sector: "  ")
    private static let odd = AntennaEntry(code: 4, name: "Odd sector", bands: "20m", sector: "abc")

    @Test func selectMatchesJava() {
        let all: [AntennaEntry] = [Self.yagiUs, Self.yagiJa, Self.dipole]
        let all2: [AntennaEntry] = [Self.blank, Self.yagiJa, Self.odd, Self.yagiUs]
        let rows = Self.rows(RadioMeasured.radio, "ANT.select")
        #expect(rows.count == 65)
        for row in rows {
            let band = Self.band(row[0])!
            let azimuth: Int? = row[1] == "<null>" ? nil : Self.int(row[1])
            let first = AntennaSelector.select(all, band: band, azimuth: azimuth).map { all[$0].name } ?? "<empty>"
            let second = AntennaSelector.select(all2, band: band, azimuth: azimuth).map { all2[$0].name } ?? "<empty>"
            #expect(first == row[2], "\(row)")
            #expect(second == row[3], "\(row)")
        }
    }

    /// Java looks up the current antenna by `indexOf` = **instance identity** (`AntennaEntry` has no
    /// `equals`): a foreign instance, even a value-equal one, is not found and `next` returns the band's first antenna.
    /// Swift carries identity as a position in the table; a foreign instance = `nil`.
    @Test func nextMatchesJava() {
        let all: [AntennaEntry] = [Self.yagiUs, Self.yagiJa, Self.dipole]
        let rows = Self.rows(RadioMeasured.radio, "ANT.next")
        #expect(rows.count == 25)
        // Probe order: yUs, yJa, dip, a foreign `Stranger`, a value copy of yUs, null.
        let currents: [Int?] = [0, 1, 2, nil, nil, nil]
        for (index, row) in rows.prefix(24).enumerated() {
            let band = Self.band(row[0])!
            let next = AntennaSelector.next(all, band: band, currentIndex: currents[index % 6])
            #expect((next.map { all[$0].name } ?? "<empty>") == row[2], "\(row)")
        }
        // Two value-equal antennas in the table: from the second (identity) it goes to the third.
        let twins: [AntennaEntry] = [Self.yagiUs, Self.yagiUs, Self.yagiJa]
        #expect(rows[24][2] == "Yagi JA")
        #expect(AntennaSelector.next(twins, band: .m20, currentIndex: 1).map { twins[$0].name } == "Yagi JA")
    }

    // MARK: - BandNotes

    @Test func bandNotesMatchJavaProbeP6() {
        let notes: [BandNote] = [
            BandNote(band: "", freqKHz: 14_100.0, text: "beacon"),
            BandNote(band: "20m", freqKHz: 0, text: "whole"),
            BandNote(band: " 20M ", freqKHz: 0, text: "w2"),
            BandNote(band: "", freqKHz: 14_100.0005, text: "half"),
            BandNote(band: "", freqKHz: 14_099.9995, text: "half-"),
            BandNote(band: "", freqKHz: 3_510.0, text: "dx"),
            BandNote(band: "xx", freqKHz: 0, text: "nob"),
            BandNote(band: "", freqKHz: -5, text: "neg"),
            BandNote(band: "40m", freqKHz: 7_010.0, text: "freqWins"),
        ]
        checkBandNotes(notes, table: RadioMeasured.research, forBand: 3, bandOf: 0, near: 18)
    }

    @Test func bandNotesMatchJavaProbeRadio() {
        let notes: [BandNote] = [
            BandNote(band: "", freqKHz: 14_100.0, text: "beacon"),
            BandNote(band: "", freqKHz: .nan, text: "nan"),
            BandNote(band: "", freqKHz: 1e300, text: "huge"),
            BandNote(band: "", freqKHz: .infinity, text: "inf"),
            BandNote(band: "20m", freqKHz: -0.0, text: "negzero"),
            BandNote(band: "20m", freqKHz: 0.0, text: "zero"),
            BandNote(band: " 20M ", freqKHz: 0, text: "upper"),
            BandNote(band: "20m\u{A0}", freqKHz: 0, text: "nbsp"),
            BandNote(band: "", freqKHz: 14_000.0, text: "edgeLow"),
            BandNote(band: "", freqKHz: 14_350.0, text: "edgeHigh"),
            BandNote(band: "", freqKHz: 14_350.0005, text: "past"),
            BandNote(band: "", freqKHz: 13_999.9995, text: "under"),
            BandNote(band: "", freqKHz: 14_100.0, text: "beacon2"),
        ]
        checkBandNotes(notes, table: RadioMeasured.radio, forBand: 2, bandOf: 13, near: 24)
    }

    private func checkBandNotes(_ notes: [BandNote], table: String, forBand: Int, bandOf: Int, near: Int) {
        let forBandRows = Self.rows(table, "BN.forBand")
        #expect(forBandRows.count == forBand)
        for row in forBandRows {
            let texts: [String] = BandNotes.forBand(notes, band: Self.band(row[0])!).map(\.text)
            #expect("[" + texts.joined(separator: ", ") + "]" == row[1], "\(row[0])")
        }
        let bandOfRows = Self.rows(table, "BN.bandOf")
        #expect(bandOfRows.count == bandOf)
        for (index, row) in bandOfRows.enumerated() {
            #expect(notes[index].text == row[0])
            #expect(Self.describe(BandNotes.bandOf(notes[index])) == row[1], "\(row[0])")
        }
        let nearRows = Self.rows(table, "BN.near")
        #expect(nearRows.count == near)
        for row in nearRows {
            let found = BandNotes.near(notes, freqHz: Self.int(row[0]), toleranceHz: Self.int(row[1]))
            #expect((found?.text ?? "<empty>") == row[2], "\(row)")
        }
    }

    // MARK: - DxSpot and SpotNavigator

    private static let spots: [DxSpot] = [
        DxSpot(spotter: "S", freqHz: 14_000_000, dxCall: "EDGELOW", comment: ""),
        DxSpot(spotter: "S", freqHz: 14_350_000, dxCall: "EDGEHIGH", comment: ""),
        DxSpot(spotter: "S", freqHz: 14_350_001, dxCall: "PAST", comment: ""),
        DxSpot(spotter: "S", freqHz: 13_999_999, dxCall: "UNDER", comment: ""),
        DxSpot(spotter: "S", freqHz: 14_025_050, dxCall: "FIFTY", comment: ""),
        DxSpot(spotter: "S", freqHz: 14_024_950, dxCall: "MINUSFIFTY", comment: ""),
        DxSpot(spotter: "S", freqHz: 14_025_051, dxCall: "FIFTYONE", comment: ""),
        DxSpot(spotter: "S", freqHz: 14_024_949, dxCall: "MINUSFIFTYONE", comment: ""),
        DxSpot(spotter: "S", freqHz: 14_030_000, dxCall: "TIE1", comment: ""),
        DxSpot(spotter: "S", freqHz: 14_020_000, dxCall: "TIEDOWN", comment: ""),
        DxSpot(spotter: "S", freqHz: 14_030_000, dxCall: "TIE2", comment: "", selfSpotted: true),
        DxSpot(spotter: "S", freqHz: Int.max, dxCall: "MAX", comment: ""),
        DxSpot(spotter: "S", freqHz: Int.min, dxCall: "MIN", comment: ""),
        DxSpot(spotter: "S", freqHz: 0, dxCall: "ZERO", comment: "", selfSpotted: true),
        DxSpot(spotter: "S", freqHz: 7_025_000, dxCall: "FORTY", comment: ""),
    ]

    @Test func dxSpotBandMatchesJava() {
        let rows = Self.rows(RadioMeasured.radio, "DXS.band")
        #expect(rows.count == Self.spots.count)
        for (index, row) in rows.enumerated() {
            let spot = Self.spots[index]
            #expect(spot.dxCall == row[0])
            #expect(spot.freqHz == Self.int(row[1]))
            #expect(Self.describe(spot.band) == row[2], "\(row)")
            #expect(spot.selfSpotted == (row[3] == "true"))
        }
        let network = DxSpot(spotter: "OK1XOE", freqHz: 14_025_000, dxCall: "DL1ABC", comment: "CQ")
        #expect(!network.selfSpotted, "a network spot (Java constructor with 4 fields)")
    }

    @Test func spotNavigatorMatchesJava() {
        let rows = Self.rows(RadioMeasured.radio, "SN.next")
        #expect(rows.count == 44)
        for row in rows {
            let freq = Self.int(row[0])
            let direction = Self.int(row[1])
            let any = SpotNavigator.next(Self.spots, freqHz: freq, direction: direction) { _ in true }
            let selfOnly = SpotNavigator.next(Self.spots, freqHz: freq, direction: direction) { $0.selfSpotted }
            let network = SpotNavigator.next(Self.spots, freqHz: freq, direction: direction) { !$0.selfSpotted }
            #expect((any?.dxCall ?? "<empty>") == row[2], "\(row)")
            #expect((selfOnly?.dxCall ?? "<empty>") == row[3], "\(row)")
            #expect((network?.dxCall ?? "<empty>") == row[4], "\(row)")
        }
    }
}
