import Foundation
import Testing
@testable import MCLCore

/// The `bcast` rows of `IntegrationsProbe.java` (the private `contactData`, `radioData`, `scoreData`, `appInfoData` of
/// `AppState` v1.1.1, rendered through `BroadcastXml`) replayed through `BroadcastMapping`, plus the pins of the
/// values the probe cannot vary (the session number, the replace arguments).
@Suite struct BroadcastMappingTests {

    typealias F = IntegrationsFixture

    static let contestNr: Int32 = 123_456_789

    static func mask(_ text: String) -> String {
        text.replacingOccurrences(of: "\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}", with: "<instant>",
                                  options: .regularExpression)
    }

    static func fullQso() -> Qso {
        var q = Qso()
        q.call = "DL1ABC"
        q.timestampUtc = Date(timeIntervalSince1970: 1_791_021_600) // 2026-10-03T10:00:00Z
        q.freqHz = 14_025_000
        q.mode = .cw
        q.continent = "EU"
        q.rstSent = "599"
        q.rstRcvd = "579"
        q.serialSent = 5
        q.serialRcvd = 14
        q.points = 3
        q.multiplier = true
        q.uuid = "11111111-2222-3333-4444-555555555555"
        return q
    }

    @Test func rowsMatchJvm() throws {
        let rows = F.rows("bcast")
        #expect(rows.count == 22)
        for contest in [nil, "cq-ww-cw"] as [String?] {
            let tag: String = contest ?? "none"
            let runtime = try F.runtime(contest: contest)
            if contest != nil {
                try runtime.log(call: "DL1ABC", band: "20m", mode: "CW", exchange: JavaLinkedMap([("rst", "599"), ("zone", "14")]))
                try runtime.log(call: "JA1XYZ", band: "15m", mode: "CW", exchange: JavaLinkedMap([("rst", "599"), ("zone", "25")]))
            }
            var got: [String: String] = [:]
            let name: String? = runtime.activeName
            for (label, qso) in [("full", Self.fullQso()), ("bare", Qso())] {
                let data = BroadcastMapping.contactData(qso, contestName: name, contestNr: Self.contestNr,
                                                        stationCall: F.ownCall)
                got["contact-" + label] = BroadcastXml.contactInfo(data)
                let replace = BroadcastMapping.replace(old: qso, new: qso, contestName: name, contestNr: Self.contestNr,
                                                       stationCall: F.ownCall)
                got["replace-" + label] = BroadcastXml.contactReplace(replace.data, oldCall: replace.oldCall,
                                                                       oldTs: replace.oldTimestamp)
            }
            let score = BroadcastMapping.scoreData(isContestActive: runtime.isActive, score: runtime.score,
                                                   activeName: name, activeId: runtime.activeId,
                                                   stationCall: F.ownCall, operatorCall: F.ownCall,
                                                   now: Date(timeIntervalSince1970: 1_791_021_600))
            got["score"] = score.map { Self.mask(BroadcastXml.dynamicResults($0)) } ?? "<null>"
            got["appinfo"] = BroadcastXml.appInfo(BroadcastMapping.appInfoData(contestNr: Self.contestNr,
                                                                               contestName: name, stationCall: F.ownCall))
            let rigs: [(Bool, RigState?, RunMode)] = [
                (false, nil, .searchAndPounce),
                (true, nil, .searchAndPounce),
                (true, RigState(freqHz: 14_025_000, mode: .cw, rawMode: "CW", passband: 500), .searchAndPounce),
                (true, RigState(freqHz: 7_074_000, mode: .ft8, rawMode: "PKTUSB", passband: 3000), .run),
                (true, RigState(freqHz: 3_600_000, mode: nil, rawMode: "XYZ", passband: 0), .run),
            ]
            for (index, rig) in rigs.enumerated() {
                let radio = BroadcastMapping.radioData(stationCall: F.ownCall, catConnected: rig.0, rig: rig.1,
                                                       operatorCall: F.ownCall, runMode: rig.2)
                got["radio-\(index)"] = radio.map { BroadcastXml.radioInfo($0) } ?? "<null>"
            }
            var compared = 0
            for row in rows where row[1] == tag {
                compared += 1
                let java: String = F.unescape(row[3])
                if got[row[2]] != java {
                    Issue.record("\(tag) \(row[2])\nSwift: \(got[row[2]] ?? "missing")\nJava:  \(java)")
                }
            }
            #expect(compared == 11)
        }
    }

    @Test func contestNrKeepsThe31LowBits() {
        #expect(BroadcastMapping.contestNr(nowMs: 0) == 0)
        #expect(BroadcastMapping.contestNr(nowMs: 123_456_789) == 123_456_789)
        #expect(BroadcastMapping.contestNr(nowMs: 0x7FFF_FFFF) == Int32.max)
        #expect(BroadcastMapping.contestNr(nowMs: 0x8000_0000) == 0)
        #expect(BroadcastMapping.contestNr(nowMs: 0x1_2345_6789) == 0x2345_6789)
        // A current time: positive, below 2^31.
        let now = BroadcastMapping.contestNr(nowMs: 1_791_021_600_123)
        #expect(now >= 0)
        #expect(Int64(now) == 1_791_021_600_123 & 0x7FFF_FFFF)
    }

    /// A Kotlin bug is fixed here: `oldcall` and `oldtimestamp` come from the QSO before the edit, the rest from the edit.
    @Test func replaceCarriesTheOriginalCallAndTimeAsTheOldOnes() {
        let original: Qso = Self.fullQso()
        var edited: Qso = original
        edited.call = "DL9XYZ"
        let replace = BroadcastMapping.replace(old: original, new: edited, contestName: "X", contestNr: 1,
                                               stationCall: F.ownCall)
        #expect(replace.oldCall == "DL1ABC")
        #expect(replace.oldTimestamp == original.timestampUtc)
        #expect(replace.data.call == "DL9XYZ")
        #expect(replace.data.timestamp == original.timestampUtc)
    }

    @Test func aTimeEditKeepsTheOriginalTimeAsOld() {
        let original: Qso = Self.fullQso()
        var edited: Qso = original
        edited.timestampUtc = original.timestampUtc?.addingTimeInterval(120)
        let replace = BroadcastMapping.replace(old: original, new: edited, contestName: "X", contestNr: 1,
                                               stationCall: F.ownCall)
        #expect(replace.oldCall == "DL1ABC")
        #expect(replace.oldTimestamp == original.timestampUtc)
        #expect(replace.data.timestamp == edited.timestampUtc)
        #expect(replace.data.timestamp != replace.oldTimestamp)
    }

    @Test func anEditOfNeitherCallNorTimeHasIdenticalOldAndNewValues() {
        let original: Qso = Self.fullQso()
        var edited: Qso = original
        edited.rstSent = "579"
        let replace = BroadcastMapping.replace(old: original, new: edited, contestName: "X", contestNr: 1,
                                               stationCall: F.ownCall)
        #expect(replace.oldCall == replace.data.call)
        #expect(replace.oldTimestamp == replace.data.timestamp)
        #expect(replace.data.snt == "579")
    }

    @Test func scoreNameFallsBackToTheIdAndThenToEmpty() {
        let state = ScoreState(qsoCount: 1, qsoPoints: 3, multTotal: 1, multByGroup: JavaLinkedMap<Int32>(),
                               bonusPoints: 0, qtcPoints: 0, total: 6)
        let now = Date(timeIntervalSince1970: 0)
        func data(_ name: String?, _ id: String?) -> BroadcastXml.ScoreData? {
            BroadcastMapping.scoreData(isContestActive: true, score: state, activeName: name, activeId: id,
                                       stationCall: "A", operatorCall: "B", now: now)
        }
        #expect(data("Name", "id")?.contest == "Name")
        #expect(data(nil, "id")?.contest == "id")
        #expect(data(nil, nil)?.contest == "")
        #expect(data("", "id")?.contest == "")
        #expect(data("Name", "id")?.score == 6)
        #expect(data("Name", "id")?.ops == "B")
        #expect(BroadcastMapping.scoreData(isContestActive: false, score: state, activeName: "N", activeId: "i",
                                           stationCall: "A", operatorCall: "B", now: now) == nil)
        #expect(BroadcastMapping.scoreData(isContestActive: true, score: nil, activeName: "N", activeId: "i",
                                           stationCall: "A", operatorCall: "B", now: now) == nil)
    }
}
