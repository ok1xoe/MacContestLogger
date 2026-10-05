import Foundation
import Testing
@testable import MCLCore

/// the Java parity suite in CI: the Swift `ScoreCheck` (via `ScoreCheckReport`, i.e. the same core as
/// `mcl-scorecheck`) over an anonymised corpus sample (424 logs from 10 sets) against the committed
/// Java reference `scorecheck-reference/scorecheck-sample-reference-<cty|json>.tsv`
/// (maintainer-only probe).
///
/// The logs themselves are not distributed with the sources (third-party data): they are read from
/// `ScoreCheckSampleCorpus.directory` (`MCL_SCORECHECK_SAMPLE_DIR`, default
/// `~/cq_deniky/scorecheck-sample`) and the comparison is skipped when it is absent (CI).
/// The reference completeness checks run always. Rows are paired by `key` (SHA-256 of the
/// log), so a different corpus fails loudly ("missing in Swift" / "missing in the reference").
///
/// - Both DXCC modes: `cty` over the pinned `scorecheck-reference/cty/cty.dat`, `json` over
///   `scorecheck-reference/dxcc-json/dxcc.json` (the snapshot from which the Java reference was made).
/// - Rows are paired by `key` (SHA-256 of the content) — `file` repeats across sets; keys
///   must be unique on both sides.
/// - All data columns (`file` … `error`) are compared with tolerance 0 and the header rows
///   `format`, `columns`, `dxcc-source`, `cty.dat-sha256`/`dxcc.json-sha256`,
///   `contest-data-sha256`, `logs`.
/// - Mismatch listing: `set/file key: column java=… swift=…`, at most `maxReported` rows.
///
/// Falsifiability (injected defects, measured): replaying QSOs sorted
/// by time instead of file order, skipping a bad QSO instead of discarding the log and tolerant
/// UTF-8 decoding — each gives mismatches.
@Suite struct ScoreCheckParityTests {

    static let maxReported = 40
    static let dataColumns = ScoreCheckReport.columns.split(separator: " ").map(String.init)

    /// Header rows that describe the inputs and format (not the implementation) — must match.
    static func comparedHeaderKeys(_ mode: ScoreCheckReport.DxccMode) -> [String] {
        ["format", "columns", "dxcc-source", mode == .cty ? "cty.dat-sha256" : "dxcc.json-sha256",
         "contest-data-sha256", "logs"]
    }

    struct Table: Sendable {
        var header: [String: String] = [:]
        /// key → (set/file, columns `key` … `error`)
        var rows: [String: (where: String, cols: [String])] = [:]
        var duplicateKeys: [String] = []
        var order: [String] = []
    }

    /// Header `# key: value` → dictionary.
    static func parseHeader(_ lines: [String]) -> [String: String] {
        var header: [String: String] = [:]
        for line in lines where line.hasPrefix("# ") {
            let body = line.dropFirst(2)
            guard let sep = body.range(of: ": ") else { continue }
            header[String(body[body.startIndex..<sep.lowerBound])] = String(body[sep.upperBound...])
        }
        return header
    }

    /// Data rows → a table by key; `places[i]` describes the i-th row (`set/file`).
    static func table(header: [String], rows: [String], places: [String]) -> Table {
        var t = Table()
        t.header = parseHeader(header)
        for (i, row) in rows.enumerated() {
            let cols = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let key = cols[0]
            if t.rows[key] != nil { t.duplicateKeys.append(key) }
            t.rows[key] = (i < places.count ? places[i] : cols.count > 1 ? cols[1] : "?", cols)
            t.order.append(key)
        }
        return t
    }

    /// The reference as a table. A Java row carries only the file name; the set is added by the map
    /// key → `set/file` from the Swift side (the key is the content, the set cannot be told from it).
    static func reference(_ mode: ScoreCheckReport.DxccMode) throws -> Table {
        let ref = try #require(Bundle.module.url(forResource: "scorecheck-reference", withExtension: nil))
        let url = ref.appendingPathComponent("scorecheck-sample-reference-\(mode.rawValue).tsv")
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.isEmpty }
        let header = lines.filter { $0.hasPrefix("#") }
        let rows = lines.filter { !$0.hasPrefix("#") }
        return table(header: header, rows: rows, places: [])
    }

    /// Comparison of tables; returns all mismatches as lines of text (empty = match).
    static func compare(java: Table, swift: Table, headerKeys: [String]) -> [String] {
        var out: [String] = []
        for key in java.duplicateKeys { out.append("duplicate key in the reference: \(key)") }
        for key in swift.duplicateKeys { out.append("duplicate key in Swift: \(key)") }
        for name in headerKeys where java.header[name] != swift.header[name] {
            out.append("header \(name): java=\(java.header[name] ?? "∅") swift=\(swift.header[name] ?? "∅")")
        }
        for key in java.order where swift.rows[key] == nil {
            out.append("\(java.rows[key]?.where ?? "?") \(key): missing in Swift")
        }
        for key in swift.order {
            guard let s = swift.rows[key] else { continue }
            guard let j = java.rows[key] else {
                out.append("\(s.where) \(key): missing in the reference")
                continue
            }
            let width = max(j.cols.count, s.cols.count)
            for c in 1..<width {
                let jv = c < j.cols.count ? j.cols[c] : "∅"
                let sv = c < s.cols.count ? s.cols[c] : "∅"
                if jv != sv {
                    let name = c < dataColumns.count ? dataColumns[c] : "#\(c)"
                    out.append("\(s.where) \(key): \(name) java=\(jv) swift=\(sv)")
                }
            }
        }
        return out
    }

    static func sampleDir() -> URL {
        ScoreCheckSampleCorpus.directory
    }

    static func dxccFile(_ mode: ScoreCheckReport.DxccMode) throws -> URL {
        let ref = try #require(Bundle.module.url(forResource: "scorecheck-reference", withExtension: nil))
        switch mode {
        case .cty: return ref.appendingPathComponent("cty/cty.dat")
        case .json: return ref.appendingPathComponent("dxcc-json/dxcc.json")
        }
    }

    /// The Swift side: `ScoreCheckReport.run` over the sample directory (takes only `.log`/`.cbr`/
    /// `.cabrillo`), concurrently across all cores.
    static func swiftTable(_ mode: ScoreCheckReport.DxccMode) throws -> Table {
        let input = sampleDir()
        let output = try ScoreCheckReport.run(ScoreCheckReport.Options(
            input: input, contestData: try SessionFixture.contestData(), dxccMode: mode,
            dxccFile: try dxccFile(mode), jobs: ProcessInfo.processInfo.activeProcessorCount,
            setName: "scorecheck-sample"))
        // rows are in `collectFiles` order → relative path `set/file`
        let base = input.standardizedFileURL.path + "/"
        let places = try ScoreCheckReport.collectFiles(input).map {
            $0.standardizedFileURL.path.replacingOccurrences(of: base, with: "")
        }
        #expect(places.count == output.rows.count)
        return table(header: output.header, rows: output.rows, places: places)
    }

    static func report(_ mode: ScoreCheckReport.DxccMode, _ mismatches: [String]) -> Comment {
        var text = "scoreCheck vzorek \(mode.rawValue): \(mismatches.count) neshod"
        for line in mismatches.prefix(maxReported) { text += "\n  " + line }
        if mismatches.count > maxReported { text += "\n  … and \(mismatches.count - maxReported) more" }
        return Comment(rawValue: text)
    }

    /// Reference completeness from committed data only (runs without the corpus).
    static func checkReferenceComplete(_ java: Table, _ mode: ScoreCheckReport.DxccMode) {
        // the gate must not pass vacuously: the sample is complete and covers all statuses
        #expect(java.rows.count == 424 && java.header["logs"] == "424")
        #expect(java.duplicateKeys.isEmpty)
        // `nil == nil` would be taken by the comparator as a match — every compared header key must be in the reference
        let missingHeader = Self.comparedHeaderKeys(mode).filter { java.header[$0] == nil }
        #expect(missingHeader.isEmpty, "reference without header rows: \(missingHeader)")
        let statuses = Set(java.rows.values.map { $0.cols[2] })
        #expect(statuses == ["OK", "ERR", "EXC", "UNREADABLE"])
    }

    @Test(arguments: [ScoreCheckReport.DxccMode.cty, .json])
    func sampleReferenceIsComplete(mode: ScoreCheckReport.DxccMode) throws {
        Self.checkReferenceComplete(try Self.reference(mode), mode)
    }

    @Test(.enabled(if: ScoreCheckSampleCorpus.available, ScoreCheckSampleCorpus.skipReason),
          arguments: [ScoreCheckReport.DxccMode.cty, .json])
    func sampleMatchesJavaReference(mode: ScoreCheckReport.DxccMode) async throws {
        let java = try Self.reference(mode)
        Self.checkReferenceComplete(java, mode)
        // `ScoreCheckReport.run` with more threads waits in `DispatchGroup.wait` (seconds) — off the shared pool.
        let swift = try await onOwnThread("scorecheck-test") { try Self.swiftTable(mode) }
        let mismatches = Self.compare(java: java, swift: swift, headerKeys: Self.comparedHeaderKeys(mode))
        // a count, not the field: swift-testing would otherwise print the whole field and bypass the listing cap
        let mismatchCount = mismatches.count
        #expect(mismatchCount == 0, Self.report(mode, mismatches))
    }

    // MARK: - the comparator itself can go red

    @Test func comparatorFlagsEveryKindOfDifference() {
        let header = ["# format: f", "# logs: 2", "# set: a"]
        let java = Self.table(header: header, rows: ["k1\ta.log\tOK\t1", "k2\tb.log\tOK\t2", "k3\tc.log\tOK\t3"],
                              places: [])
        let swift = Self.table(header: ["# format: f", "# logs: 3", "# set: b"],
                               rows: ["k1\ta.log\tOK\t1", "k2\tb.log\tEXC\t2", "k4\td.log\tOK\t4", "k1\ta.log\tOK\t1"],
                               places: ["s1/a.log", "s2/b.log", "s2/d.log", "s3/a.log"])
        let out = Self.compare(java: java, swift: swift, headerKeys: ["format", "logs"])
        #expect(out.contains("duplicate key in Swift: k1"))
        #expect(out.contains("header logs: java=2 swift=3"))
        #expect(!out.contains { $0.hasPrefix("header set") })
        #expect(out.contains("c.log k3: missing in Swift"))
        #expect(out.contains("s2/d.log k4: missing in the reference"))
        #expect(out.contains("s2/b.log k2: status java=OK swift=EXC"))
        #expect(out.count == 5)
        #expect(Self.compare(java: java, swift: java, headerKeys: ["format", "logs"]).isEmpty)
    }

    @Test func reportIsCapped() {
        let lines = (0..<45).map { "radek \($0)" }
        let text = Self.report(.cty, lines).rawValue
        #expect(text.hasPrefix("scoreCheck vzorek cty: 45 neshod"))
        #expect(text.contains("radek 39") && !text.contains("radek 40"))
        #expect(text.hasSuffix("… and 5 more"))
    }
}
