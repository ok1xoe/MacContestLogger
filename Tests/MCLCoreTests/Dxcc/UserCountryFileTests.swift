import Foundation
import Testing
@testable import MCLCore

/// N1MM „Import country list from downloaded file": the imported `cty.dat` is checked, kept in the data folder, and
/// is the DXCC source while it exists.
@Suite struct UserCountryFileTests {

    private static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("country-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func aCountryFileIsInstalledAndRemoved() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("wl_cty.dat")
        try Data(CtyDxccResolverTests.ctySource.utf8).write(to: source)
        let data = dir.appendingPathComponent("data")
        #expect(UserCountryFile.load(dataDir: data) == nil)
        #expect(try UserCountryFile.install(from: source, dataDir: data) == 5)
        #expect(UserCountryFile.url(dataDir: data).path.hasSuffix("/data/country/cty.dat"))
        #expect(UserCountryFile.load(dataDir: data) == Data(CtyDxccResolverTests.ctySource.utf8))
        #expect(try UserCountryFile.remove(dataDir: data))
        #expect(try !UserCountryFile.remove(dataDir: data))
        #expect(UserCountryFile.load(dataDir: data) == nil)
    }

    @Test func aFileWithoutCountriesIsRefusedAndTheEarlierImportStays() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = dir.appendingPathComponent("cty.dat")
        try Data(CtyDxccResolverTests.ctySource.utf8).write(to: good)
        let bad = dir.appendingPathComponent("notes.txt")
        try Data("hello world\n".utf8).write(to: bad)
        try UserCountryFile.install(from: good, dataDir: dir)
        #expect(throws: UserCountryFile.Failure.noEntities) {
            try UserCountryFile.install(from: bad, dataDir: dir)
        }
        #expect(UserCountryFile.load(dataDir: dir) == Data(CtyDxccResolverTests.ctySource.utf8))
        #expect(throws: UserCountryFile.Failure.self) {
            try UserCountryFile.install(from: dir.appendingPathComponent("missing.dat"), dataDir: dir)
        }
    }

    @Test func theImportedFileIsTheDxccSourceBeforeClubLogAndTheLocalData() throws {
        let root = try #require(Bundle.module.url(forResource: "contest-data", withExtension: nil))
        let tiny = "Atlantis:  01:  01:  EU:  10.00:  10.00:  0.0:  ZZ9:\n    OK,ZZ9;\n"
        let environment = ContestEnvironment.load(dataRoot: root.path, dxccDir: nil, fallbackDataRoot: "/nonexistent",
                                                  clubLog: try ClubLogCtyTests.fixture(), userCty: Data(tiny.utf8))
        #expect(environment.dxcc?.resolve("OK1XOE")?.name == "Atlantis")
        // A file without countries is ignored: Club Log stays.
        let ignored = ContestEnvironment.load(dataRoot: root.path, dxccDir: nil, fallbackDataRoot: "/nonexistent",
                                              clubLog: try ClubLogCtyTests.fixture(), userCty: Data("x".utf8))
        #expect(ignored.dxcc is ClubLogCtyResolver)
    }

    @Test func theStampOfAnImportedFileIsItsDate() {
        let file = URL(fileURLWithPath: "/data/country/cty.dat")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let stamp = DxccDataStamp.current(clubLogInUse: true, clubLogState: nil, clubLogDir: nil, dxccDir: nil,
                                          userCty: file, modificationDate: { $0 == file ? date : nil })
        #expect(stamp == DxccDataStamp(source: .ctyDat, date: date))
    }
}
