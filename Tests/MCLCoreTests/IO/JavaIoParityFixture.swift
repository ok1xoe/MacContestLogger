import Foundation
import Testing
@testable import MCLCore

/// Shared helpers of the `JavaIoParityTests` gate: reading the gzipped references
/// a maintainer-only probe, row texts (`tx`), input rows → Swift values,
/// Java `EXC class: message` from Swift errors, checksums and normalisation of the Java rows
/// of the read arm (`null ≡ ""`, lone surrogate).
///
/// The format of rows and sums is the one from a maintainer-only probe (`JavaEngineParityTests`): item =
/// `sha256` + rows `["path","in"|"out",…]`. Short inputs are after `EngineRefGen.esc`, export and reader
/// texts after `tx` (space stays, `" \ ~` and non-ASCII as `\uXXXX`, `~` = null).
enum JavaIoParityFixture {

    typealias Entry = JavaYamlParityTests.ReferenceFile

    // MARK: - Reference

    /// A reference from the bundle (`<name>.json.gz`, the `.copy` rule in `Package.swift`).
    static func reference(_ name: String) throws -> [Entry] {
        let url = try #require(Bundle.module.url(forResource: name + ".json", withExtension: "gz"),
                               Comment(rawValue: "the bundle has no \(name).json.gz — the .copy rule in Package.swift"))
        let text = try #require(String(data: try gunzip(Data(contentsOf: url)), encoding: .utf8))
        return try JavaYamlParityTests.parseReference(text)
    }

    enum GzipError: Error, CustomStringConvertible {
        case malformed(String)
        var description: String {
            switch self {
            case .malformed(let why): "invalid gzip: \(why)"
            }
        }
    }

    /// Gzip as written by Java `GZIPOutputStream`: a 10-byte header without optional fields,
    /// raw DEFLATE, CRC32 and length (both verified). Apple `zlib` in `NSData.decompressed`
    /// is exactly raw DEFLATE.
    static func gunzip(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
            throw GzipError.malformed("header")
        }
        guard bytes[3] == 0 else { throw GzipError.malformed("optional header fields \(bytes[3])") }
        let body = Data(bytes[10..<(bytes.count - 8)])
        let out = try (body as NSData).decompressed(using: .zlib) as Data
        let crc = bytes[(bytes.count - 8)..<(bytes.count - 4)].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let tail = bytes[(bytes.count - 4)...].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard tail == UInt32(truncatingIfNeeded: out.count) else { throw GzipError.malformed("length") }
        guard crc == crc32(out) else { throw GzipError.malformed("CRC32") }
        return out
    }

    /// CRC-32 table (IEEE 802.3, reversed polynomial `0xEDB88320`), as gzip writes it.
    static let crcTable: [UInt32] = (0..<256).map { (n: Int) -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        let table = crcTable
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for byte in raw { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }

    // MARK: - Texts

    static let hexDigits: [Character] = Array("0123456789ABCDEF")

    static func hex4(_ unit: UInt16) -> String {
        let shifts: [UInt16] = [12, 8, 4, 0]
        return String(shifts.map { hexDigits[Int((unit >> $0) & 0xF)] })
    }

    /// Java `IoRefGen.tx` over UTF-16 units.
    static func tx<C: Collection>(units: C) -> String where C.Element == UInt16 {
        var out = ""
        out.reserveCapacity(units.count)
        for unit in units {
            if unit < 0x20 || unit > 0x7E || unit == 0x22 || unit == 0x5C || unit == 0x7E {
                out += "\\u" + hex4(unit)
            } else {
                out.unicodeScalars.append(Unicode.Scalar(UInt8(unit)))
            }
        }
        return out
    }

    static func tx(_ text: String?) -> String {
        guard let text else { return "~" }
        return tx(units: text.utf16)
    }

    /// The inverse of `tx` (and `esc`): `~` → `nil`, `\uXXXX` → unit.
    static func untx(_ text: String) -> String? {
        JavaEngineParityTests.unesc(text)
    }

    /// The inverse of `tx` by units (a lone surrogate stays).
    static func untxUnits(_ text: String) -> [UInt16] {
        let source = Array(text.utf16)
        var units: [UInt16] = []
        var index = 0
        while index < source.count {
            if source[index] == 0x5C, index + 5 < source.count, source[index + 1] == 0x75,
               let unit = UInt16(String(decoding: source[(index + 2)..<(index + 6)], as: UTF16.self), radix: 16) {
                units.append(unit)
                index += 6
            } else {
                units.append(source[index])
                index += 1
            }
        }
        return units
    }

    /// A row with an array of values (Java `IoRefGen.lineOf`).
    static func line(_ path: String, _ kind: String, _ fields: [String]) -> String {
        let all: [String] = [path, kind] + fields
        return "[" + all.map(JavaYamlParityTests.jsonString).joined(separator: ",") + "]"
    }

    static func out(_ path: String, _ fields: String...) -> String {
        line(path, "out", fields)
    }

    static func pad(_ number: Int, _ width: Int) -> String {
        let text = String(number)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    /// A whole text as rows `path/NNNN` (Java `split("\n", -1)` by UTF-16 units).
    static func text(_ lines: inout [String], _ path: String, _ text: String) {
        let units = Array(text.utf16)
        var start = 0
        var part = 0
        for index in 0...units.count where index == units.count || units[index] == 0x0A {
            lines.append(out(path + "/" + pad(part, 4), tx(units: units[start..<index])))
            part += 1
            start = index + 1
        }
    }

    /// A text reassembled from the reference rows `path/NNNN` (for the read arm: Java exports).
    static func joinedText(_ entry: Entry, prefix: String) -> String? {
        let parts = entry.lines.filter { JavaYamlParityTests.pathOf($0).hasPrefix(prefix) }
            .map { untx(JavaEngineParityTests.fields($0)[2]) ?? "" }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    // MARK: - Exceptions

    /// Java `EXC full.name.Class: message` from a Swift error.
    static func exc(_ error: any Error) -> String {
        let (name, message) = javaException(error)
        return "EXC " + name + ": " + tx(message)
    }

    static func javaException(_ error: any Error) -> (String, String?) {
        switch error {
        case let e as CabrilloExportError:
            switch e {
            case .illegalArgument(let message): return (e.javaClass, message)
            }
        case let e as CabrilloReaderError:
            switch e {
            case .numberFormat(let message): return (e.javaClass, message)
            case .unreadable(let message, _): return (e.javaClass, message)
            }
        case let e as LogExportsError:
            switch e {
            case .nullPointer(let message): return (e.javaClass, message)
            }
        case let e as JavaIndexOutOfBoundsError:
            return ("java.lang.StringIndexOutOfBoundsException", e.message)
        case let e as ExpressionError:
            let simple = JavaEngineParityTests.javaName(e.kind)
            let package = simple == "PatternSyntaxException" ? "java.util.regex." : "java.lang."
            return (package + simple, e.message)
        default:
            return ("Swift." + String(describing: type(of: error)), "\(error)")
        }
    }

    // MARK: - Inputs

    /// Fields of an input row after the path and `in`.
    static func inputs(_ line: String) -> [String] {
        Array(JavaEngineParityTests.fields(line).dropFirst(2))
    }

    static func date(millis text: String) -> Date? {
        Int64(text).map { Date(timeIntervalSince1970: Double($0) / 1000) }
    }

    static func millis(_ date: Date?) -> String {
        guard let date else { return "~" }
        return String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }

    /// A QSO from the input `/q/NNN` (field order of `IoRefGen.qsoLines`); a Java `null` in text = `""`.
    static func qso(_ f: [String]) throws -> Qso {
        func text(_ i: Int) -> String { untx(f[i]) ?? "" }
        var q = Qso()
        q.timestampUtc = date(millis: f[0])
        q.call = text(1)
        q.freqHz = try #require(Int(f[2]))
        if f[3] != "~" {
            let band: Band = try #require(Band(rawValue: f[3]))
            q.band = band
        } else {
            q.band = nil
        }
        if f[4] != "~" {
            let mode: Mode = try #require(Mode(rawValue: f[4]))
            q.mode = mode
        }
        q.rstSent = text(5)
        q.rstRcvd = text(6)
        q.serialSent = Int(f[7])
        q.serialRcvd = Int(f[8])
        q.exchangeSent = text(9)
        q.exchangeRcvd = text(10)
        q.runMode = try #require(RunMode(rawValue: f[11]))
        q.operator = text(12)
        q.comment = text(13)
        q.dxccEntity = Int(f[14])
        q.dxccName = text(15)
        q.continent = text(16)
        q.stationId = text(17)
        q.deleted = f[18].contains("d")
        q.xqso = f[18].contains("x")
        return q
    }

    /// A station from the input `/station/N` (call, operator, grid, name, address1, address2, city,
    /// state, zip, country, arrlSection, club, email).
    static func station(_ f: [String]) -> StationConfig {
        let v: [String] = f.map { untx($0) ?? "" }
        var s = StationConfig()
        s.call = v[0]
        s.operator = v[1]
        s.gridSquare = v[2]
        s.name = v[3]
        s.address1 = v[4]
        s.address2 = v[5]
        s.city = v[6]
        s.state = v[7]
        s.zip = v[8]
        s.country = v[9]
        s.arrlSection = v[10]
        s.club = v[11]
        s.email = v[12]
        return s
    }

    static func qtc(_ f: [String]) throws -> QtcRecord {
        QtcRecord(id: Int64(f[0]), contestId: untx(f[1]), sent: f[2] == "true", partnerCall: untx(f[3]) ?? "",
                  groupNr: try #require(Int(f[4])), groupSize: try #require(Int(f[5])), qsoTime: untx(f[6]) ?? "",
                  qsoCall: untx(f[7]) ?? "", qsoSerial: try #require(Int(f[8])),
                  at: try #require(date(millis: f[9])), freqHz: try #require(Int64(f[10])), mode: untx(f[11]))
    }

    // MARK: - Definitions and checksums

    /// The gate's definitions in reference order: `contests/*.yaml` (22), then `io/*.yaml` (`io-gate-synthetic/`).
    static func definitionFiles() throws -> [(name: String, url: URL)] {
        let contests = try ContestDataLayoutTests.contestDataRoot().appendingPathComponent("contests")
        let synthetic = try #require(Bundle.module.url(forResource: "io-gate-synthetic", withExtension: nil),
                                     "the bundle has no io-gate-synthetic directory — the .copy rule in Package.swift")
        var out: [(name: String, url: URL)] = []
        for name in try JavaDefinitionParityTests.sortedNames(in: contests, suffix: ".yaml") {
            out.append(("contests/" + name, contests.appendingPathComponent(name)))
        }
        for name in try JavaDefinitionParityTests.sortedNames(in: synthetic, suffix: ".yaml") {
            out.append(("io/" + name, synthetic.appendingPathComponent(name)))
        }
        return out
    }

    /// By the same rule as `EngineRefGen.entry`; `definition` is a finished fingerprint (hex) or `nil`.
    static func checksum(definition: String?, registry: String, lines: [String]) -> String {
        let inputs = lines.filter(JavaEngineParityTests.isInput).map { $0 + "\n" }.joined()
        var text = ""
        if let definition {
            text += "definition\t" + definition + "\n"
            text += "registry\t" + registry + "\n"
        }
        text += "inputs\t" + JavaYamlParityTests.sha256Hex(Data(inputs.utf8)) + "\n"
        return JavaYamlParityTests.sha256Hex(Data(text.utf8))
    }

    // MARK: - Comparison

    /// Differences reference × Swift as `JavaEngineParityTests.differences` (set of items and sums →
    /// "REGENERATE REFERENCE", otherwise "MISMATCH"), but the input for a difference is the row `in` with the **longest
    /// path that is a prefix** of the output path (`/f/<file>`, `/cab/0`…), not the first segment.
    static func differences(reference: [Entry], mine: [Entry], arm: String, regenerate: String) -> String? {
        let referenceNames = reference.map(\.relative)
        let mineNames = mine.map(\.relative)
        if referenceNames != mineNames {
            return "REGENERATE REFERENCE (\(arm)) — the set of items diverged: reference "
                + referenceNames.joined(separator: ", ") + " | vstupy " + mineNames.joined(separator: ", ") + regenerate
        }
        let stale = zip(reference, mine).filter { $0.sha256 != $1.sha256 }.map(\.0.relative)
        if !stale.isEmpty {
            return "REGENERATE REFERENCE (\(arm)) — the code did not diverge, the input bytes did. "
                + "Checksum mismatch at: " + stale.joined(separator: ", ") + regenerate
        }
        var report: [String] = []
        for (java, swift) in zip(reference, mine) where java.lines != swift.lines && report.count < 25 {
            var javaByPath: [String: String] = [:]
            var swiftByPath: [String: String] = [:]
            var inputs: [String: String] = [:]
            for line in java.lines {
                let path = JavaYamlParityTests.pathOf(line)
                javaByPath[path] = javaByPath[path] ?? JavaYamlParityTests.valueOf(line)
                if JavaEngineParityTests.isInput(line) { inputs[path] = JavaYamlParityTests.valueOf(line) }
            }
            for line in swift.lines {
                let path = JavaYamlParityTests.pathOf(line)
                swiftByPath[path] = swiftByPath[path] ?? JavaYamlParityTests.valueOf(line)
            }
            var seen = Set<String>()
            let before = report.count
            for path in (java.lines + swift.lines).map(JavaYamlParityTests.pathOf)
            where report.count < 25 && report.count - before < 6 {
                guard seen.insert(path).inserted else { continue }
                let javaText = javaByPath[path] ?? "<row missing>"
                let swiftText = swiftByPath[path] ?? "<row missing>"
                guard javaText != swiftText else { continue }
                var input = ""
                var prefix = path
                while let slash = prefix.lastIndex(of: "/"), slash != prefix.startIndex {
                    prefix = String(prefix[..<slash])
                    if let found = inputs[prefix] {
                        input = " | vstup " + prefix + " " + String(found.prefix(160))
                        break
                    }
                }
                let shown = "java=" + unJson(javaText) + " swift=" + unJson(swiftText)
                report.append("\(java.relative): \(path): \(shown)\(unJson(input))")
            }
            if report.count == before {
                report.append("\(java.relative): rows match, their order differs")
            }
        }
        guard !report.isEmpty else { return nil }
        return "MISMATCH (\(arm)) — input checksums match, but the result diverged from Java:\n"
            + report.joined(separator: "\n")
    }

    /// A row for the report without JSON doubling of backslashes.
    static func unJson(_ text: String) -> String {
        text.replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - Normalisation of Java rows of the read arm

    /// Columns of a QSO tuple (`/q/NNN`) with the model text: `call`, `rstSent`, `rstRcvd`,
    /// `exchangeSent`, `exchangeRcvd`, `operator`, `comment`.
    static let textColumns: Set<Int> = [0, 5, 6, 9, 10, 11, 12]

    /// An edge file where Java returns a lone surrogate (Swift `U+FFFD`).
    static let surrogateAllowlist: [String] = ["/f/AR5b-pulka-surrogatu.adi/"]

    struct Normalization {
        /// Java returned `""` (not `null`) in a tuple text field — Swift cannot tell it from `null`.
        var javaEmptyNotNull = 0
        /// How many values with a lone surrogate matched as `U+FFFD` (`surrogateAllowlist` only).
        var surrogates = 0
    }

    /// Is the path a QSO tuple (`…/q/NNN`)?
    static func isTuple(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        return parts.count >= 2 && parts[parts.count - 2] == "q" && Int(parts[parts.count - 1]) != nil
    }

    /// Java rows of the read arm in a shape Swift can handle: a `null` text → `""` (it is counted
    /// how many times Java gave `""`), a lone surrogate → `U+FFFD` only in `surrogateAllowlist`.
    static func normalized(_ entry: Entry, _ stats: inout Normalization) -> Entry {
        var lines: [String] = []
        lines.reserveCapacity(entry.lines.count)
        for raw in entry.lines {
            let path = JavaYamlParityTests.pathOf(raw)
            let allow = surrogateAllowlist.contains { path.hasPrefix($0) }
            guard isTuple(path) || allow, !JavaEngineParityTests.isInput(raw) else {
                lines.append(raw)
                continue
            }
            var fields = JavaEngineParityTests.fields(raw)
            for i in 2..<fields.count {
                if isTuple(path), textColumns.contains(i - 2) {
                    if fields[i] == "" { stats.javaEmptyNotNull += 1 }
                    if fields[i] == "~" { fields[i] = "" }
                }
                if allow, fields[i].contains("\\uD") {
                    let fixed = replacingLoneSurrogates(fields[i])
                    if fixed != fields[i] { stats.surrogates += 1 }
                    fields[i] = fixed
                }
            }
            lines.append(line(path, fields[1], Array(fields.dropFirst(2))))
        }
        return Entry(relative: entry.relative, sha256: entry.sha256, lines: lines)
    }

    static func replacingLoneSurrogates(_ text: String) -> String {
        var units = untxUnits(text)
        for i in units.indices where IoEdgeFixture.isLoneSurrogate(units, at: i) {
            units[i] = 0xFFFD
        }
        return tx(units: units)
    }
}
