import Foundation
import Testing
@testable import MCLCore

/// Java parity: import, merge, the exports, configuration profiles and printing, against the real Kotlin code of
/// v1.1.1: `AppState.importQsos` and `mergeLog` over an in-memory logbook (`imp.READ`), `AppState.exportEdi`,
/// `exportOther` and `exportAdif` (`exp.FILES`, the files by name, size and SHA-256), `ConfigProfiles.loadInto`,
/// `isValidName` and `list` (`prof.MERGE`) and `LogPrinter.print(Graphics, PageFormat, i)` through a recording
/// `Graphics2D` (`print.PAGE`). The reference `Fixtures/ui-c-java.json.gz` comes from a maintainer-only probe (fixture
/// `c`, instructions kept with the probe).
///
/// Input rows are taken from the reference (except `defs` and the `file:` contents of `imp.READ`, which Swift builds
/// from its own files), outputs are computed by Swift (`UiParityCSections`) with the core steps the app model runs.
/// A change of inputs = "REGENERATE REFERENCE", a different output = "MISMATCH". The gate prints nothing; each item
/// runs on its own thread, not in the shared pool.
@Suite struct JavaUiParityCTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Rows per item in the Java reference — against a broken generator (an empty fuzzer, a missing case kind),
    /// where inputs taken from the reference would still match.
    static let pinned: [String: Int] = [
        "imp.READ": 2_392, "exp.FILES": 1_524, "prof.MERGE": 1_500, "print.PAGE": 3_542,
    ]

    @Test func importExportProfilesAndPrintingMatchKotlin() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("ui-c-java")
            #expect(reference.map(\.relative) == UiParityCSections.names, "set of reference items")
            for entry in reference {
                #expect(entry.lines.count == Self.pinned[entry.relative],
                        "\(entry.relative): number of reference rows (pinned)")
            }
            let mine: [UiParityCSections.Entry] = try await UiParityCSections.replayAll(reference)
            let report = JavaNetParityFixture.differences(reference: reference, mine: mine, regenerate: Self.regenerate,
                                                          label: "import, export, profiles, printing")
            #expect(report == nil, Comment(rawValue: report ?? ""))
        }
    }

    /// The reference covers the import outcomes (imported, unreadable, a Kotlin crash), both merge outcomes and every
    /// merge source kind (ADIF, Cabrillo, a database).
    @Test func referenceCoversTheCaseKinds() throws {
        let reference = try JavaIoParityFixture.reference("ui-c-java")
        let imports = try #require(reference.first { $0.relative == "imp.READ" })
        var statuses: Set<String> = []
        var kinds: Set<String> = []
        for line in imports.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count > 2 else { continue }
            if fields[1] == "out", !fields[0].contains("/q/"), let status = JavaCoreParityFixture.text(fields[2]) {
                statuses.insert(String(status.prefix(8)))
            }
            if fields[1] == "in", fields[0].hasPrefix("m/"), let kind = fields.first(where: {
                $0.hasPrefix("db") || $0.hasPrefix("adif") || $0.hasPrefix("cabrillo")
            }) {
                kinds.insert(String(kind.prefix(2)))
            }
        }
        #expect(statuses.isSuperset(of: ["Importov", "Nelze p\u{0159}", "THROW St", "Slou\u{010D}eno", "Slou\u{010D}en\u{00ED}"]))
        #expect(kinds == ["db", "ad", "ca"])
    }
}
