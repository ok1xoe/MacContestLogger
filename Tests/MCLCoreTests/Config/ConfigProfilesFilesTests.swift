import Foundation
import Testing
@testable import MCLCore

/// The file layer of profile loading against a maintainer-only probe (v1.1.1
/// `ConfigProfiles.loadInto` before Jackson parses, `file(name)` with Java `trim()`, `delete`).
@Suite struct ConfigProfilesFilesTests {

    static func make() throws -> (dir: URL, profiles: ConfigProfiles<AppConfig>) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ConfigProfilesFiles-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("plain.json"))
        try Data("{}".utf8).write(to: dir.appendingPathComponent("\u{a0}nbsp\u{a0}.json"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("folder.json"),
                                                withIntermediateDirectories: false)
        return (dir, ConfigProfiles<AppConfig>(dir: dir))
    }

    /// `(class, message)` of the error `profileData` throws, `("OK", "")` without one.
    static func outcome(_ profiles: ConfigProfiles<AppConfig>, _ name: String) -> (String, String) {
        do {
            _ = try profiles.profileData(name)
            return ("OK", "")
        } catch {
            let described = JavaThrowables.describe(error)
            return (described.javaClass, described.message ?? "null")
        }
    }

    @Test func profileDataMatchesTheProbe() throws {
        let (dir, profiles) = try Self.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Self.outcome(profiles, "missing") == ("java.io.IOException", "Profil neexistuje: missing"))
        #expect(Self.outcome(profiles, "folder")
            == ("java.io.FileNotFoundException", dir.appendingPathComponent("folder.json").path + " (Is a directory)"))
        // Java `trim()`: ASCII blanks and tabs go, a no-break space stays part of the name.
        #expect(Self.outcome(profiles, "  plain \t") == ("OK", ""))
        #expect(Self.outcome(profiles, "\u{a0}nbsp\u{a0}") == ("OK", ""))
        #expect(Self.outcome(profiles, "nbsp") == ("java.io.IOException", "Profil neexistuje: nbsp"))
        #expect(try profiles.profileData("plain") == Data("{}".utf8))
    }

    @Test func unreadableProfileIsReportedAsMissing() throws {
        let (dir, profiles) = try Self.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let locked: URL = dir.appendingPathComponent("locked.json")
        try Data("{}".utf8).write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        #expect(Self.outcome(profiles, "locked") == ("java.io.IOException", "Profil neexistuje: locked"))
    }

    @Test func deleteOfAMissingProfileIsSilentAndTrimsLikeJava() throws {
        let (dir, profiles) = try Self.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        try profiles.delete("missing")
        try profiles.delete(" plain ")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("plain.json").path))
        try profiles.delete("nbsp")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\u{a0}nbsp\u{a0}.json").path))
    }
}
