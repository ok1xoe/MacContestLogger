import Foundation
import Testing
@testable import MCLCore

/// The repository-root `contest-data/` is what `DefinitionUpdater.defaultBase` serves to users. The fixture corpus is
/// the frozen subset the Java parity references were measured over: every fixture file is published byte-identical,
/// and the definitions and sets added after the port are checked here instead (the index lists every file, each
/// definition passes the definition editor's check against the published sets and scores a QSO without an engine
/// error). `index-v2.txt` lists every file; `index.txt` only what the released v0.9.0-rc1 can load (see
/// `rc1Incompatible`).
@Suite struct PublishedContestDataTests {

    @Test func rootContestDataMatchesFixtureCorpus() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let published = repoRoot.appendingPathComponent("contest-data")
        guard FileManager.default.fileExists(atPath: published.path) else { return }  // source tree not available
        let fixture = try ContestDataLayoutTests.contestDataRoot()

        let publishedFiles = try ContestDataLayoutTests.relativeFiles(under: published)
        let fixtureFiles = try ContestDataLayoutTests.relativeFiles(under: fixture)
        #expect(Set(fixtureFiles).isSubset(of: Set(publishedFiles)))
        // The indexes list the published files (more than the fixture's); the index tests below check them.
        for path in publishedFiles where fixtureFiles.contains(path) && !path.hasPrefix("index") {
            let a = try Data(contentsOf: published.appendingPathComponent(path))
            let b = try Data(contentsOf: fixture.appendingPathComponent(path))
            #expect(a == b, "\(path) differs between contest-data/ and the fixture corpus")
        }
    }

    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contest-data")
    }

    static func files(_ dir: String) throws -> [String] {
        let url = root.appendingPathComponent(dir)
        return try FileManager.default.contentsOfDirectory(atPath: url.path)
            .filter { !$0.hasPrefix(".") }.sorted().map { dir + "/" + $0 }
    }

    /// The files of the directory an index may list: the root `*.yaml`, `contests/*` and `multipliers/*`.
    static func presentFiles() throws -> [String] {
        let rootFiles: [String] = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".yaml") }
        return (rootFiles + (try files("contests")) + (try files("multipliers"))).sorted()
    }

    /// The entries of an index file, parsed like the updater does.
    static func indexEntries(_ name: String) throws -> [String] {
        let data = try Data(contentsOf: root.appendingPathComponent(name))
        return DefinitionUpdater.indexLines(String(decoding: data, as: UTF8.self))
    }

    /// The files `index.txt` leaves out because the released v0.9.0-rc1 cannot load them (it reads only
    /// `index.txt`). They are listed in `index-v2.txt`, which newer apps read first. Keep in sync with the comment at
    /// the top of `index.txt` and with `docs/definition-editor.md`.
    static let rc1Incompatible: Set<String> = [
        "multipliers/last_letters.yaml", "multipliers/worked_calls.yaml",
        "contests/ea-qrp-cw.yaml", "contests/ok-dx-rtty.yaml", "contests/ok1wc-memorial.yaml",
        "contests/russian-yl-om.yaml",
    ]

    /// Algorithms of `kind: ALGORITHM` sets the released v0.9.0-rc1 builds; any other fails its whole `loadDir`.
    static let rc1Algorithms: Set<String> = ["wpx"]
    /// Providers of `kind: EXTERNAL_DATA` sets the released v0.9.0-rc1 builds (`nil` = the default DXCC).
    static let rc1Providers: Set<String> = ["dxcc-json", "cty"]

    private static func checkWellFormed(_ name: String, _ listed: [String]) throws {
        #expect(Set(listed).count == listed.count, "\(name): no file listed twice")
        for path in listed {
            #expect(DefinitionUpdater.isSafe(path), "\(name): unsafe path \(path)")
            #expect(!path.contains(" "), "\(name): \(path)")
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                    "\(name): \(path) does not exist")
        }
    }

    /// `index-v2.txt` (read first by the app) lists every published file.
    @Test func indexV2ListsEveryFile() throws {
        let listed = try Self.indexEntries("index-v2.txt")
        try Self.checkWellFormed("index-v2.txt", listed)
        #expect(listed.sorted() == (try Self.presentFiles()))
    }

    /// `index.txt` (the only index v0.9.0-rc1 reads) lists every published file except the documented
    /// rc1-incompatible ones.
    @Test func indexListsEveryFileExceptRc1Incompatible() throws {
        let listed = try Self.indexEntries("index.txt")
        try Self.checkWellFormed("index.txt", listed)
        let present = try Self.presentFiles()
        #expect(Self.rc1Incompatible.isSubset(of: Set(present)), "rc1Incompatible names a file that is gone")
        #expect(listed.sorted() == present.filter { !Self.rc1Incompatible.contains($0) })
    }

    /// What v0.9.0-rc1 could not load from the files of an index: a multiplier set with an algorithm or provider it
    /// does not know (which would stop every set after it from loading), and a definition that fails the editor's
    /// check against the sets it could load (or references a set the index does not ship).
    static func rc1Problems(_ listed: [String]) throws -> [String] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rc1-index-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("multipliers"),
                                                withIntermediateDirectories: true)
        var problems: [String] = []
        for path in listed where path.hasPrefix("multipliers/") {
            if path.hasSuffix(".yaml") {
                let definition = try MultiplierSetLoader.loadFile(root.appendingPathComponent(path))
                switch definition.kind {
                case .ALGORITHM?:
                    let type = (definition.algorithm?.type ?? "").lowercased()
                    if !rc1Algorithms.contains(type) {
                        problems.append(path)
                        continue
                    }
                case .EXTERNAL_DATA?:
                    if let type = definition.provider?.type, !rc1Providers.contains(type.lowercased()) {
                        problems.append(path)
                        continue
                    }
                default:
                    break
                }
            }
            try FileManager.default.copyItem(at: root.appendingPathComponent(path),
                                             to: dir.appendingPathComponent(path))
        }
        // What the rc1-loadable sets of the index load to (no file may fail here either).
        _ = try MultiplierSetRegistry(dxcc: try SessionFixture.dxcc()).loadDir(dir.appendingPathComponent("multipliers"))
        let known = DefinitionEditing.knownSets(dir.appendingPathComponent("multipliers"))
        for path in listed where path.hasPrefix("contests/") {
            let url = root.appendingPathComponent(path)
            let text = try String(contentsOf: url, encoding: .utf8)
            let check = DefinitionEditing.check(text, fileId: url.deletingPathExtension().lastPathComponent,
                                                knownSets: known)
            if check.hasErrors { problems.append(path) }
        }
        return problems.sorted()
    }

    /// Guard: every file of `index.txt` must be loadable by v0.9.0-rc1. A set with a newer algorithm (or a
    /// definition using one) belongs only to `index-v2.txt`.
    @Test func indexIsLoadableByRc1() throws {
        #expect(try Self.rc1Problems(try Self.indexEntries("index.txt")) == [])
    }

    /// The guard can turn red: over the complete `index-v2.txt` it finds exactly the files `index.txt` leaves out.
    @Test func rc1GuardFindsTheIncompatibleFiles() throws {
        #expect(try Self.rc1Problems(try Self.indexEntries("index-v2.txt")) == Self.rc1Incompatible.sorted())
    }

    @Test func everyDefinitionPassesTheEditorCheck() throws {
        let known: [String] = DefinitionEditing.knownSets(Self.root.appendingPathComponent("multipliers"))
        let contests: URL = Self.root.appendingPathComponent("contests")
        for name in try Self.files("contests") {
            let url = Self.root.appendingPathComponent(name)
            let id = url.deletingPathExtension().lastPathComponent
            let text = try String(contentsOf: url, encoding: .utf8)
            let check = DefinitionEditing.check(text, fileId: id, knownSets: known)
            let errors = check.issues.filter { $0.severity == .error }.map(\.message)
            #expect(!check.hasErrors, "\(id): \(errors)")
        }
        let catalog = try ContestCatalog.fromDir(contests)
        #expect(catalog.count == (try Self.files("contests")).count)
    }

    @Test func everyDefinitionScoresAQso() throws {
        let dxcc = try SessionFixture.dxcc()
        let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(Self.root.appendingPathComponent("multipliers"))
        for definition in try ContestCatalog.fromDir(Self.root.appendingPathComponent("contests")) {
            let session = ContestSession(definition: definition, dxcc: dxcc, registry: registry, myCall: "OK1XOE",
                                         myGrid: "JO70")
            let band: String = definition.bands?.compactMap { $0 }.first ?? "20m"
            let mode: String = definition.modes?.compactMap { $0 }.first ?? "CW"
            var raw = JavaLinkedMap<String>()
            for case let field? in definition.exchange?.received ?? [] {
                raw.put(field.id, Self.sample(field))
            }
            for call in ["DL1ABC", "W1AW", "OK1ABC"] {
                do {
                    _ = try session.log(call: call, band: band, mode: mode, receivedRaw: raw,
                                        at: Date(timeIntervalSince1970: 1_795_867_500))
                } catch {
                    Issue.record("\(definition.id ?? "?") \(call): \(error)")
                }
            }
            do {
                _ = try session.score()
            } catch {
                Issue.record("\(definition.id ?? "?") score: \(error)")
            }
        }
    }

    private static func sample(_ field: ContestDefinition.ExchangeField) -> String {
        switch field.type {
        case .RST: return "599"
        case .RS: return "59"
        case .SERIAL, .INTEGER: return "12"
        case .LOCATOR: return "JO62"
        case .CQ_ZONE: return "14"
        case .ITU_ZONE: return "28"
        default: return "AB"
        }
    }

    /// OK DX RTTY rule 8a: outside OK/OL every OK/OL station is a multiplier on each band; OK stations count DXCC only.
    @Test func okDxRttyCountsOkStations() throws {
        let dxcc = try SessionFixture.dxcc()
        let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(Self.root.appendingPathComponent("multipliers"))
        let definition = try ContestDefinitionLoader.loadFile(
            Self.root.appendingPathComponent("contests/ok-dx-rtty.yaml"))
        func score(_ myCall: String) throws -> ScoreState {
            let session = ContestSession(definition: definition, dxcc: dxcc, registry: registry, myCall: myCall)
            for (call, band) in [("OK1ABC", "20m"), ("OK1XYZ", "20m"), ("OK1ABC", "40m"), ("W1AW", "20m")] {
                _ = try session.log(call: call, band: band, mode: "RTTY",
                                    receivedRaw: SessionFixture.raw(("rst", "599"), ("zone", "15")),
                                    at: Date(timeIntervalSince1970: 1_795_867_500))
            }
            return try session.score()
        }
        // DL: OK and US per band (3) + OK1ABC, OK1XYZ on 20 m and OK1ABC on 40 m (3).
        #expect(try score("DL1ABC").multTotal == 6)
        // OK: DXCC only (OK on 20 and 40 m, US on 20 m).
        #expect(try score("OK1XOE").multTotal == 3)
    }
}
