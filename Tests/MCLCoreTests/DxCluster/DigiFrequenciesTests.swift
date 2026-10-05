import Foundation
import Testing
@testable import MCLCore

/// Port of `dxcluster/DigiFrequenciesTest` (6) and `dxcluster/DigiFreqFileTest` (2).
@Suite struct DigiFrequenciesTests {

    private let table = DigiFrequencies.defaultTable()

    @Test func ft8OnStandardFrequencies() {
        #expect(table.modeAt(14_074_000) == "FT8") // 20m dial
        #expect(table.modeAt(50_313_000) == "FT8") // 6m
        #expect(table.modeAt(7_074_000) == "FT8")  // 40m
    }

    @Test func ft8WithinSubbandOffset() {
        // A spot at dial + audio offset (e.g. 14075.3 = JA2ODB from the cluster) → still FT8.
        #expect(table.modeAt(14_075_300) == "FT8")
    }

    @Test func ft4OnStandardFrequency() {
        #expect(table.modeAt(7_047_500) == "FT4")
        #expect(table.modeAt(14_080_000) == "FT4")
    }

    @Test func notDigiFrequency() {
        #expect(table.modeAt(14_100_000) == nil) // beacon/outside
        #expect(table.modeAt(7_020_000) == nil)  // CW segment
        #expect(table.isDigi(50_313_000))
        #expect(!table.isDigi(7_020_000))
    }

    @Test func missingFileFallsBackToDefault() {
        let d = DigiFrequencies.fromDir(URL(fileURLWithPath: "/nonexistent-digi-dir"))
        #expect(d.modeAt(14_074_000) == "FT8")
    }

    @Test func loadsExternalYaml() throws {
        try withDxTemporaryDirectory { dir in
            let yaml: String = "channels:\n"
                + "  - { mode: FT8, fromKhz: 14073.5, toKhz: 14077.0 }\n"
                + "  - { mode: MYMODE, fromKhz: 14200, toKhz: 14205 }\n"
            try yaml.write(to: dir.appendingPathComponent("digi_frequencies.yaml"), atomically: false, encoding: .utf8)
            let d = DigiFrequencies.fromDir(dir)
            #expect(d.modeAt(14_074_000) == "FT8")
            #expect(d.modeAt(14_202_000) == "MYMODE")
            // A frequency outside the supplied list is no longer digi (the table replaces the default).
            #expect(d.modeAt(50_313_000) == nil)
        }
    }

    // MARK: - DigiFreqFileTest

    @Test func roundTrip() throws {
        try withDxTemporaryDirectory { dir in
            let t = DigiFreqFile.Table(channels: [
                DigiFreqFile.Channel(mode: "FT8", fromKhz: 14073.5, toKhz: 14077.0),
                DigiFreqFile.Channel(mode: "FT4", fromKhz: 7046.5, toKhz: 7050.0),
            ])
            try DigiFreqFile.write(dir, t)
            let back = DigiFreqFile.read(dir)
            #expect(back.channels.count == 2)
            #expect(back.channels[0].mode == "FT8")
            #expect(back.channels[0].fromKhz == 14073.5)
            #expect(back.channels[0].toKhz == 14077.0)
            // And DigiFrequencies loads it.
            #expect(DigiFrequencies.fromDir(dir).modeAt(14_074_000) == "FT8")
        }
    }

    @Test func missingFileGivesEmpty() {
        let t = DigiFreqFile.read(URL(fileURLWithPath: "/nonexistent-digi"))
        #expect(t.channels.isEmpty)
    }
}
