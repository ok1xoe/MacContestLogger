import Foundation
import Testing
@testable import MCLCore

/// The probe table a maintainer-only probe, read from the repository.
enum RigKeyingProbeTable {

    struct Row: Equatable {
        let area: String
        let input: String
        let result: String
    }

    static let rows: [Row] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/jvm-probes/rig-keying-probe.tsv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return Row(area: parts[0], input: parts[1], result: parts.count > 2 ? parts[2] : "")
        }
    }()

    static func area(_ name: String) -> [Row] {
        rows.filter { $0.area == name }
    }
}

/// `CatStatusLine` against `CatConnection.format` (`CC:160-163`) and `AppState.khz` measured on the JVM.
@Suite struct CatStatusLineTests {

    @Test func probeTableIsPresent() {
        #expect(RigKeyingProbeTable.rows.count > 1_000)
    }

    /// Every `status` row: boundary frequencies (HALF_UP at .x5, negative, `Long.MAX_VALUE`) × known/unknown mode.
    @Test func statusLineMatchesTheJvm() throws {
        let rows = RigKeyingProbeTable.area("status")
        #expect(rows.count == 49)
        for row in rows {
            let parts = row.input.split(separator: " ").map(String.init)
            let freq = try #require(Int64(parts[0]))
            let state: RigState
            switch parts[1] {
            case "null": state = RigState(freqHz: freq, mode: nil, rawMode: "PKTUSB", passband: 0)
            case "empty": state = RigState(freqHz: freq, mode: nil, rawMode: "", passband: 0)
            default:
                let mode = try #require(Mode(rawValue: parts[1]))
                state = RigState(freqHz: freq, mode: mode, rawMode: "RAW", passband: 0)
            }
            #expect(CatStatusLine.format(state) == row.result, "\(row.input)")
        }
    }

    @Test func statusLineHasTwoSpacesAndTheRawModeWhenUnmapped() {
        let state = RigState(freqHz: 14_025_050, mode: nil, rawMode: "PKTLSB", passband: 0)
        #expect(CatStatusLine.format(state) == "TRX: 14025.1 kHz  PKTLSB")
        #expect(CatStatusLine.format(state) == CatSession.format(state))
    }

    @Test func khzAndFieldTextMatchTheJvm() throws {
        let rows = RigKeyingProbeTable.area("khz")
        #expect(rows.count == 8)
        for row in rows {
            let hz = try #require(Int64(row.input))
            #expect(CatStatusLine.khz(hz) + " | " + CatStatusLine.fieldText(hz) == row.result, "\(row.input)")
        }
    }
}
