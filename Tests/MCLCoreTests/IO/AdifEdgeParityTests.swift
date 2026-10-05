import Foundation
import Testing
@testable import MCLCore

/// `AdifReader` over the edge inputs `Fixtures/io-edge/*.adi` against Java
/// (`Fixtures/io-edge-java.tsv`, `IoEdgeFixture`): file decoding, the `readFile` result
/// (QSO count or an exception), the `readRecords` result over the decoded text, tuples of all QSOs
/// and all fields of the raw maps.
///
/// Exceptions: always the class, for `StringIndexOutOfBoundsException` also the message (Swift carries it verbatim);
/// for `MalformedInputException` only the class (the length `Input length = N` is not
/// emulated). An input SHA-256 mismatch = "REGENERATE REFERENCE" (the reference is stale), not a defect.
@Suite struct AdifEdgeParityTests {

    static let malformed = "java.nio.charset.MalformedInputException"
    static let indexError = "java.lang.StringIndexOutOfBoundsException"
    static let unchecked = "java.io.UncheckedIOException"

    /// The Java row `dekódování` in the Swift shape (without the `MalformedInputException` message).
    static func decodingLabel(_ data: Data) -> String {
        guard let text = Utf8Text.decodeKeepingBom(data) else { return "UNREADABLE " + malformed }
        return text.unicodeScalars.first == "\u{FEFF}" ? "UTF8+BOM" : "UTF8"
    }

    /// The Java exception text shortened to what is compared: for `MalformedInputException`
    /// (also as the cause of `UncheckedIOException`) only the class.
    static func comparable(_ java: String) -> String {
        guard let range = java.range(of: malformed) else { return java }
        return String(java[java.startIndex..<range.upperBound])
    }

    static func label(_ error: any Error, path: String) -> String {
        switch error {
        case let e as JavaIndexOutOfBoundsError:
            return "EXC " + indexError + ": " + e.message
        case let e as UncheckedIOError:
            let message = e.message.replacingOccurrences(of: path, with: "<path>")
            let cause = e.cause is Utf8Text.MalformedInput ? malformed : String(describing: e.cause)
            return "EXC " + unchecked + ": " + message + " / cause " + cause
        default:
            return "EXC swift " + String(describing: error)
        }
    }

    @Test func readerMatchesJavaOnEdgeInputs() throws {
        try JavaV111Gate.run {
            let fx = try IoEdgeFixture.load()
            #expect(fx.version["java.version"] == "21.0.2")
            let adifFiles = fx.files.filter { $0.reader == "adif" }
            let dir = try IoEdgeFixture.inputURL("")
            let onDisk = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasSuffix(".adi") }
            #expect(Set(onDisk) == Set(adifFiles.map(\.name)), "inputs and reference do not match")

            var mismatches: [String] = []
            var stats = IoEdgeFixture.Stats()
            var qsoCount = 0
            var recordFields = 0
            for row in adifFiles {
                let url = try IoEdgeFixture.inputURL(row.name)
                let data = try Data(contentsOf: url)
                guard ScoreCheckReport.sha256Hex(data) == row.sha256, data.count == row.bytes else {
                    mismatches.append("\(row.name): REGENERATE REFERENCE — the input bytes differ from the reference")
                    continue
                }
                let decoding = Self.decodingLabel(data)
                if decoding != Self.comparable(row.decoding) {
                    mismatches.append("\(row.name) decoding: java=\(row.decoding) swift=\(decoding)")
                }

                // `readFile` — the application path.
                var swiftQsos: [Qso] = []
                let read: String
                do {
                    swiftQsos = try AdifReader().readFile(url)
                    read = "QSO " + String(swiftQsos.count)
                } catch {
                    read = Self.label(error, path: url.path)
                }
                let javaRead = IoEdgeFixture.unescape(Self.comparable(row.read)).map {
                    String(decoding: $0, as: UTF16.self)
                }
                if read != javaRead {
                    mismatches.append("\(row.name) read: java=\(row.read) swift=\(read)")
                }
                mismatches += IoEdgeFixture.compareQsos(
                    file: row.name, java: fx.qsos[row.name] ?? [], swift: swiftQsos, stats: &stats)
                qsoCount += swiftQsos.count

                // `readRecords` over the decoded text.
                guard let text = Utf8Text.decodeKeepingBom(data) else {
                    if row.records != "-" { mismatches.append("\(row.name) records: java=\(row.records) swift=-") }
                    continue
                }
                var swiftRecords: [[String: String]] = []
                let records: String
                do {
                    swiftRecords = try AdifReader().readRecords(text)
                    records = "REC " + String(swiftRecords.count)
                } catch {
                    records = Self.label(error, path: url.path)
                }
                if records != row.records {
                    mismatches.append("\(row.name) records: java=\(row.records) swift=\(records)")
                }
                let javaRecords = fx.records[row.name] ?? [:]
                for (index, map) in swiftRecords.enumerated() {
                    let swiftPairs = map.map { (Array($0.key.utf16), Array($0.value.utf16)) }
                        .sorted { $0.0.lexicographicallyPrecedes($1.0) }
                    let javaPairs = javaRecords[index] ?? []
                    recordFields += javaPairs.count
                    if swiftPairs.map(\.0) != javaPairs.map(\.0) {
                        let j = javaPairs.map { IoEdgeFixture.escape($0.0) }.joined(separator: ",")
                        let s = swiftPairs.map { IoEdgeFixture.escape($0.0) }.joined(separator: ",")
                        mismatches.append("\(row.name) record \(index) keys: java=\(j) swift=\(s)")
                        continue
                    }
                    for (j, s) in zip(javaPairs, swiftPairs)
                    where !IoEdgeFixture.same(java: j.1, swift: s.1, file: row.name, stats: &stats) {
                        let key = IoEdgeFixture.escape(j.0)
                        let values = "java=" + IoEdgeFixture.escape(j.1) + " swift=" + IoEdgeFixture.escape(s.1)
                        mismatches.append("\(row.name) record \(index) \(key): " + values)
                    }
                }
                if javaRecords.count > swiftRecords.count {
                    mismatches.append("\(row.name): java has more records in the R rows")
                }
            }

            print(
                "AdifEdgeParity: \(adifFiles.count) files, \(qsoCount) QSOs, \(stats.comparedFields) QSO fields, "
                    + "\(recordFields) map fields; null≡\"\" (Java returned \"\", not null): \(stats.javaEmptyNotNull)×; "
                    + "lone surrogate (allowlist): \(stats.surrogateAllowances)×")
            let report: String = mismatches.prefix(60).joined(separator: "\n")
            #expect(mismatches.isEmpty, "\(mismatches.count) mismatches:\n\(report)")
            // Java returned `""`, not `null`: the edge `comment` (value truncated at `<EOR>`), no. 6
            // `rstRcvd` (`<RST_RCVD:0>`), `rstSent` and `comment` (`<…:0>`).
            #expect(stats.javaEmptyNotNull == 4)
            // `comment` in the QSO tuple and in the raw map — the exception must not apply elsewhere.
            #expect(stats.surrogateAllowances == 2)
        }
    }
}
