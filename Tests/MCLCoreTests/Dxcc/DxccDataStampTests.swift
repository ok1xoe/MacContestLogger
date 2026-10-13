import Foundation
import Testing
@testable import MCLCore

/// The DXCC data stamp of a log (N1MM: warn when the database's country table is older than the country file).
@Suite struct DxccDataStampTests {

    static let day1 = Date(timeIntervalSince1970: 1_790_000_000)
    static let day2 = Date(timeIntervalSince1970: 1_790_086_400)

    @Test func encodesAndReadsBackToTheSecond() throws {
        let stamp = DxccDataStamp(source: .clubLog, date: Date(timeIntervalSince1970: 1_790_000_000.75))
        #expect(stamp.encoded == "clublog 2026-09-21T14:13:20Z")
        #expect(stamp.day == "2026-09-21")
        let read = try #require(DxccDataStamp(encoded: stamp.encoded))
        #expect(read == stamp)
        #expect(DxccDataStamp(encoded: "cty.dat 2026-09-21T14:13:20Z")?.source == .ctyDat)
        #expect(DxccDataStamp(encoded: "dxcc.json 2026-09-21T14:13:20Z")?.source == .dxccJson)
        #expect(DxccDataStamp(encoded: "") == nil)
        #expect(DxccDataStamp(encoded: "other 2026-09-21T14:13:20Z") == nil)
        #expect(DxccDataStamp(encoded: "clublog yesterday") == nil)
    }

    /// The source follows `ContestEnvironment.load`: Club Log when its copy is in use, else `cty.dat`, else
    /// `dxcc.json`; the file dates come from the injected function.
    @Test func theCurrentStampFollowsTheSourceInUse() {
        let clubLog = URL(fileURLWithPath: "/data/clublog")
        let dxcc = URL(fileURLWithPath: "/data/dxcc-json")
        var files: [String: Date] = [
            "/data/clublog/cty.json": Self.day1, "/data/dxcc-json/cty.dat": Self.day1,
            "/data/dxcc-json/dxcc.json": Self.day2,
        ]
        let dates: (URL) -> Date? = { files[$0.path] }
        let state = ClubLogCtyCache.State(downloadedAt: Self.day2, lastAttemptAt: Self.day2)
        #expect(DxccDataStamp.current(clubLogInUse: true, clubLogState: state, clubLogDir: clubLog, dxccDir: dxcc,
                                      modificationDate: dates) == DxccDataStamp(source: .clubLog, date: Self.day2))
        #expect(DxccDataStamp.current(clubLogInUse: true, clubLogState: ClubLogCtyCache.State(), clubLogDir: clubLog,
                                      dxccDir: dxcc, modificationDate: dates)
                == DxccDataStamp(source: .clubLog, date: Self.day1), "no download time: the cached file's date")
        #expect(DxccDataStamp.current(clubLogInUse: false, clubLogState: state, clubLogDir: clubLog, dxccDir: dxcc,
                                      modificationDate: dates) == DxccDataStamp(source: .ctyDat, date: Self.day1))
        files["/data/dxcc-json/cty.dat"] = nil
        let withoutCty: (URL) -> Date? = { files[$0.path] }
        #expect(DxccDataStamp.current(clubLogInUse: false, clubLogState: nil, clubLogDir: nil, dxccDir: dxcc,
                                      modificationDate: withoutCty) == DxccDataStamp(source: .dxccJson, date: Self.day2))
        #expect(DxccDataStamp.current(clubLogInUse: false, clubLogState: nil, clubLogDir: nil, dxccDir: nil,
                                      modificationDate: withoutCty) == nil)
    }

    @Test func aRealFileGivesItsModificationDate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("cty.dat")
        try Data("x".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Self.day1], ofItemAtPath: file.path)
        #expect(DxccDataStamp.fileModificationDate(file) == Self.day1)
        #expect(DxccDataStamp.fileModificationDate(dir.appendingPathComponent("none")) == nil)
        #expect(DxccDataStamp.current(clubLogInUse: false, clubLogState: nil, clubLogDir: nil, dxccDir: dir)
                == DxccDataStamp(source: .ctyDat, date: Self.day1))
    }

    @Test func theDecisionWhenADatabaseIsOpened() {
        let old = DxccDataStamp(source: .ctyDat, date: Self.day1)
        let new = DxccDataStamp(source: .clubLog, date: Self.day2)
        #expect(DxccDataStamp.decide(stored: old.encoded, current: nil, hasQsos: true) == .keep)
        #expect(DxccDataStamp.decide(stored: nil, current: new, hasQsos: false) == .store(new))
        #expect(DxccDataStamp.decide(stored: nil, current: new, hasQsos: true) == .store(new),
                "a log from before the stamps is not flagged")
        #expect(DxccDataStamp.decide(stored: "garbage", current: new, hasQsos: true) == .store(new))
        #expect(DxccDataStamp.decide(stored: old.encoded, current: new, hasQsos: true)
                == .warn(stored: old, current: new))
        #expect(DxccDataStamp.decide(stored: old.encoded, current: new, hasQsos: false) == .store(new))
        #expect(DxccDataStamp.decide(stored: new.encoded, current: new, hasQsos: true) == .keep)
        #expect(DxccDataStamp.decide(stored: new.encoded, current: old, hasQsos: true) == .keep,
                "older data than the log's is not flagged")
    }
}
