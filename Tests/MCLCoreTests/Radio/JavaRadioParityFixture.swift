import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// Helpers of the `JavaRadioParityTests` gate: inputs from the reference
/// a maintainer-only probe, fingerprints of own inputs (corpus, `rigctl -l`, PCM),
/// writing rows like the generator (`tx`, `line`) and the item checksum (`IoRefGen`/`EngineRefGen.entry`
/// without a definition: SHA-256 of the text `inputs TAB sha(in rows) LF`).
///
/// Input rows the generator invented itself (grids, seeded fuzzers) are taken from the reference;
/// inputs lying in the repo (`radio-gate/corpus.txt`, `hamlib-rigctl-l-4.7.1.txt`, `radio-gate/dsp/*.wav`)
/// are fingerprinted by Swift itself — so changing them gives "REGENERATE REFERENCE", not "MISMATCH".
enum JavaRadioParityFixture {

    typealias Entry = JavaYamlParityTests.ReferenceFile

    // MARK: - Inputs from the reference

    /// Rows `in` of one reference item: path → fields (after JSON, still after `tx`).
    struct Inputs: Sendable {
        let ordered: [String]
        let byPath: [String: [String]]

        init(_ entry: Entry) {
            var ordered: [String] = []
            var byPath: [String: [String]] = [:]
            for line in entry.lines where JavaEngineParityTests.isInput(line) {
                let fields: [String] = JavaEngineParityTests.fields(line)
                ordered.append(fields[0])
                byPath[fields[0]] = Array(fields.dropFirst(2))
            }
            self.ordered = ordered
            self.byPath = byPath
        }

        /// Input fields (empty when missing in the reference — the difference then shows up as an input mismatch).
        func fields(_ path: String) -> [String] {
            byPath[path] ?? []
        }

        /// Input fields unpacked from `tx` (`~` = `nil`).
        func values(_ path: String) -> [String?] {
            fields(path).map(JavaIoParityFixture.untx)
        }

        /// Input paths `prefix` + one segment (without another `/`), in reference order; the fingerprint
        /// of the corpus `/corpus` is computed by Swift itself, hence it is not among them.
        func children(_ prefix: String) -> [String] {
            ordered.filter { $0 != "/corpus" && $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }
        }
    }

    /// An item in progress: rows in generator order.
    struct Builder {
        let name: String
        let inputs: Inputs
        var lines: [String] = []

        init(_ name: String, _ inputs: Inputs) {
            self.name = name
            self.inputs = inputs
        }

        /// Input taken from the reference.
        mutating func input(_ path: String) {
            lines.append(JavaIoParityFixture.line(path, "in", inputs.fields(path)))
        }

        /// Input computed by Swift (a fingerprint of a file or the corpus).
        mutating func own(_ path: String, _ fields: [String]) {
            lines.append(JavaIoParityFixture.line(path, "in", fields))
        }

        mutating func out(_ path: String, _ fields: String...) {
            lines.append(JavaIoParityFixture.line(path, "out", fields))
        }

        func entry() -> Entry {
            let sum = JavaIoParityFixture.checksum(definition: nil, registry: "", lines: lines)
            return Entry(relative: name, sha256: sum, lines: lines)
        }
    }

    // MARK: - Own inputs

    static func gateDirectory() throws -> URL {
        try #require(Bundle.module.url(forResource: "radio-gate", withExtension: nil),
                     "the bundle has no radio-gate directory — the .copy rule in Package.swift")
    }

    /// Rows of the hand-made corpus (`radio-gate/corpus.txt`) like Java `Files.readAllLines`.
    static func corpusLines() throws -> [String] {
        let data = try Data(contentsOf: try gateDirectory().appendingPathComponent("corpus.txt"))
        var lines: [String] = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// Fingerprint of the corpus sections (`RadioRefGen.corpusDigest`): SHA-256 of the rows with the `tags` markers.
    static func corpusDigest(_ lines: [String], _ tags: [String]) -> String {
        var text = ""
        for line in lines where tags.contains(where: { line.hasPrefix($0 + "\t") }) {
            text += line + "\n"
        }
        return sha256(Data(text.utf8))
    }

    static func sha256(_ data: Data) -> String {
        JavaYamlParityTests.sha256Hex(data)
    }

    static func wav(_ name: String) throws -> Data {
        try Data(contentsOf: try gateDirectory().appendingPathComponent("dsp/" + name + ".wav"))
    }

    // MARK: - Values

    static func tx(_ text: String?) -> String {
        JavaIoParityFixture.tx(text)
    }

    static func untx(_ text: String) -> String? {
        JavaIoParityFixture.untx(text)
    }

    static func bool(_ text: String) -> Bool {
        text == "1"
    }

    static func flag(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    static func int(_ text: String) -> Int {
        Int(text) ?? Int.min
    }

    static func int64(_ text: String) -> Int64 {
        Int64(text) ?? Int64.min
    }

    static func int32(_ text: String) -> Int32 {
        Int32(text) ?? Int32.min
    }

    /// `Long.toHexString(Double.doubleToRawLongBits(d))`.
    static func double(bits text: String) -> Double {
        Double(bitPattern: UInt64(text, radix: 16) ?? 0)
    }

    static func mode(_ text: String) -> Mode? {
        text == "~" ? nil : Mode(rawValue: text)
    }

    static func band(_ text: String) -> Band? {
        text == "~" ? nil : Band(rawValue: text)
    }

    /// `RadioRefGen.list`: items after `tx` joined by `|`.
    static func list(_ items: [String]) -> String {
        items.map { tx($0) }.joined(separator: "|")
    }

    static func javaList(_ items: [String]) -> String {
        "[" + items.joined(separator: ", ") + "]"
    }

    static func hex(_ bytes: [UInt8]) -> String {
        KeyerProbe.hex(bytes)
    }

    static func javaDouble(_ value: Double) -> String {
        JavaDouble.toString(value)
    }

    /// An instant from epoch milliseconds (Java `Instant.ofEpochMilli`).
    static func date(millis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    // MARK: - Tolerance (DSP)

    /// A row of space-separated numbers: if they match the Java ones within `tolerance`, returns the Java text
    /// (the comparison then passes); otherwise the Swift one. `maxDeviation` = the largest difference.
    static func reconcile(java: String?, swift: [Double], tolerance: Double, maxDeviation: inout Double) -> String {
        let mine: String = swift.map { javaDouble($0) + " " }.joined()
        guard let java else { return mine }
        let parts: [Substring] = java.split(separator: " ")
        guard parts.count == swift.count else { return mine }
        for (text, value) in zip(parts, swift) {
            guard let expected = Double(String(text)) else { return mine }
            let deviation: Double = abs(expected - value)
            if expected != value && !(deviation <= tolerance) { return mine }
            if expected != value { maxDeviation = max(maxDeviation, deviation) }
        }
        return java
    }

    /// The value of a reference output row (the first field after `out`).
    static func outputs(_ entry: Entry) -> [String: [String]] {
        var map: [String: [String]] = [:]
        for line in entry.lines where !JavaEngineParityTests.isInput(line) {
            let fields: [String] = JavaEngineParityTests.fields(line)
            map[fields[0]] = Array(fields.dropFirst(2))
        }
        return map
    }

    /// Parity report truncated to a reasonable length (the DSP rows have tens of kB).
    static func capped(_ report: String) -> String {
        report.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.count > 600 ? String(line.prefix(600)) + "…" : String(line)
        }.joined(separator: "\n")
    }
}
