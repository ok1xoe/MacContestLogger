import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// Reading Java references of the Cabrillo reader and converting the Swift result into their shape.
///
/// - `io-edge-java.tsv` (maintainer-only probe, format in its README): rows `F`
///   and `Q` of the `cabrillo` reader;
/// - `cabrillo-sample-java.tsv` (maintainer-only probe): a row `L` per log
///   of the sample logs with a SHA-256 fingerprint of all QSO tuples.
///
/// A QSO tuple is 14 fields in probe order (`call`, `freqHz`, `band`, `mode`, `timestampUtc` ms,
/// `rstSent`, `rstRcvd`, `serialSent`, `serialRcvd`, `exchangeSent`, `exchangeRcvd`,
/// `operator`, `comment`, `xqso`), texts escaped by UTF-16 units as in the probe.
/// Java `null` in text (`\N`) is compared as `""` — the number of cases
/// where Java returned `""` and not `null` (so it distinguishes) is counted separately and the test prints it.
enum CabrilloEdgeFixture {

    /// Row `F`: one edge file.
    struct FileRow {
        let name: String
        let sha256: String
        let decoding: String
        let read: String
    }

    struct EdgeReference {
        var version: [String: String] = [:]
        var files: [FileRow] = []
        /// Escaped tuples per file, in index order.
        var qsos: [String: [[String]]] = [:]
    }

    /// Row `L`: one log of the sample.
    struct SampleRow {
        let path: String
        let sha256: String
        let decoding: String
        let read: String
        let tupleDigest: String
        let javaEmptyTexts: String
    }

    /// Indices of the tuple's text fields (normalisation `\N` ≡ `""`).
    static let textColumns: Set<Int> = [0, 5, 6, 9, 10, 11, 12]

    // MARK: - loading

    static func edgeDirectory() throws -> URL {
        try #require(Bundle.module.url(forResource: "io-edge", withExtension: nil))
    }

    /// The sample logs are not distributed with the sources (`ScoreCheckSampleCorpus`); each log is
    /// checked against the SHA-256 in `cabrillo-sample-java.tsv` before it is compared.
    static func sampleDirectory() -> URL {
        ScoreCheckSampleCorpus.directory
    }

    private static func lines(_ resource: String) throws -> [[String]] {
        let url = try #require(Bundle.module.url(forResource: resource, withExtension: "tsv"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        }
    }

    /// The Cabrillo part of `io-edge-java.tsv`.
    static func edgeReference() throws -> EdgeReference {
        var reference = EdgeReference()
        for cols in try lines("io-edge-java") {
            switch cols[0] {
            case "V":
                reference.version[cols[1]] = cols[2]
            case "F" where cols[2] == "cabrillo":
                try #require(cols.count == 8)
                reference.files.append(FileRow(name: cols[1], sha256: cols[3], decoding: cols[5], read: cols[6]))
            case "Q" where cols[1].hasSuffix(".log"):
                try #require(cols.count == 17)
                try #require(Int(cols[2]) == reference.qsos[cols[1], default: []].count)
                reference.qsos[cols[1], default: []].append(Array(cols[3...]))
            default:
                break
            }
        }
        return reference
    }

    /// `cabrillo-sample-java.tsv`: version and rows `L`.
    static func sampleReference() throws -> (version: [String: String], logs: [SampleRow]) {
        var version: [String: String] = [:]
        var logs: [SampleRow] = []
        for cols in try lines("cabrillo-sample-java") {
            switch cols[0] {
            case "V":
                version[cols[1]] = cols[2]
            case "L":
                try #require(cols.count == 8)
                logs.append(SampleRow(path: cols[1], sha256: cols[2], decoding: cols[4], read: cols[5],
                                      tupleDigest: cols[6], javaEmptyTexts: cols[7]))
            default:
                break
            }
        }
        return (version, logs)
    }

    // MARK: - Swift result in the Java shape

    /// Probe escape by UTF-16 units; `nil` = `\N`.
    static func escape(_ text: String?) -> String {
        guard let text else { return "\\N" }
        var out = ""
        for unit in text.utf16 {
            switch unit {
            case 0x5C: out += "\\\\"
            case 0x09: out += "\\t"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x20..<0x7F: out.unicodeScalars.append(Unicode.Scalar(UInt8(unit)))
            default: out += "\\u" + hex4(unit)
            }
        }
        return out
    }

    private static func hex4(_ unit: UInt16) -> String {
        let digits: [Character] = Array("0123456789ABCDEF")
        var out = ""
        for shift in stride(from: 12, through: 0, by: -4) {
            out.append(digits[Int((unit >> UInt16(shift)) & 0xF)])
        }
        return out
    }

    /// Java `Instant.toEpochMilli()`; the reader gives whole seconds.
    static func epochMillis(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }

    /// A Swift QSO as a probe tuple (texts `""` instead of Java `null`).
    static func tuple(_ q: Qso) -> [String] {
        let null: String = "\\N"
        let band: String = q.band.map(bandName) ?? null
        let mode: String = q.mode.map(modeName) ?? null
        let time: String = q.timestampUtc.map(epochMillis) ?? null
        let serialSent: String = q.serialSent.map { String($0) } ?? null
        let serialRcvd: String = q.serialRcvd.map { String($0) } ?? null
        var out: [String] = [escape(q.call), String(q.freqHz), band, mode, time]
        out.append(contentsOf: [escape(q.rstSent), escape(q.rstRcvd), serialSent, serialRcvd])
        out.append(contentsOf: [escape(q.exchangeSent), escape(q.exchangeRcvd), escape(q.operator)])
        out.append(contentsOf: [escape(q.comment), q.xqso ? "true" : "false"])
        return out
    }

    /// Java `Band.name()` (`M20`, `CM70`…) = the name of the Swift case in uppercase.
    static func bandName(_ band: Band) -> String {
        String(describing: band).uppercased()
    }

    /// Java `Mode.name()` (`CW`, `DIGITAL`…).
    static func modeName(_ mode: Mode) -> String {
        String(describing: mode).uppercased()
    }

    /// A Java tuple after normalising `\N` ≡ `""` in texts and the number of texts where Java returned `""`.
    static func normalized(_ java: [String]) -> (tuple: [String], distinguished: Int) {
        var out = java
        var distinguished = 0
        for index in textColumns {
            if out[index] == "\\N" {
                out[index] = ""
            } else if out[index].isEmpty {
                distinguished += 1
            }
        }
        return (out, distinguished)
    }

    /// A sample fingerprint row: `index` + tuple, tabs, terminated by `\n` (like the probe).
    static func digestLine(_ index: Int, _ q: Qso) -> String {
        ([String(index)] + tuple(q)).joined(separator: "\t") + "\n"
    }

    static func sha256Hex(_ data: some DataProtocol) -> String {
        SHA256.hash(data: data).map { byte in
            let text = String(byte, radix: 16)
            return byte < 0x10 ? "0" + text : text
        }.joined()
    }

    /// Decoding category as a probe column (for an unreadable one only the class).
    static func decoding(_ data: Data) -> String {
        guard let text = Utf8Text.decodeKeepingBom(data) else {
            return "UNREADABLE java.nio.charset.MalformedInputException"
        }
        return text.unicodeScalars.first == "\u{FEFF}" ? "UTF8+BOM" : "UTF8"
    }

    /// The Java decoding column without the exception text (`Input length = N` is not emulated).
    static func javaDecodingCategory(_ decoding: String) -> String {
        String(decoding.prefix { $0 != ":" })
    }

    static let numberFormat = "EXC java.lang.NumberFormatException: "

    /// The Java `read` column shortened to what is compared: for
    /// `UncheckedIOException` the class and the class of the cause; for `NumberFormatException` the whole text, when the
    /// reference carries it (edge files — Swift emulates it verbatim), otherwise only the class (the sample).
    static func javaReadCategory(_ read: String) -> String {
        guard read.hasPrefix("EXC ") else { return read }
        if read.hasPrefix(numberFormat) {
            return IoEdgeFixture.unescape(read).map { String(decoding: $0, as: UTF16.self) } ?? read
        }
        let body = read.dropFirst(4)
        let javaClass = body.prefix { $0 != ":" && $0 != " " }
        guard let cause = body.range(of: " / cause ") else { return "EXC " + javaClass }
        let causeClass = body[cause.upperBound...].prefix { $0 != ":" && $0 != " " }
        return "EXC " + javaClass + " / cause " + causeClass
    }

    /// The Swift result of `readFile` with the same shortening; `message` = also the text of `NumberFormatException`.
    static func swiftReadCategory(_ result: Result<[Qso], CabrilloReaderError>, message: Bool = false) -> String {
        switch result {
        case .success(let qsos):
            return "QSO \(qsos.count)"
        case .failure(let error):
            switch error {
            case .unreadable(_, let causeClass):
                return "EXC \(error.javaClass) / cause \(causeClass)"
            case .numberFormat(let text):
                return message ? "EXC \(error.javaClass): " + text : "EXC \(error.javaClass)"
            }
        }
    }

    static func readFile(_ url: URL) -> Result<[Qso], CabrilloReaderError> {
        do throws(CabrilloReaderError) {
            return .success(try CabrilloReader().readFile(url))
        } catch {
            return .failure(error)
        }
    }
}
