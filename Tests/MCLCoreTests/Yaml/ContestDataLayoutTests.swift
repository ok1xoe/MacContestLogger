import Foundation
import Testing
@testable import MCLCore

/// Verifies that the `contest-data/` corpus got into the test bundle **with
/// its nesting preserved**.
///
/// This is not a formality. Measured on this repository: with the rule
/// `.process("Fixtures")` all 40 `contest-data/` files ended up flat
/// in `Contents/Resources/` and the `contests/`/`multipliers/` subdirectories
/// **vanished completely** from the bundle — without a single build warning. `ContestCatalog.fromDir` and `MultiplierSetRegistry.loadDir`, which walk the
/// directories, rely on that nesting. `Package.swift`
/// therefore uses `.copy("Fixtures/contest-data")` and this test guards that the
/// rule does not change back.
///
/// The counts are **not taken from a number in the assignment** — they are derived from the directory contents.
/// That the bundle lacks no file that is in the repository is cross-checked
/// by `JavaYamlParityTests`: the reference was made over the source directory, so
/// if a file does not get into the bundle, the key sets diverge.
@Suite struct ContestDataLayoutTests {

    /// Root of the copied corpus in the test bundle.
    static func contestDataRoot() throws -> URL {
        try #require(
            Bundle.module.url(forResource: "contest-data", withExtension: nil),
            "there is no contest-data directory in the bundle — check the .copy rule in Package.swift"
        )
    }

    /// Relative paths of all regular files under the root, with `/` and sorted.
    static func relativeFiles(under root: URL) throws -> [String] {
        let base = root.standardizedFileURL.path
        let enumerator = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]),
            "directory \(base) cannot be walked"
        )
        var out: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            out.append(String(path.dropFirst(base.count + 1)))
        }
        return out.sorted()
    }

    @Test func bundleCarriesContestsAndMultipliersSubdirectories() throws {
        let root = try Self.contestDataRoot()
        var isDirectory: ObjCBool = false

        for subdirectory in ["contests", "multipliers"] {
            let url = root.appendingPathComponent(subdirectory)
            #expect(
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                "\(subdirectory)/ is missing from the bundle — the rule in Package.swift flattened the tree"
            )
            #expect(isDirectory.boolValue, "\(subdirectory) is not a directory in the bundle")
        }
    }

    @Test func bothSubdirectoriesCanBeEnumeratedAndAreNotEmpty() throws {
        let root = try Self.contestDataRoot()
        let all = try Self.relativeFiles(under: root)

        let contests = all.filter { $0.hasPrefix("contests/") }
        let multipliers = all.filter { $0.hasPrefix("multipliers/") }
        let rootLevel = all.filter { !$0.contains("/") }

        // The counts are taken from the directory contents, not from a hard-coded number; the test
        // only insists that none of the three groups is empty and that together they
        // equal everything found in the corpus (i.e. that there is no
        // fourth, unexpected nesting level).
        #expect(!contests.isEmpty, "contests/ is empty in the bundle")
        #expect(!multipliers.isEmpty, "multipliers/ is empty in the bundle")
        #expect(!rootLevel.isEmpty, "there are no files in the root of contest-data/")
        let others: [String] = all.filter { relative in
            !relative.hasPrefix("contests/") && !relative.hasPrefix("multipliers/") && relative.contains("/")
        }
        #expect(
            contests.count + multipliers.count + rootLevel.count == all.count,
            Comment(rawValue: "the corpus has paths other than contests/, multipliers/ and the root: "
                              + others.joined(separator: ", "))
        )

        // Shape invariants that flattening the tree would break: contest definitions
        // are YAML only, multiplier sets have CSV next to YAML, and `bandplan.yaml`
        // belongs to the root (not to any subdirectory).
        let nonYaml: [String] = contests.filter { !$0.hasSuffix(".yaml") }
        #expect(nonYaml.isEmpty, Comment(rawValue: "contests/ contains something other than .yaml: " + nonYaml.joined(separator: ", ")))
        #expect(multipliers.contains { $0.hasSuffix(".yaml") }, "there are no .yaml sets in multipliers/")
        #expect(multipliers.contains { $0.hasSuffix(".csv") }, "there are no CSV files next to the sets in multipliers/")
        #expect(rootLevel.contains("bandplan.yaml"), "bandplan.yaml is not in the root of contest-data/")
    }

    @Test func everyFileInBundleIsReadable() throws {
        let root = try Self.contestDataRoot()
        let all = try Self.relativeFiles(under: root)

        for relative in all {
            let data = try? Data(contentsOf: root.appendingPathComponent(relative))
            #expect(data != nil, "\(relative): the file in the bundle cannot be read")
        }
    }
}
