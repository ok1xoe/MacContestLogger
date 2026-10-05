import Foundation
import Testing
@testable import MCLCore

/// `InfoLines` against `ui/RateWindow.kt` (`:263-384`) of v1.1.1. `countryLine`, `sunLine` and `dayShort` are the
/// real Kotlin functions measured on the JVM; `spotLine`, `wwvLine` and the header are transcribed
/// (maintainer-only probe).
@Suite struct InfoLinesTests {

    /// A `CallsignInfo` from a probe input: `prefix|entity|continent|cq|sp|lp|km|mi|sunrise|sunset|localNano|dow`.
    static func info(_ input: String) -> CallsignInfo {
        let f = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        func text(_ i: Int) -> String? { f[i] == "~" ? nil : f[i] }
        func int(_ i: Int) -> Int? { f[i] == "~" ? nil : Int(f[i]) }
        let day: CallsignInfo.DayOfWeek? = text(11).flatMap { name in
            CallsignInfo.DayOfWeek.allCases.first { $0.javaName == name }
        }
        return CallsignInfo(prefix: text(0), entityName: text(1), continent: text(2), cqZone: int(3),
                            shortPathDeg: int(4), longPathDeg: int(5), distanceKm: int(6), distanceMiles: int(7),
                            sunrise: int(8).map { Int32($0) }, sunset: int(9).map { Int32($0) },
                            dxLocalTime: text(10).flatMap { Int64($0) }, dxDayOfWeek: day)
    }

    @Test func countryAndSunLinesMatchTheJvm() {
        let country = InfoProbeTable.area("country")
        let sun = InfoProbeTable.area("sun")
        #expect(country.count == 10)
        #expect(sun.count == 10)
        for row in country {
            let value: CallsignInfo? = row.input == "null" ? nil : Self.info(row.input)
            let line = InfoLines.country(value)
            #expect((row.input == "null" ? "[" + line + "]" : line) == row.result, "country \(row.input)")
        }
        for row in sun {
            let value: CallsignInfo? = row.input == "null" ? nil : Self.info(row.input)
            let line = InfoLines.sun(value)
            #expect((row.input == "null" ? "[" + line + "]" : line) == row.result, "sun \(row.input)")
        }
    }

    @Test func dayShortMatchesTheJvm() {
        let rows = InfoProbeTable.area("dayShort")
        #expect(rows.count == 8)
        for row in rows {
            if row.input == "null" {
                #expect("[" + InfoLines.dayShort(nil) + "]" == row.result)
                continue
            }
            let day = CallsignInfo.DayOfWeek.allCases.first { $0.javaName == row.input }
            #expect(InfoLines.dayShort(day) == row.result, "\(row.input)")
        }
    }

    /// Only `út`, `čt`, `pá` go through `tr` (RW:375-384); the other four stay Czech in every language.
    @Test func onlyThreeDayNamesAreTranslated() {
        let english = SpotActionsTests.translator(["út": "Tu", "čt": "Th", "pá": "Fr", "po": "Mo"])
        let names = CallsignInfo.DayOfWeek.allCases.map { InfoLines.dayShort($0, translate: english) }
        #expect(names == ["po", "Tu", "st", "Th", "Fr", "so", "ne"])
    }

    @Test func callsignInfoMatchesTheJvm() throws {
        let rows = InfoProbeTable.area("callinfo")
        #expect(rows.count == 220)
        let dxcc = SpotAnalysisFixture.dxcc()
        for row in rows {
            let f = row.input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let info = try InfoLines.callsignInfo(typedCall: f[0], lookup: dxcc, myLat: try #require(Double(f[1])),
                                                  myLon: try #require(Double(f[2])),
                                                  now: InfoProbeTable.instant(millis: try #require(Int64(f[3]))))
            let text = InfoLines.country(info) + " // " + InfoLines.sun(info)
            #expect(text == row.result, "\(row.input)")
        }
    }

    @Test func wwvLineMatchesTheJvm() throws {
        let rows = InfoProbeTable.area("wwv")
        #expect(rows.count == 5)
        for row in rows {
            if row.input == "null" {
                #expect("[" + InfoLines.wwv(nil) + "]" == row.result)
                continue
            }
            let f = row.input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let w = WwvMessage(spotter: f[0], hourUtc: try #require(Int(f[1])), sfi: try #require(Int(f[2])),
                               aIndex: try #require(Int(f[3])), kIndex: try #require(Int(f[4])), conditions: f[5])
            #expect("[" + InfoLines.wwv(w) + "]" == row.result, "\(row.input)")
        }
    }

    /// A settable clock for the spot buffer.
    final class ClockBox: @unchecked Sendable {
        private let lock = NSLock()
        private var millis: Int64
        init(_ millis: Int64) { self.millis = millis }
        func set(_ value: Int64) { lock.lock(); millis = value; lock.unlock() }
        var date: Date { lock.lock(); defer { lock.unlock() }; return Date(timeIntervalSince1970: Double(millis) / 1000.0) }
    }

    @Test func spotLineMatchesTheJvm() throws {
        let rows = InfoProbeTable.area("spot")
        #expect(rows.count == 128)
        let base = InfoProbeTable.baseMillis
        let clock = ClockBox(base)
        let spots = SpotBuffer(maxAgeMinutes: 30, clock: { clock.date })
        spots.add(DxSpot(spotter: "VE3KI", freqHz: 14_090_070, dxCall: "MI0BPB", comment: "CW 25 WPM CQ"))
        clock.set(base + 61_000)
        spots.add(DxSpot(spotter: "OK1RR", freqHz: 14_025_000, dxCall: "DL1ABC", comment: ""))
        spots.add(DxSpot(spotter: "OK1RR", freqHz: 7_012_345, dxCall: "OK2ZZ", comment: "   "))
        spots.add(DxSpot(spotter: "DK0SK-#", freqHz: 3_500_005, dxCall: "W1AW", comment: "5 dB"))
        spots.add(DxSpot(spotter: "N0NBH", freqHz: 28_000_999, dxCall: "K1ABC", comment: "x"))
        spots.add(DxSpot(spotter: "N0NBH", freqHz: 144_300_000, dxCall: "JA1XYZ", comment: ""))
        for row in rows {
            let f = row.input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let separator = f[0] == "cs-CZ" ? "," : "."
            let now = try #require(Int64(f[1]))
            clock.set(now)
            let line = InfoLines.spot(call: f[2], spots: spots, now: InfoProbeTable.instant(millis: now),
                                      decimalSeparator: separator)
            #expect("[" + line + "]" == row.result, "\(row.input)")
        }
    }

    @Test func headerMatchesTheJvm() {
        let rows = InfoProbeTable.area("header")
        #expect(rows.count == 6)
        for row in rows {
            let f = row.input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let header = InfoLines.header(stationCall: f[0], sentExchange: f[1], operatorCall: f[2])
            let text = "[" + header.stationCall + "][" + (header.exchangeText ?? "") + "][" + header.operatorCall + "]"
            #expect(text == row.result, "\(row.input)")
        }
    }

    @Test func positionIsParsedLikeKotlin() {
        // AppState.myLatLon: trim, comma to point, toDoubleOrNull, NaN otherwise.
        let p = InfoLines.position(latitude: " 50,08 ", longitude: "14.42")
        #expect(p.lat == 50.08)
        #expect(p.lon == 14.42)
        let bad = InfoLines.position(latitude: "", longitude: "x")
        #expect(bad.lat.isNaN)
        #expect(bad.lon.isNaN)
    }

    @Test func typedCallIsNormalized() {
        #expect(InfoLines.normalizedCall("  ok1xoe ") == "OK1XOE")
        // A call shorter than two characters has no info (RW:304).
        #expect((try? InfoLines.callsignInfo(typedCall: " O ", lookup: SpotAnalysisFixture.dxcc(), myLat: 50, myLon: 15,
                                            now: .epoch)) == .some(nil))
    }
}
