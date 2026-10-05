import Foundation
import Testing
@testable import MCLCore

/// `ContestEnvironment.load` against the Kotlin `AppState.buildContestController` (v1.1.1) over the
/// `contest-data` fixture, `dxcc-test.json` and `scorecheck-cty-mini.dat` copied into a temporary directory.
@Suite struct ContestEnvironmentTests {

    /// A temporary directory removed by `cleanup()`.
    final class Scratch {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mcl-env-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        func dir(_ name: String) throws -> URL {
            let dir = url.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext))
    }

    /// A DXCC directory: `dxcc.json` (= `dxcc-test.json`) and optionally `cty.dat` (= `scorecheck-cty-mini.dat`).
    static func dxccDir(_ scratch: Scratch, json: Bool = true, cty: Bool = false) throws -> URL {
        let dir = try scratch.dir("dxcc-json")
        if json {
            try FileManager.default.copyItem(at: fixture("dxcc-test", "json"), to: dir.appendingPathComponent("dxcc.json"))
        }
        if cty {
            try FileManager.default.copyItem(at: fixture("scorecheck-cty-mini", "dat"),
                                             to: dir.appendingPathComponent("cty.dat"))
        }
        return dir
    }

    static func contestData() throws -> URL {
        try SessionFixture.contestData()
    }

    @Test func loadsStructuredDataDirectory() throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        let dxcc = try Self.dxccDir(scratch)
        let root = try Self.contestData()
        let env = ContestEnvironment.load(dataRoot: root.path, dxccDir: dxcc.path, fallbackDataRoot: "/nonexistent")
        #expect(env.engineAvailable)
        #expect(env.problems.isEmpty)
        #expect(env.dataRoot.path == root.path)
        #expect(env.contestsDir.lastPathComponent == "contests")
        #expect(env.catalog.count == 22)
        #expect(env.registry?.contains("cq_zones") == true)
        #expect(env.dxcc is DxccSpecialCases)
        #expect(env.dxcc?.resolve("OK1ABC")?.entityCode == 503)

        let runtime = ContestRuntime(environment: env, myCall: { "OK1XOE" })
        #expect(runtime.available.count == 22)
        #expect(runtime.activate(id: "cq-ww-cw") == nil)
    }

    @Test func blankConfiguredRootFallsBack() throws {
        let root = try Self.contestData()
        for configured in [nil, "", "   ", "\u{00A0}", "\u{3000}\t"] as [String?] {
            let url = ContestEnvironment.dataRoot(configured: configured, fallback: root.path)
            #expect(url.path == root.path, "configured \(String(describing: configured))")
        }
        #expect(ContestEnvironment.dataRoot(configured: "/x/y", fallback: root.path).path == "/x/y")
        // Kotlin `isNotBlank` keeps a control character (not whitespace): the path is used as is.
        #expect(ContestEnvironment.dataRoot(configured: "\u{0001}", fallback: root.path).path != root.path)

        let env = ContestEnvironment.load(dataRoot: " ", dxccDir: nil, fallbackDataRoot: root.path)
        #expect(env.catalog.count == 22)
    }

    @Test func flatDirectoryWithoutContestsSubdirectory() throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        let flat = try scratch.dir("flat")
        let source = try Self.contestData().appendingPathComponent("contests")
        try FileManager.default.copyItem(at: source.appendingPathComponent("cq-ww-cw.yaml"),
                                         to: flat.appendingPathComponent("cq-ww-cw.yaml"))
        let dxcc = try Self.dxccDir(scratch)
        let env = ContestEnvironment.load(dataRoot: flat.path, dxccDir: dxcc.path, fallbackDataRoot: "/nonexistent")
        #expect(env.contestsDir.path == flat.path)
        #expect(env.catalog.map(\.id) == ["cq-ww-cw"])
        #expect(env.registry == nil, "no multipliers/ → no registry")
        #expect(!env.engineAvailable)
        #expect(env.problems.map(\.czech) == ["Multiplikátorové sady nejsou načtené."])
    }

    @Test func missingDxccDisablesTheEngine() throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        let root = try Self.contestData()
        let empty = try scratch.dir("empty-dxcc")
        for dxccDir in [nil, empty.path, scratch.url.appendingPathComponent("missing").path] as [String?] {
            let env = ContestEnvironment.load(dataRoot: root.path, dxccDir: dxccDir, fallbackDataRoot: "/nonexistent")
            #expect(env.dxcc == nil)
            #expect(env.registry == nil, "the registry needs DXCC")
            #expect(env.catalog.count == 22, "definitions load without DXCC")
            #expect(env.problems.map(\.czech) == ["Contest engine není dostupný."])
        }
    }

    @Test func missingDataRoot() throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        let dxcc = try Self.dxccDir(scratch)
        let missing = scratch.url.appendingPathComponent("no-data").path
        let env = ContestEnvironment.load(dataRoot: missing, dxccDir: dxcc.path, fallbackDataRoot: "/nonexistent")
        #expect(env.catalog.isEmpty)
        #expect(env.contestsDir.path == missing)
        #expect(env.registry == nil)
        #expect(env.dxcc != nil)
        #expect(env.problems.map(\.czech) == ["Multiplikátorové sady nejsou načtené."])
    }

    @Test func ctyDatWinsWithCodesFromDxccJson() throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        let dir = try Self.dxccDir(scratch, json: true, cty: true)
        let dxcc = try #require(ContestEnvironment.loadDxcc(dir))
        let turkey = try #require(dxcc.resolve("TA1ABC"), "only cty.dat knows Turkey")
        #expect(turkey.name == "Turkey")
        #expect(dxcc.resolve("OK1ABC")?.adifDxcc == 503, "DXCC number from dxcc.json")
    }

    @Test func ctyDatWithoutDxccJsonHasNoCodes() throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        let dir = try Self.dxccDir(scratch, json: false, cty: true)
        let dxcc = try #require(ContestEnvironment.loadDxcc(dir))
        #expect(dxcc.resolve("TA1ABC") != nil)
        #expect(dxcc.resolve("OK1ABC")?.adifDxcc == nil)
    }

    @Test func unreadableCtyDatFallsBackToDxccJson() throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        let dir = try Self.dxccDir(scratch)
        // A directory named cty.dat is "readable" for Files.isReadable, but reading it fails.
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("cty.dat"),
                                                withIntermediateDirectories: true)
        let dxcc = try #require(ContestEnvironment.loadDxcc(dir))
        #expect(dxcc.resolve("TA1ABC") == nil, "dxcc-test.json has no Turkey")
        #expect(dxcc.resolve("OK1ABC")?.entityCode == 503)
    }

    @Test func brokenSetMeansNoRegistry() throws {
        let scratch = try Scratch()
        defer { scratch.cleanup() }
        let root = try scratch.dir("data")
        let multipliers = try scratch.dir("data/multipliers")
        try Data("id: [unclosed".utf8).write(to: multipliers.appendingPathComponent("broken.yaml"))
        let dxcc = try Self.dxccDir(scratch)
        let env = ContestEnvironment.load(dataRoot: root.path, dxccDir: dxcc.path, fallbackDataRoot: "/nonexistent")
        #expect(env.dxcc != nil)
        #expect(env.registry == nil)
        #expect(env.problems.map(\.czech) == ["Multiplikátorové sady nejsou načtené."])
    }
}
