import Foundation
import Testing
@testable import MCLCore

/// The repository-root `contest-data/` is what `DefinitionUpdater.defaultBase` serves to users. The fixture corpus is
/// the frozen subset the Java parity references were measured over: every fixture file is published byte-identical,
/// and the definitions and sets added after the port are checked here instead (the index lists every file, each
/// definition passes the definition editor's check against the published sets and scores a QSO without an engine
/// error).
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
        // The index lists the published files (more than the fixture's); `indexListsEveryFile` checks it.
        for path in publishedFiles where fixtureFiles.contains(path) && path != "index.txt" {
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

    @Test func indexListsEveryFile() throws {
        let text = try String(contentsOf: Self.root.appendingPathComponent("index.txt"), encoding: .utf8)
        let listed: [String] = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let rootFiles: [String] = try FileManager.default.contentsOfDirectory(atPath: Self.root.path)
            .filter { $0.hasSuffix(".yaml") }
        let present: [String] = (rootFiles + (try Self.files("contests")) + (try Self.files("multipliers"))).sorted()
        #expect(listed.sorted() == present)
        #expect(Set(listed).count == listed.count, "no file listed twice")
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
