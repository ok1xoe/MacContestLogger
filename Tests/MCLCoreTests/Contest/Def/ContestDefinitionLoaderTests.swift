import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `ContestDefinitionLoaderTest` (7 tests) and the file part of
/// the loader (probe `ProbeCat`, a maintainer-only probe).
@Suite struct ContestDefinitionLoaderTests {

    static func contestsDir() throws -> URL {
        let root = try #require(Bundle.module.url(forResource: "contest-data", withExtension: nil))
        return root.appendingPathComponent("contests")
    }

    static func bundled(_ name: String) throws -> ContestDefinition {
        try ContestDefinitionLoader.loadFile(contestsDir().appendingPathComponent(name))
    }

    // MARK: - Java ContestDefinitionLoaderTest

    @Test func loadsCqWw() throws {
        let definition = try Self.bundled("cq-ww-cw.yaml")
        #expect(definition.id == "cq-ww-cw")
        #expect(definition.bands?.count == 6)
        #expect(definition.exchange?.received?.count == 2)
        #expect(definition.multipliers?.count == 2)
        #expect(definition.scoring?.total == "qsoPoints * multTotal")
        #expect(definition.scoring?.qsoPoints?.mode == .FIRST_MATCH)
        #expect(definition.scoring?.qsoPoints?.defaultValue == 0)
        #expect(definition.scoring?.qsoPoints?.rules?.count == 4)
        // first multiplier: zones from the zone, countries from the callsign
        #expect(definition.multipliers?.first??.id == "zones")
        #expect(definition.multipliers?.first??.from == "zone")
        #expect(definition.multipliers?[1]?.from == "callsign")
    }

    @Test func loadsWpxWithSerialAndPrefixMult() throws {
        let definition = try Self.bundled("cq-wpx-cw.yaml")
        #expect(definition.multipliers?.count == 1)
        #expect(definition.multipliers?.first??.set == "wpx_prefixes")
        #expect(definition.scoring?.qsoPoints?.defaultValue == 1)
    }

    @Test func loads160WithConditionalExchange() throws {
        let definition = try Self.bundled("cq-160-cw.yaml")
        #expect(definition.bands?.count == 1)
        #expect(definition.stationClasses?.count == 2)
        #expect(definition.exchange?.received?.count == 3)
        let state = try #require(definition.exchange?.received?.compactMap { $0 }.first { $0.id == "state" })
        #expect(state.appliesWhen != nil)
        #expect(state.appliesWhen?.workedClass == "wve")
    }

    @Test func loadsOkOmConditionalExchange() throws {
        let definition = try Self.bundled("ok-om-dx-cw.yaml")
        #expect(definition.stationClasses?.count == 2)
        #expect(definition.exchange?.received?.count == 3)
    }

    /// The count **22 is hard-coded**, as in Java: the test thus guards that nothing was
    /// added to or removed from the fixtures `contest-data/contests/` (an added or
    /// deleted file breaks it and forces the fixtures to be consciously reconciled with the Java
    /// repo). Computing it from the directory contents would cancel the check.
    @Test func catalogLoadsAllBundled() throws {
        let bundled = try ContestCatalog.fromDir(Self.contestsDir())
        #expect(bundled.count == 22)
        for id in ["iaru-hf", "dx", "ok-om-dx-cw", "cq-ww-ssb", "cq-ww-rtty", "cq-wpx-ssb", "cq-wpx-rtty",
                   "cq-160-ssb", "ww-digi"] {
            #expect(bundled.contains { $0.id == id }, "\(id)")
        }
    }

    @Test func loadsOperatingRulesForTimers() throws {
        // Operating rules (off-time and band changes) for the timers of the Info window.
        let yaml = """
            schemaVersion: 1
            id: "test-operating"
            metadata:
              name: "Test"
            bands: ["20m"]
            modes: ["CW"]
            exchange:
              received:
              - id: "rst"
                type: "RST"
                required: true
            scoring:
              qsoPoints:
                mode: "FIRST_MATCH"
                default: 1
              total: "qsoPoints"
            operating:
              offTime:
                minimumMinutes: 30
                requiredMinutes: 180
              bandChange:
                minimumMinutes: 10
                perHour: 8

            """
        let definition = try ContestDefinitionLoader.load(Data(yaml.utf8))
        #expect(definition.operating?.offTime?.minimumMinutes == 30)
        #expect(definition.operating?.offTime?.requiredMinutes == 180)
        #expect(definition.operating?.bandChange?.minimumMinutes == 10)
        #expect(definition.operating?.bandChange?.perHour == 8)
    }

    /// The `operating` block is optional and a definition without it stays valid
    /// (the Java test also calls `ContestValidator().validate(d).isValid()`).
    @Test func definitionsWithoutOperatingRulesStayValid() throws {
        let definition = try Self.bundled("iaru-hf.yaml")
        #expect(definition.operating == nil)
        let report = ContestValidator.validate(definition)
        #expect(report.isValid, "iaru-hf has errors:\n\(report)")
    }

    // MARK: - files

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContestDefinitionLoaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Open error → "Nelze načíst definici: <path>" (Java `loadFile`),
    /// the path as it was passed — a relative one stays relative.
    @Test func missingFileFailsToOpen() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("missing.yaml")
        #expect(throws: ContestDefinitionError.failure("Nelze načíst definici: " + url.path)) {
            try ContestDefinitionLoader.loadFile(url)
        }
        let relative = MultiplierSetRegistryLoadDirTests.relativePath(to: url)
        #expect(throws: ContestDefinitionError.failure("Nelze načíst definici: " + relative)) {
            try ContestDefinitionLoader.loadFile(URL(fileURLWithPath: relative))
        }
    }

    /// The directory `d.yaml` opens in Java and only the read inside Jackson fails →
    /// "Nelze načíst definici závodu: java.io.IOException: Is a directory".
    @Test func directoryFailsWhileReading() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("d.yaml")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        #expect(throws: ContestDefinitionError.failure("Nelze načíst definici závodu: Is a directory")) {
            try ContestDefinitionLoader.loadFile(sub)
        }
    }

    /// Invalid UTF-8: Java `CharConversionException` at 1:1 (within the first ~1 kB).
    @Test func invalidUtf8IsDefinitionError() {
        do {
            _ = try ContestDefinitionLoader.load(Data(Array("id: bad".utf8) + [0xFF] + Array("\n".utf8)))
            Issue.record("invalid UTF-8 should have failed")
        } catch {
            guard case .invalidDefinition(let yaml) = error else {
                Issue.record("expected .invalidDefinition, got \(error)")
                return
            }
            #expect(yaml.line == 1 && yaml.column == 1)
        }
    }
}
