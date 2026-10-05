import Foundation
import Testing
@testable import MCLCore

/// Reading reference fields (maintainer-only probe) without crashing: a malformed number is an error, not `!`.
enum JavaNetParityValues {

    struct Malformed: Error, CustomStringConvertible {
        let text: String
        var description: String { "malformed reference input: \(text)" }
    }

    static func int(_ text: String) throws -> Int {
        guard let value = Int(text) else { throw Malformed(text: text) }
        return value
    }

    static func int32(_ text: String) throws -> Int32 {
        guard let value = Int32(text) else { throw Malformed(text: text) }
        return value
    }

    static func int64(_ text: String) throws -> Int64 {
        guard let value = Int64(text) else { throw Malformed(text: text) }
        return value
    }

    /// `Double.toString` (Swift `Double(_:)` also reads `1.0E-5`, `NaN`, `Infinity`).
    static func double(_ text: String) throws -> Double {
        guard let value = Double(text) else { throw Malformed(text: text) }
        return value
    }

    /// `Long.toHexString(Double.doubleToRawLongBits(d))`.
    static func double(bits text: String) throws -> Double {
        guard let raw = UInt64(text, radix: 16) else { throw Malformed(text: text) }
        return Double(bitPattern: raw)
    }

    /// `Float.floatToIntBits` in hexadecimal.
    static func float(_ text: String) throws -> Float {
        guard let raw = UInt32(text, radix: 16) else { throw Malformed(text: text) }
        return Float(bitPattern: raw)
    }
}

/// Helpers of the `JavaNetParityTests` gate: replay of a reference item (input rows from the reference, output
/// computed by Swift), fingerprints of inputs lying in the repo and reporting of differences.
enum JavaNetParityFixture {

    typealias Entry = JavaYamlParityTests.ReferenceFile
    typealias F = JavaIoParityFixture
    typealias Rows = [(String, [String])]

    /// Computation of one item: outputs before the input row, after it and at the end of the item. Lives on one thread.
    struct Runner {
        let compute: (String, [String]) throws -> Rows
        var before: (String) -> Rows = { _ in [] }
        var finish: () -> Rows = { [] }
    }

    /// Runner of item `name`; `java` = the Java outputs of the item (geo compares them with a tolerance).
    static func runner(_ name: String, _ java: Entry) throws -> Runner {
        if name.hasPrefix("dxcluster.") {
            let ctx = DxClusterParitySections.Ctx()
            return Runner(compute: { try DxClusterParitySections.compute(name, $0, $1, ctx) },
                          before: { DxClusterParitySections.before(name, $0, ctx) },
                          finish: { DxClusterParitySections.finish(name, ctx) })
        }
        if name.hasPrefix("wsjtx.") {
            return Runner(compute: { [($0, try WsjtxParitySections.output(name, $0, $1))] })
        }
        if BroadcastParitySections.names.contains(name) {
            let ctx = BroadcastParitySections.Ctx()
            return Runner(compute: { try BroadcastParitySections.compute(name, $0, $1, ctx) })
        }
        if CallbookParitySections.names.contains(name) {
            let ctx = CallbookParitySections.Ctx(dxcc: try DxccResolver.fromData(DxccTestFixture.data()))
            return Runner(compute: { try CallbookParitySections.compute(name, $0, $1, ctx) })
        }
        if GeoParitySections.names.contains(name) {
            let expected: [String: [String]] = outputs(java)
            return Runner(compute: { path, fields in
                let mine: [String] = try GeoParitySections.output(name, path, fields)
                // Continuous fields within tolerance (`GeoParitySections.matches`) → Java text, so the rows agree.
                if let theirs = expected[path], GeoParitySections.matches(name, theirs, mine) {
                    return [(path, theirs)]
                }
                return [(path, mine)]
            })
        }
        return Runner(compute: { [($0, try SyncParitySections.output(name, $0, $1))] })
    }

    /// Output rows of an item: path → fields (first occurrence).
    static func outputs(_ entry: Entry) -> [String: [String]] {
        var map: [String: [String]] = [:]
        for line in entry.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count >= 2, fields[1] == "out", map[fields[0]] == nil else { continue }
            map[fields[0]] = Array(fields.dropFirst(2))
        }
        return map
    }

    /// Replays an item: input rows from the reference (fingerprints of repo files are computed by Swift — `own`), after each
    /// the outputs computed by Swift. A Swift error at a row = the output row `SWIFT ERROR`, not a crash of the whole gate.
    static func replay(_ java: Entry, own: [String: String]) throws -> Entry {
        let runner = try runner(java.relative, java)
        var lines: [String] = []
        lines.reserveCapacity(java.lines.count)
        for line in java.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count >= 2, fields[1] == "in" else { continue }
            let path: String = fields[0]
            for (outPath, out) in runner.before(path) {
                lines.append(F.line(outPath, "out", out))
            }
            if let digest = own[path] {
                lines.append(F.line(path, "in", [digest]))
                continue
            }
            lines.append(line)
            do {
                for (outPath, out) in try runner.compute(path, Array(fields.dropFirst(2))) {
                    lines.append(F.line(outPath, "out", out))
                }
            } catch {
                lines.append(F.line(path, "out", ["SWIFT ERROR", String(describing: error)]))
            }
        }
        for (outPath, out) in runner.finish() {
            lines.append(F.line(outPath, "out", out))
        }
        let sum: String = F.checksum(definition: nil, registry: "", lines: lines)
        return Entry(relative: java.relative, sha256: sum, lines: lines)
    }

    // MARK: - Inputs from the repo

    /// Fingerprints of inputs that the generator reads from the repo (`Sec.inFile`, `NetRefGen.dirDigest`); their change
    /// = "REGENERATE REFERENCE".
    static func ownInputs() throws -> [String: String] {
        let dxcc: String = JavaYamlParityTests.sha256Hex(try DxccTestFixture.data())
        let contestData: String = try dirDigest(try SessionFixture.contestData(), ["contests", "multipliers"])
        return ["/dxcc": dxcc, "/contest-data": contestData]
    }

    /// `NetRefGen.dirDigest`: SHA-256 of the text `subdirectory/name TAB sha256 LF` over regular files
    /// (without hidden ones) sorted by name.
    static func dirDigest(_ root: URL, _ subdirs: [String]) throws -> String {
        var text = ""
        for sub in subdirs {
            let dir: URL = root.appendingPathComponent(sub)
            let names: [String] = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { !$0.hasPrefix(".") }.sorted()
            for name in names {
                let url: URL = dir.appendingPathComponent(name)
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                text += sub + "/" + name + "\t"
                text += JavaYamlParityTests.sha256Hex(try Data(contentsOf: url)) + "\n"
            }
        }
        return JavaYamlParityTests.sha256Hex(Data(text.utf8))
    }

    // MARK: - Reporting

    /// Differences reference × Swift: a different set of items or an input checksum → "REGENERATE REFERENCE",
    /// otherwise "MISMATCH" with at most 6 differences per item and 30 in total (a row truncated to 400 characters). `label` = the parity
    /// arm in the report — mandatory, so the report never carries another suite's name.
    static func differences(reference: [Entry], mine: [Entry], regenerate: String, label: String) -> String? {
        let referenceNames: [String] = reference.map(\.relative)
        let mineNames: [String] = mine.map(\.relative)
        if referenceNames != mineNames {
            return "REGENERATE REFERENCE (\(label)) — the set of items diverged: reference "
                + referenceNames.joined(separator: ", ") + " | Swift " + mineNames.joined(separator: ", ") + regenerate
        }
        let stale: [String] = zip(reference, mine).filter { $0.sha256 != $1.sha256 }.map(\.0.relative)
        if !stale.isEmpty {
            return "REGENERATE REFERENCE (\(label)) — the code did not diverge, the inputs did. Checksum mismatch at: "
                + stale.joined(separator: ", ") + regenerate
        }
        var report: [String] = []
        for (java, swift) in zip(reference, mine) where java.lines != swift.lines {
            report += sectionDifferences(java, swift, budget: max(0, 30 - report.count))
        }
        guard !report.isEmpty else { return nil }
        return "MISMATCH (\(label)) — input checksums match, but the result diverged from Java:\n"
            + report.joined(separator: "\n")
    }

    static func sectionDifferences(_ java: Entry, _ swift: Entry, budget: Int) -> [String] {
        var inputs: [String: String] = [:]
        for line in java.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            if fields.count >= 2, fields[1] == "in" { inputs[fields[0]] = fields.dropFirst(2).joined(separator: " | ") }
        }
        let javaOut: [String: [String]] = outputs(java)
        let swiftOut: [String: [String]] = outputs(swift)
        var paths: [String] = []
        var seen = Set<String>()
        for line in java.lines + swift.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count >= 2, fields[1] == "out", seen.insert(fields[0]).inserted else { continue }
            paths.append(fields[0])
        }
        let differing: [String] = paths.filter { javaOut[$0] != swiftOut[$0] }
        var out: [String] = []
        if differing.isEmpty {
            out.append("\(java.relative): outputs match, the order or number of rows differs")
        } else {
            out.append("\(java.relative): \(differing.count) differing outputs")
        }
        for path in differing.prefix(min(6, budget)) {
            let javaText: String = javaOut[path].map { $0.joined(separator: " | ") } ?? "<row missing>"
            let swiftText: String = swiftOut[path].map { $0.joined(separator: " | ") } ?? "<row missing>"
            var detail: String = "  " + path + "\n    java  " + cap(javaText) + "\n    swift " + cap(swiftText)
            if let input = input(for: path, inputs) {
                detail += "\n    vstup " + cap(input)
            }
            out.append(detail)
        }
        return out
    }

    /// The input for an output: the row `in` with the same path, otherwise the one with the longest path that is its prefix.
    static func input(for path: String, _ inputs: [String: String]) -> String? {
        var prefix = path
        while true {
            if let found = inputs[prefix] { return found }
            guard let slash = prefix.lastIndex(of: "/"), slash != prefix.startIndex else { return nil }
            prefix = String(prefix[..<slash])
        }
    }

    static func cap(_ text: String) -> String {
        text.count > 400 ? String(text.prefix(400)) + "…" : text
    }

    // MARK: - Thread

    /// Computation of an item on its own thread (8 MB stack — deep JSON/GeoJSON nesting, regexes), not in the
    /// shared pool; the caller waits via `await`.
    static func onGateThread<T: Sendable>(_ name: String, _ body: @escaping @Sendable () throws -> T) async throws -> T {
        // A task-local does not cross into a `Thread`: capture the gate switch and rebind it on the thread.
        let javaV111: Bool = Band.javaV111Table
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
            let thread = Thread {
                do {
                    continuation.resume(returning: try Band.$javaV111Table.withValue(javaV111) { try body() })
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            thread.name = "net-gate " + name
            thread.stackSize = 8 << 20
            thread.start()
        }
    }
}
