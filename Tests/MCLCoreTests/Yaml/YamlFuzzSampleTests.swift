import Foundation
import Testing
@testable import MCLCore

/// A sample of the YAML fuzz against Java as a table in the suite.
///
/// The full fuzz (maintainer-only probe, over 200,000 inputs) is run manually;
/// this table is its deterministic cut-out so that **drift of the reader or locator
/// turns the suite red** even without manual re-measuring. The rows are chosen by `sample.py` from the outputs of
/// `ProbeErr --values`/`--trailing` (Java 21, Jackson 2.22.0 + SnakeYAML 2.5)
/// and only where Swift agrees with Java:
///
/// - `accept` — Java accepts the input; the tree is compared in the canonical format of
///   `JavaYamlParityTests` (type, value, literal spelling of the scalar),
/// - `root` — Java accepts only because it does not read past the root node; guards the end of
///   reading (`JavaYamlErrorLocator` → `rootEnd`), otherwise compared as `accept`,
/// - `reject` — Java rejects; Swift must report `.syntax` at the Java line and column.
///
/// The regeneration procedure is in a maintainer-only probe, "Sample for the suite".
@Suite struct YamlFuzzSampleTests {

    struct Row {
        let group: String
        let text: String
        let expected: Expected
    }

    enum Expected {
        case tree(String)
        case error(line: Int, column: Int)
    }

    static func load() throws -> [Row] {
        let url = try #require(Bundle.module.url(forResource: "yaml-fuzz-sample", withExtension: "tsv"))
        let content = try String(contentsOf: url, encoding: .utf8)
        return try content.split(separator: "\n").map { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let data = try #require(Data(base64Encoded: fields[1]))
            // As the loaders and `swift-harness`: Foundation drops the leading BOM, the same
            // as SnakeYAML's `UnicodeReader`.
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            switch fields[2] {
            case "OK":
                let tree = try #require(Data(base64Encoded: fields[3]))
                return Row(group: fields[0], text: text, expected: .tree(String(decoding: tree, as: UTF8.self)))
            default:
                return Row(group: fields[0], text: text,
                           expected: .error(line: try #require(Int(fields[3])),
                                            column: try #require(Int(fields[4]))))
            }
        }
    }

    @Test func sampleMatchesJava() throws {
        let rows = try Self.load()
        // Groups according to `sample.py`; if the file were shortened, the test would guard nothing.
        #expect(rows.filter { $0.group == "accept" }.count == 150)
        #expect(rows.filter { $0.group == "root" }.count == 100)
        #expect(rows.filter { $0.group == "reject" }.count == 200)
        var mismatches: [String] = []
        for row in rows {
            switch row.expected {
            case .tree(let java):
                do {
                    let swift = JavaYamlParityTests.canonicalLines(try YamlParser.parse(row.text))
                        .joined(separator: "\n")
                    if swift != java {
                        mismatches.append("\(row.group) \(row.text.debugDescription): \(swift) ≠ \(java)")
                    }
                } catch {
                    mismatches.append("\(row.group) \(row.text.debugDescription): \(error), Java OK")
                }
            case .error(let line, let column):
                do {
                    _ = try YamlParser.parse(row.text)
                    mismatches.append("\(row.group) \(row.text.debugDescription): accepted, Java \(line):\(column)")
                } catch let error as YamlError {
                    if error.kind != .syntax || error.line != line || error.column != column {
                        mismatches.append("\(row.group) \(row.text.debugDescription): \(error), Java \(line):\(column)")
                    }
                } catch {
                    mismatches.append("\(row.group) \(row.text.debugDescription): \(error)")
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) of \(rows.count):\n\(mismatches.joined(separator: "\n"))")
    }
}
