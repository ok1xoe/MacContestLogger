import Foundation
import Testing
@testable import MCLCore

/// The `mcl-scorecheck` core (`ScoreCheckReport`) against Java rows
/// (`Fixtures/scorecheck-edge-java.tsv`) converted to the reference generator format.
///
/// Probe row: `L mode file status contest qso points multi groups computed claimed pass
/// unrecognised skip error`. Generator row: `key file status contest … claimed
/// unresolved skip errorClass error` — without `pass`, for `EXC` the `Class: message` is split
/// and groups with `null` are written `\N`; texts longer than 80 characters are hashed.
@Suite struct ScoreCheckReportTests {

    private static func probeRows(mode: String) throws -> [String: [String]] {
        let url = try #require(Bundle.module.url(forResource: "scorecheck-edge-java", withExtension: "tsv"))
        let text = try String(contentsOf: url, encoding: .utf8)
        var result: [String: [String]] = [:]
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if cols.first == "L" && cols[1] == mode { result[cols[2]] = Array(cols[3...]) }
        }
        return result
    }

    /// Probe row → generator columns (`status` … `error`).
    private static func generatorColumns(_ p: [String]) -> String {
        let status = p[0]
        let groups = p[5].replacingOccurrences(of: "=null", with: "=\\N")
        var errorClass = "\\N"
        var error = p[11]
        if status == "EXC", let sep = error.range(of: ": ") {
            errorClass = String(error[error.startIndex..<sep.lowerBound])
            error = String(error[sep.upperBound...])
        }
        let cols = [status, hashed(p[1]), p[2], p[3], p[4], groups, p[6], p[7], p[9], p[10],
                    errorClass, hashed(error)]
        return cols.joined(separator: "\t")
    }

    private static func hashed(_ escaped: String) -> String {
        if escaped == "\\N" || escaped.utf8.count <= 80 { return escaped }
        return "#sha256:" + String(ScoreCheckReport.sha256Hex(Data(escaped.utf8)).prefix(16))
    }

    private func run(mode: ScoreCheckReport.DxccMode, jobs: Int) throws -> ScoreCheckReport.Output {
        let edge = try #require(Bundle.module.url(forResource: "scorecheck-edge", withExtension: nil))
        let dxccFile: URL
        switch mode {
        case .cty:
            dxccFile = try #require(Bundle.module.url(forResource: "scorecheck-cty-mini", withExtension: "dat"))
        case .json:
            dxccFile = try #require(Bundle.module.url(forResource: "dxcc-test", withExtension: "json"))
        }
        let options = ScoreCheckReport.Options(
            input: edge, contestData: try SessionFixture.contestData(), dxccMode: mode, dxccFile: dxccFile,
            jobs: jobs, setName: "edge")
        return try ScoreCheckReport.run(options)
    }

    @Test func rowsMatchJavaProbe() throws {
        for mode in [ScoreCheckReport.DxccMode.json, .cty] {
            let probe = try Self.probeRows(mode: mode.rawValue)
            let output = try run(mode: mode, jobs: 1)
            #expect(output.rows.count == 74 && probe.count == 74)
            let edge = try #require(Bundle.module.url(forResource: "scorecheck-edge", withExtension: nil))
            for row in output.rows {
                let cols = row.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
                let name = cols[1]  // fixture names are ASCII, escape is the identity
                let data = try Data(contentsOf: edge.appendingPathComponent(name))
                let key = String(ScoreCheckReport.sha256Hex(data).prefix(16))
                let p = try #require(probe[name], "\(name)")
                #expect(row == key + "\t" + name + "\t" + Self.generatorColumns(p), "\(mode) \(name)")
            }
            #expect(output.rows.map { $0.split(separator: "\t")[1] } == output.rows.map { $0.split(separator: "\t")[1] }.sorted())
        }
    }

    @Test func parallelOutputIsIdentical() throws {
        let serial = try run(mode: .json, jobs: 1)
        let parallel = try run(mode: .json, jobs: 4)
        #expect(serial.text == parallel.text)
        #expect(serial.counts == parallel.counts)
    }

    @Test func headerDescribesInputs() throws {
        let output = try run(mode: .cty, jobs: 1)
        #expect(output.header.first == "# format: scorecheck-reference 1")
        #expect(output.header.contains("# dxcc-source: cty"))
        #expect(output.header.contains("# logs: 74"))
        #expect(output.header.last == "# columns: " + ScoreCheckReport.columns)
        let cty = try #require(output.header.first { $0.hasPrefix("# cty.dat-sha256: ") })
        #expect(cty.count == "# cty.dat-sha256: ".count + 64)
        #expect(output.text.utf8.allSatisfy { $0 < 0x80 })
    }

    @Test func longTextIsHashed() {
        let long = String(repeating: "x", count: 81)
        let text = ScoreCheckReport.text(long)
        #expect(text.hasPrefix("#sha256:") && text.count == 8 + 16)
        #expect(ScoreCheckReport.text(String(repeating: "y", count: 80)).count == 80)
        // the hash is computed from the escaped form: 40 × "č" = 240 characters escaped
        #expect(ScoreCheckReport.text(String(repeating: "č", count: 14)).hasPrefix("#sha256:"))
        #expect(ScoreCheckReport.text(nil) == "\\N")
        #expect(ScoreCheckReport.escape("a\\b\u{1F600}") == "a\\\\b\\ud83d\\ude00")
    }

    @Test func collectsOnlyLogFilesInByteOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sc-collect-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("a-b"), withIntermediateDirectories: true)
        for name in ["b.LOG", "a/z.cbr", "a-b/y.cabrillo", "c.txt", "C.log", "a/n.Log"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        let files = try ScoreCheckReport.collectFiles(root).map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }
        // byte ordering of paths: "-" (0x2D) < "/" (0x2F) < uppercase < lowercase letters
        #expect(files == ["C.log", "a-b/y.cabrillo", "a/n.Log", "a/z.cbr", "b.LOG"])
    }

    // MARK: - unreadable files, names, thread limit

    private func runOn(_ dir: URL, jobs: Int = 1) throws -> ScoreCheckReport.Output {
        let dxccFile = try #require(Bundle.module.url(forResource: "dxcc-test", withExtension: "json"))
        return try ScoreCheckReport.run(ScoreCheckReport.Options(
            input: dir, contestData: try SessionFixture.contestData(), dxccMode: .json, dxccFile: dxccFile,
            jobs: jobs))
    }

    private func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sc-report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func readFailureIsUnreadableRowNotEmptyLog() throws {
        let root = try scratch()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: root.appendingPathComponent("a.log").path)
            try? FileManager.default.removeItem(at: root)
        }
        let file = root.appendingPathComponent("a.log")
        try Data("START-OF-LOG: 3.0\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        guard !FileManager.default.isReadableFile(atPath: file.path) else { return }  // e.g. a run as root
        let output = try runOn(root)
        #expect(output.rows == ["\\N\ta.log\tUNREADABLE\t\\N\t0\t0\t0\t\t0\t\\N\t0\t\\N\t\\N\tnelze na\\u010d\\u00edst"])
    }

    @Test func invalidUtf8IsUnreadableWithContentKey() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data([0x53, 0xFF, 0xFE, 0x0A])
        try bytes.write(to: root.appendingPathComponent("bad.log"))
        let output = try runOn(root)
        let key = String(ScoreCheckReport.sha256Hex(bytes).prefix(16))
        #expect(output.rows == [key + "\tbad.log\tUNREADABLE\t\\N\t0\t0\t0\t\t0\t\\N\t0\t\\N\t\\N\tnelze na\\u010d\\u00edst"])
        #expect(output.counts == ["UNREADABLE": 1])
    }

    @Test func nonAsciiNameIsEscaped() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let edge = try #require(Bundle.module.url(forResource: "scorecheck-edge", withExtension: nil))
        try Data(contentsOf: edge.appendingPathComponent("01-zaklad-ok.log"))
            .write(to: root.appendingPathComponent("\u{F8}-\u{DF}.log"))
        // the extension must not "survive" a combining character after it
        try Data().write(to: root.appendingPathComponent("x.log\u{301}"))
        let output = try runOn(root)
        #expect(output.rows.count == 1)
        let cols = output.rows[0].split(separator: "\t", omittingEmptySubsequences: false)
        #expect(cols[1] == "\\u00f8-\\u00df.log")
        #expect(cols[2] == "OK")
    }

    @Test func jobsIsRealLimit() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<20 { try Data("x\(i)".utf8).write(to: root.appendingPathComponent("f\(i).log")) }
        let serial = try runOn(root, jobs: 1)
        for jobs in [2, 3, 64] {
            #expect(try runOn(root, jobs: jobs).text == serial.text)
        }
    }
}
