import Foundation
import Testing
@testable import MCLCore

/// The setup of a maintainer-only probe in Swift: a synthetic DXCC (six entities,
/// Canada without coordinates), the contest data of the fixtures, my station OK1XOE in JN79, synthetic callbook
/// records, and the probe's spot lists — only synthetic spots.
enum SpotAnalysisFixture {

    /// Synthetic DXCC: the first entity whose prefix starts the trimmed upper-case call wins (the probe's
    /// `SyntheticDxcc`).
    struct SyntheticDxcc: DxccLookup {
        let list: [DxccEntity]
        let prefixes: [[String]]

        func resolve(_ callsign: String?) -> DxccEntity? {
            guard let callsign else { return nil }
            let upper: String = JavaText.toUpperCase(JavaText.trim(callsign))
            for (index, entity) in list.enumerated() {
                if prefixes[index].contains(where: { DxClusterRegex.startsWith(upper, $0) }) {
                    return entity
                }
            }
            return nil
        }

        func entities() -> [DxccEntity] {
            list
        }
    }

    static func entity(_ code: Int, _ name: String, _ cc: String, _ continent: String, _ cq: [Int], _ itu: [Int],
                       _ lat: Double, _ lon: Double, _ prefix: String) -> DxccEntity {
        DxccEntity(entityCode: code, name: name, countryCode: cc, continents: [continent], cq: cq, itu: itu,
                   lat: lat, lon: lon, primaryPrefix: prefix)
    }

    static func dxcc() -> SyntheticDxcc {
        SyntheticDxcc(list: [
            entity(503, "Czech Republic", "CZ", "EU", [15], [28], 50.0, 15.0, "OK"),
            entity(230, "Germany", "DE", "EU", [14], [28], 51.0, 10.0, "DL"),
            entity(291, "United States", "US", "NA", [5, 4, 3], [8, 7, 6], 37.0, -96.0, "K"),
            entity(339, "Japan", "JA", "AS", [25], [45], 36.0, 138.0, "JA"),
            entity(1, "Canada", "CA", "NA", [5], [9], .nan, .nan, "VE"),
            entity(100, "Argentina", "AR", "SA", [13], [14], -34.0, -64.0, "LU"),
        ], prefixes: [["OK", "OL"], ["DL", "DA", "DJ", "DK"], ["K", "N", "W"], ["JA"], ["VE"], ["LU"]])
    }

    /// The probe's callbook (`CALLBOOK`).
    static let callbookRecords: [String: HamQthRecord] = [
        "W1AW": HamQthRecord(grid: "FN31", name: "Hiram", cqZone: "4", ituZone: "7"),
        "K2ZZ": HamQthRecord(grid: "", name: "Empty", cqZone: "", ituZone: ""),
        "JA1ABC": HamQthRecord(grid: "PM95", name: "", cqZone: "", ituZone: "45"),
    ]

    static let callbook: @Sendable (String) -> HamQthRecord? = { call in
        guard let record = callbookRecords[SpotAnalyzer.callbookKey(call)], !record.isEmpty else { return nil }
        return record
    }

    /// The probe's time of the logged QSOs.
    static let at: Date = Date(timeIntervalSince1970: 1_791_028_800)   // 2026-10-03T12:00:00Z

    /// A recording grid log (messages in Czech).
    final class LogLines: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []

        func append(_ line: String) {
            lock.lock()
            lines.append(line)
            lock.unlock()
        }

        func take() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            let out = lines
            lines = []
            return out
        }
    }

    /// The probe's environment: runtime, the analyzer inputs and the grid log.
    struct Environment {
        let runtime: ContestRuntime
        let data: URL
        let bandPlan: BandPlan
        let digi: DigiFrequencies
        let gridDb: GridDatabase
        let fieldMap: GridFieldMap
        let lines: LogLines
        let gridLog: SpotGridLog

        func analyzer() -> SpotAnalyzer {
            SpotAnalyzer(runtime: runtime, bandPlan: bandPlan, digiFrequencies: digi, gridDatabase: gridDb,
                         gridFieldMap: fieldMap, callbook: SpotAnalysisFixture.callbook, gridLog: gridLog,
                         now: { SpotAnalysisFixture.at })
        }

        /// Kotlin `activate(id)`: the runtime activation plus `gridLogged.clear()`.
        func activate(_ id: String) throws {
            if let error = runtime.activate(id: id) {
                Issue.record("activation failed: \(error.czech)")
                throw CancellationError()
            }
            gridLog.reset()
        }

        func log(_ call: String, _ band: String, _ mode: String, _ pairs: (String?, String?)...) throws {
            try runtime.log(call: call, band: band, mode: mode, exchange: JavaLinkedMap(pairs),
                            at: SpotAnalysisFixture.at)
        }
    }

    static func environment() throws -> Environment {
        let dxcc = dxcc()
        let data = try SessionFixture.contestData()
        let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(data.appendingPathComponent("multipliers"))
        let runtime = ContestRuntime(dxcc: dxcc, registry: registry,
                                     contestsDir: data.appendingPathComponent("contests"),
                                     myCall: { "OK1XOE" }, myGrid: { "JN79" })
        let lines = LogLines()
        let gridLog = SpotGridLog { message in lines.append(message.czech) }
        return Environment(runtime: runtime, data: data, bandPlan: BandPlan.fromDir(data),
                           digi: DigiFrequencies.fromDir(data), gridDb: GridDatabase.fromDir(data),
                           fieldMap: GridFieldMap.fromDir(data, dxcc), lines: lines, gridLog: gridLog)
    }

    static func spot(_ spotter: String, _ freqHz: Int, _ call: String, _ comment: String,
                     _ selfSpotted: Bool = false) -> DxSpot {
        DxSpot(spotter: spotter, freqHz: freqHz, dxCall: call, comment: comment, selfSpotted: selfSpotted)
    }

    static let basic: [DxSpot] = [
        spot("OK1RR", 14_025_000, "DL1ABC", ""),
        spot("OK1RR", 14_250_000, "LU1ABC", "SSB"),
        spot("OK1RR", 3_000_000, "OK1ABC", ""),
    ]

    /// CQ WW CW spots (indices as in the probe): dupe, no new mult, double mult, dupe on 40 m, worked, double,
    /// phone, FT8 frequency, unknown DXCC, no band, blank calls, 30 m, SNR overflow, RTTY, unknown comment mode,
    /// no coordinates with SNR, self spot on 80 m, another JA.
    static let cqww: [DxSpot] = [
        spot("OK1RR", 14_025_000, "DL1ABC", ""),
        spot("DK0SK-#", 14_030_000, "DL2XYZ", "CW 18 dB 25 WPM CQ"),
        spot("OK1RR", 14_010_000, "W1AW", ""),
        spot("OK1RR", 7_010_000, "W1AW", ""),
        spot("OK1RR", 21_020_000, "JA1ABC", ""),
        spot("OK1RR", 28_020_000, "JA1ABC", "5 dB"),
        spot("OK1RR", 14_250_000, "LU1ABC", "SSB"),
        spot("OK1RR", 14_074_000, "VE3ABC", ""),
        spot("OK1RR", 14_020_000, "ZZ9ZZ", ""),
        spot("OK1RR", 3_000_000, "OK1ABC", ""),
        spot("OK1RR", 14_015_000, "", ""),
        spot("OK1RR", 14_015_000, "   ", ""),
        spot("OK1RR", 10_110_000, "DL3AA", "CW"),
        spot("OK1RR", 14_005_000, "W2XX", "CW 99999999999 dB"),
        spot("OK1RR", 14_040_000, "K1ABC", "RTTY"),
        spot("OK1RR", 14_045_000, "K2ZZ", "XYZ"),
        spot("OK1RR", 14_010_000, "VE3ABC", "CW 7 dB"),
        spot("OK1ME", 3_510_000, "LU1ABC", "", true),
        spot("OK1RR", 28_020_000, "JA2ABC", ""),
    ]

    /// WW DIGI spots: grid in the comment (verified), CSV grid (dupe), JA grid, lower-case grids, a rejected-looking
    /// grid, no grid, CW, FT4, callbook grid, another band.
    static let digi: [DxSpot] = [
        spot("OK1RR", 14_074_000, "DL1AAH", "FT8 -12 dB JO52"),
        spot("OK1RR", 14_080_000, "DL1AE", "FT8"),
        spot("OK1RR", 14_075_000, "JA1XXX", "FT8 PM95"),
        spot("OK1RR", 21_075_000, "JA1XXX", "FT8 jo52 pm96"),
        spot("OK1RR", 14_076_000, "W1AW", "FT8 JN79"),
        spot("OK1RR", 14_077_000, "K9ZZZ", "FT8"),
        spot("OK1RR", 7_010_000, "OK1ABC", "CW"),
        spot("OK1RR", 21_074_000, "LU1ABC", "FT4 GG66"),
        spot("OK1RR", 28_074_000, "JA1ABC", ""),
        spot("OK1RR", 7_074_000, "DL1AAH", ""),
    ]

    /// IARU HF spots: HQ stations (logged, other band, `W1AW/4`, lower case with a space, unknown DXCC), a zone
    /// station, phone.
    static let iaru: [DxSpot] = [
        spot("OK1RR", 14_030_000, "DA0HQ", ""),
        spot("OK1RR", 7_030_000, "DA0HQ", ""),
        spot("OK1RR", 14_035_000, "W1AW/4", ""),
        spot("OK1RR", 14_036_000, "w1aw/4 ", ""),
        spot("OK1RR", 21_030_000, "8N1HQ", ""),
        spot("OK1RR", 14_040_000, "DL5AA", ""),
        spot("OK1RR", 14_200_000, "W1AW", ""),
    ]

    /// OK-OM DX CW spots (districts grid): logged, other band, a DX station.
    static let okom: [DxSpot] = [
        spot("OK1RR", 14_025_000, "OK1ABC", ""),
        spot("OK1RR", 7_025_000, "OK1ABC", ""),
        spot("OK1RR", 14_030_000, "DL1ABC", ""),
    ]

    /// ARRL DX CW spots (sections grid): logged, another W station.
    static let arrl: [DxSpot] = [
        spot("OK1RR", 14_025_000, "W1AW", ""),
        spot("OK1RR", 7_025_000, "K2ZZ", ""),
    ]

    /// Java `String.valueOf` of a nullable value.
    static func str(_ value: Int?) -> String {
        value.map { String($0) } ?? "null"
    }

    /// The probe's escaping: UTF-16 units < 0x20, > 0x7E and `\` as `\uXXXX`.
    static func esc(_ text: String?) -> String {
        guard let text else { return "null" }
        var out = ""
        for unit in text.utf16 {
            if unit < 0x20 || unit > 0x7E || unit == 0x5C {
                out += "\\u" + String(format: "%04X", Int(unit))
            } else {
                out += String(UnicodeScalar(UInt8(unit)))
            }
        }
        return out
    }

    /// Java `AbstractMap.toString` of a `LinkedHashMap<String, String>`.
    static func mapText(_ map: JavaLinkedMap<String>) -> String {
        var parts: [String] = []
        for key in map.keys {
            parts.append((key ?? "null") + "=" + (map[key] ?? "null"))
        }
        return "{" + parts.joined(separator: ", ") + "}"
    }
}
