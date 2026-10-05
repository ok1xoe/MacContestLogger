import Foundation
import Testing
@testable import MCLCore

/// `ContestDataPaths` from the Kotlin source of v1.1.1: `AppState.contestDataRoot()` (AS:3711-3714),
/// `DefinitionEditorWindow` (DE:54 `contestsDir`, DE:138-141 the QSO party template),
/// `AppState.updateCallHistoryFromLog` (AS:219-220, AS:226-229).
@Suite struct ContestDataPathsTests {

    static let fallback = URL(fileURLWithPath: "/data/contest-data")

    /// `config.contestDataDir?.takeIf { it.isNotBlank() } ?: default` — not trimmed, Kotlin blank (also U+00A0).
    @Test func rootIsTheConfiguredDirectoryUnlessBlank() {
        #expect(ContestDataPaths.root(contestDataDir: nil, default: Self.fallback) == Self.fallback)
        #expect(ContestDataPaths.root(contestDataDir: "", default: Self.fallback) == Self.fallback)
        #expect(ContestDataPaths.root(contestDataDir: " \t", default: Self.fallback) == Self.fallback)
        #expect(ContestDataPaths.root(contestDataDir: "\u{00A0}", default: Self.fallback) == Self.fallback)
        #expect(ContestDataPaths.root(contestDataDir: "/x/defs", default: Self.fallback).path == "/x/defs")
        #expect(ContestDataPaths.root(contestDataDir: " /x/defs", default: Self.fallback).path.hasSuffix(" /x/defs"))
    }

    /// `root.resolve("contests").let { if (isDirectory(it) || !isDirectory(root)) it else root }`.
    @Test func contestsDirPrefersContestsAndFallsBackToAnExistingRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contests = root.appendingPathComponent("contests")
        // The root does not exist: `contests/` (where a new definition would be saved).
        #expect(ContestDataPaths.contestsDir(root: root).path == contests.path)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // The root exists without `contests/`: definitions directly in the root.
        #expect(ContestDataPaths.contestsDir(root: root).path == root.path)
        try FileManager.default.createDirectory(at: contests, withIntermediateDirectories: true)
        #expect(ContestDataPaths.contestsDir(root: root).path == contests.path)
        // `contests` as a file is not a directory: back to the root.
        try FileManager.default.removeItem(at: contests)
        try Data().write(to: contests)
        #expect(ContestDataPaths.contestsDir(root: root).path == root.path)
    }

    @Test func contestsDirUsesTheInjectedCheck() {
        let root = URL(fileURLWithPath: "/defs")
        let contests = root.appendingPathComponent("contests")
        #expect(ContestDataPaths.contestsDir(root: root) { _ in false } == contests)
        #expect(ContestDataPaths.contestsDir(root: root) { $0 == root } == root)
        #expect(ContestDataPaths.contestsDir(root: root) { _ in true } == contests)
    }

    /// `config.callHistoryFile.trim()`; blank → `<data>/CALLHISTORY.txt`, saved into the configuration afterwards.
    @Test func callHistoryTargetFallsBackToTheDataDirectory() {
        let data = URL(fileURLWithPath: "/data")
        let blank = ContestDataPaths.callHistoryTarget(configured: "  ", dataDir: data)
        #expect(blank.url.path == "/data/CALLHISTORY.txt")
        #expect(blank.persist)
        #expect(ContestDataPaths.callHistoryTarget(configured: "", dataDir: data).persist)
        let configured = ContestDataPaths.callHistoryTarget(configured: " /x/CH.txt\t", dataDir: data)
        #expect(configured.url.path == "/x/CH.txt")
        #expect(!configured.persist)
    }

    /// `i = id.trim()`; `qsoPartyTemplate(i, i.uppercase(), i.replace('-', '_') + "_counties")`.
    @Test func qsoPartyArgumentsFollowTheEditor() {
        let party = ContestDataPaths.qsoPartyArguments(id: "  oh-qp-2 ")
        #expect(party.id == "oh-qp-2")
        #expect(party.name == "OH-QP-2")
        #expect(party.countySet == "oh_qp_2_counties")
        // Kotlin `uppercase()` is the full mapping (`ß` → `SS`).
        #expect(ContestDataPaths.qsoPartyArguments(id: "straße").name == "STRASSE")
    }
}
