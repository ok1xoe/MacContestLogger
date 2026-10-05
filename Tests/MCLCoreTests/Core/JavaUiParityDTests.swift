import Foundation
import Testing
@testable import MCLCore

/// Java parity: the Settings window against the real Kotlin code of v1.1.1: `ConfigurerDraft(config).applyTo(target)`
/// after seeded edits of every draft field and row, mostly onto a different configuration (`cfg.APPLY`), the eight
/// change predicates `commitConfigurer` evaluates over the same cases (`cfg.DIFFERS`), the private `buildTabSpecs`
/// of `app/App.kt` over menu variants and `ConfigurerTab.byKey` (`cfg.TABS`), and the row helpers `numStr`,
/// `toSegment`, `toChannel`, `toEntry`, `overlaps`, `gridLatLon` (`cfg.ROWS`). The reference
/// `Fixtures/ui-d-java.json.gz` comes from a maintainer-only probe (fixture `d`, instructions kept with the probe).
///
/// Input rows are taken from the reference, outputs are computed by Swift (`UiParityDSections`). A change of inputs =
/// "REGENERATE REFERENCE", a different output = "MISMATCH". The gate prints nothing; each item runs on its own
/// thread, not in the shared pool.
@Suite struct JavaUiParityDTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Rows per item in the Java reference — against a broken generator (an empty fuzzer, a missing case kind),
    /// where inputs taken from the reference would still match.
    static let pinned: [String: Int] = [
        "cfg.APPLY": 23_620, "cfg.DIFFERS": 1_244, "cfg.TABS": 4_164, "cfg.ROWS": 4_394,
    ]

    @Test func settingsMatchKotlin() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("ui-d-java")
            #expect(reference.map(\.relative) == UiParityDSections.names, "set of reference items")
            for entry in reference {
                #expect(entry.lines.count == Self.pinned[entry.relative],
                        "\(entry.relative): number of reference rows (pinned)")
            }
            let mine: [UiParityDSections.Entry] = try await UiParityDSections.replayAll(reference)
            let report = JavaNetParityFixture.differences(reference: reference, mine: mine, regenerate: Self.regenerate,
                                                          label: "settings")
            #expect(report == nil, Comment(rawValue: report ?? ""))
        }
    }

    /// The edits of `cfg.APPLY` name exactly the draft fields Swift knows (so no Kotlin field goes untested and no
    /// Swift table entry is dead), use every edit kind, and every predicate bit of `cfg.DIFFERS` takes both values.
    @Test func referenceCoversTheDraft() throws {
        let reference = try JavaIoParityFixture.reference("ui-d-java")
        let apply = try #require(reference.first { $0.relative == "cfg.APPLY" })
        var named: [String: Set<String>] = [:]
        for line in apply.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count > 5, fields[1] == "in", fields[0].hasPrefix("a/") else { continue }
            var index = 5
            while index + 4 < fields.count {
                named[fields[index], default: []].insert(fields[index + 1])
                index += 5
            }
        }
        typealias D = UiParityDSections
        #expect(named["S"] == Set(D.textFields.keys))
        #expect(named["B"] == Set(D.boolFields.keys))
        #expect(named["I"] == Set(D.intFields.keys))
        #expect(named["E"] == Set(D.enumFields.keys))
        #expect(named["RS"] == Set(D.functionKeyLists.keys).union(["dxFavorites", "antennas", "transverters"]))
        #expect(named["LA"] == Set(D.textLists.keys))
        #expect(Set(named.keys) == ["S", "B", "I", "E", "RA", "RR", "RB", "RS", "LA", "LR", "LS", "KP", "KR"])

        let differs = try #require(reference.first { $0.relative == "cfg.DIFFERS" })
        var seen = [Set<Character>](repeating: [], count: 8)
        for line in differs.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count == 3, fields[1] == "out", fields[0].hasPrefix("d/"), fields[2].count == 8 else { continue }
            for (bit, value) in fields[2].enumerated() {
                seen[bit].insert(value)
            }
        }
        #expect(seen.allSatisfy { $0 == ["0", "1"] }, "every predicate is both true and false")
    }
}
