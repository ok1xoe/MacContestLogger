import Foundation
import Testing
@testable import MCLCore

/// Released apps update their contest data from `contest-data/` on `main` (`DefinitionUpdater.defaultBase`), so the
/// published files must stay readable by the oldest published release (v0.9.0-rc1, which reads `index.txt`). Its
/// readers ignore unknown keys, but they reject a schema version above 1 and an enum value they do not know; the set
/// algorithms and providers of `index.txt` are guarded by `PublishedContestDataTests.rc1Problems`. A new DSL key is
/// therefore only allowed when the definition still means something without it: `scoring.parts` keeps `total` as
/// the fallback formula of the older versions.
@Suite struct ContestDataCompatibilityTests {

    /// The values v0.9.0-rc1 decodes (its `ContestDefinition` and `MultiplierSetDefinition` enums).
    static let releasedFieldTypes: Set<String> = [
        "RST", "RS", "SERIAL", "INTEGER", "TEXT", "LOCATOR", "CQ_ZONE", "ITU_ZONE", "DXCC", "PREFIX", "HQ", "NATIONAL",
        "STATE", "PROVINCE", "DISTRICT", "IOTA", "QTC",
    ]
    static let releasedFieldSources: Set<String> = [
        "MANUAL", "AUTO_RST", "AUTO_SERIAL", "FROM_STATION", "DERIVED", "ROVER_QTH",
    ]
    static let releasedScopes: Set<String> = ["PER_BAND", "PER_BAND_MODE", "PER_MODE", "ONCE"]
    static let releasedPointsModes: Set<String> = ["FIRST_MATCH", "SUM"]
    static let releasedSetKinds: Set<String> = ["FIXED", "ALGORITHM", "EXTERNAL_DATA"]
    static let releasedKeyTypes: Set<String> = ["INTEGER", "TEXT", "CALLSIGN_PREFIX"]

    private static func definitions() throws -> [(String, ContestDefinition)] {
        try PublishedContestDataTests.files("contests").map { name in
            (name, try ContestDefinitionLoader.loadFile(PublishedContestDataTests.root.appendingPathComponent(name)))
        }
    }

    @Test func definitionsUseOnlyValuesReleasedReadersKnow() throws {
        for (name, def) in try Self.definitions() {
            #expect(def.schemaVersion <= 1, "\(name): a released loader rejects schemaVersion \(def.schemaVersion)")
            let fields = (def.exchange?.sent ?? []) + (def.exchange?.received ?? [])
            for case let field? in fields {
                if let type = field.type?.rawValue {
                    #expect(Self.releasedFieldTypes.contains(type), "\(name): field type \(type)")
                }
                if let source = field.source?.rawValue {
                    #expect(Self.releasedFieldSources.contains(source), "\(name): field source \(source)")
                }
            }
            var scopes: [String] = (def.multipliers ?? []).compactMap { $0?.scope?.rawValue }
            scopes += (def.scoring?.bonuses ?? []).compactMap { $0?.scope?.rawValue }
            scopes += [def.dupe?.scope?.rawValue].compactMap { $0 }
            for scope in scopes {
                #expect(Self.releasedScopes.contains(scope), "\(name): scope \(scope)")
            }
            if let mode = def.scoring?.qsoPoints?.mode?.rawValue {
                #expect(Self.releasedPointsModes.contains(mode), "\(name): points mode \(mode)")
            }
        }
    }

    @Test func multiplierSetsUseOnlyValuesReleasedReadersKnow() throws {
        for name in try PublishedContestDataTests.files("multipliers") where name.hasSuffix(".yaml") {
            let set = try MultiplierSetLoader.loadFile(PublishedContestDataTests.root.appendingPathComponent(name))
            if let kind = set.kind?.rawValue {
                #expect(Self.releasedSetKinds.contains(kind), "\(name): kind \(kind)")
            }
            if let keyType = set.keyType?.rawValue {
                #expect(Self.releasedKeyTypes.contains(keyType), "\(name): keyType \(keyType)")
            }
        }
    }

    /// A definition with `scoring.parts` read the way a version without the key reads it: it must still pass the
    /// check and score QSOs of every part by its `total` formula.
    @Test func scoringPartsKeepAWorkingFallbackForOlderVersions() throws {
        let dxcc = try SessionFixture.dxcc()
        let registry = try MultiplierSetRegistry(dxcc: dxcc)
            .loadDir(PublishedContestDataTests.root.appendingPathComponent("multipliers"))
        for (name, def) in try Self.definitions() where !(def.scoring?.scoredParts.isEmpty ?? true) {
            var old = def
            old.scoring?.parts = nil
            #expect(ContestValidator.validate(old).errors.isEmpty, "\(name)")
            #expect(!JavaText.isBlank(old.scoring?.total ?? ""), "\(name): parts need a fallback total")
            let session = ContestSession(definition: old, dxcc: dxcc, registry: registry, myCall: "W2XYZ",
                                         mySection: "ENY")
            var raw = JavaLinkedMap<String>()
            for case let field? in def.exchange?.received ?? [] {
                raw.put(field.id, field.type == .RST ? "599" : "MAMID")
            }
            _ = try session.log(call: "W1AW", band: def.bands?.compactMap { $0 }.first ?? "20m",
                                mode: "CW", receivedRaw: raw, at: Date(timeIntervalSince1970: 1_795_867_500))
            #expect(try session.score().parts.isEmpty, "\(name)")
        }
    }
}
