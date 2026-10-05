import Foundation
import Testing
@testable import MCLCore

/// The `goals/` package and file I/O of goals against Java v1.1.1 (maintainer-only probe,
/// table `GoalsMeasured`): the parser (hand-made rows of, tables, 860 fuzzer files), `key`, writing,
/// `fromConfigMap`, `goalFor`/`hoursOf` (incl. the `Instant` range edges), `GoalsFromLog`, `Files.readAllLines`
/// (BOM, CR/CRLF, invalid UTF-8 with the length of the bad sequence) and `Files.writeString` (permissions, link, errors).
@Suite struct GoalsMeasuredTests {

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rawRows(GoalsMeasured.rows, id)
    }

    /// Probe escaping: UTF-16 units < 0x20, > 0x7E and `\` as `\uXXXX`.
    static func esc(_ text: String) -> String {
        var out = ""
        for unit in text.utf16 {
            if unit < 0x20 || unit > 0x7E || unit == 0x5C {
                let hex: String = String(unit, radix: 16).uppercased()
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            } else {
                out.unicodeScalars.append(Unicode.Scalar(unit)!)
            }
        }
        return out
    }

    private static func list(_ items: [String]) -> String {
        ProbeRows.javaList(items.map(esc))
    }

    /// `new TreeMap<>(map).toString()`.
    static func sorted(_ map: [Int32: Int32]) -> String {
        let parts: [String] = map.keys.sorted().map { "\($0)=\(map[$0] ?? 0)" }
        return "{" + parts.joined(separator: ", ") + "}"
    }

    private static func lines(_ cell: String) -> [String] {
        cell == "<empty>" ? [] : cell.components(separatedBy: "||").map(ProbeRows.unescape)
    }

    /// `{k=v, …}` → dictionary.
    private static func map(_ cell: String) -> [Int32: Int32] {
        var out: [Int32: Int32] = [:]
        let body = String(cell.dropFirst().dropLast())
        for pair in body.components(separatedBy: ", ") where !pair.isEmpty {
            let kv: [String] = pair.components(separatedBy: "=")
            out[Int32(kv[0])!] = Int32(kv[1])!
        }
        return out
    }

    private static func instant(_ cell: String) -> JavaInstant? {
        cell == "null" ? nil : JavaInstant.parseIsoInstant(cell)!
    }

    private static func run(_ body: () throws(JavaDateTimeException) -> String) -> String {
        do {
            return try body()
        } catch {
            return "throws DateTimeException"
        }
    }

    private static func check(_ id: String, expectedCount: Int, _ actual: ([String]) -> [String]) {
        let rows: [[String]] = Self.rows(id)
        #expect(rows.count == expectedCount, "\(id)")
        var mismatches = 0
        for row in rows {
            let got: [String] = actual(row)
            let want: [String] = Array(row.suffix(got.count))
            if got != want {
                mismatches += 1
                if mismatches <= 15 {
                    Issue.record("\(id) \(row): Swift \(got)")
                }
            }
        }
        #expect(mismatches == 0, "\(id): \(mismatches) mismatches")
    }

    // MARK: - Parser, key, writing

    @Test func parseMatchesJava() {
        Self.check("G.parse", expectedCount: 956) { row in
            let band: String? = row[1] == "null" ? nil : ProbeRows.unescape(row[1])
            let r = GoalFileParser.parse(Self.lines(row[0]), band)
            return [Self.sorted(r.goals.entries), Self.list(r.ignoredLines), Self.list(r.bands)]
        }
    }

    /// Basis 3.4: rows that are reported as unrecognised (not silently dropped).
    @Test func reportsIgnoredLinesAsJava() {
        let r = GoalFileParser.parse(["type = goal", "1\u{A0}2", "99999999999 1", "\u{FEFF}1 5", "TYPE=x", "\u{663} 50"], nil)
        #expect(r.ignoredLines == ["type = goal", "1\u{A0}2", "99999999999 1", "\u{FEFF}1 5"])
        #expect(r.goals.entries == [103: 50])
    }

    @Test func keyWrapsLikeJavaInt() {
        Self.check("G.key", expectedCount: 12) { row in
            let parts: [Int32] = row[0].components(separatedBy: ",").map { Int32($0)! }
            return [String(GoalSet.key(parts[0], parts[1]))]
        }
    }

    @Test func formatTextAndConfigMapMatchJava() {
        Self.check("G.format", expectedCount: 5) { row in
            let goals = GoalSet.of(Self.map(row[0]))
            let config: [String: Int] = GoalFileWriter.toConfigMap(goals)
            let configText: String = Self.sorted(Dictionary(uniqueKeysWithValues: config.map { (Int32($0.key)!, Int32($0.value)) }))
            return [Self.list(GoalFileWriter.format(goals)), Self.esc(GoalFileWriter.toText(goals)), configText]
        }
    }

    /// Rows where Swift knowingly gives a different result than Java (a deliberate divergence from Java v1.1.1).
    private static let fromConfigDivergent: [String: String] = [
        // Duplicate key number: Java takes the last in JSON order, Swift the last in UTF-16 order ("0101" < "101").
        "101=1||0101=2": "{101=1}",
    ]

    @Test func fromConfigMapMatchesJavaExceptPinnedRows() {
        let rows: [[String]] = Self.rows("G.fromConfig")
        #expect(rows.count == 12)
        var nullRows = 0
        for row in rows {
            var stored: [String: Int] = [:]
            var hasNull = false
            for pair in row[0] == "<empty>" ? [] : row[0].components(separatedBy: "||") {
                let cut: String.Index = pair.lastIndex(of: "=")!
                let key: String = ProbeRows.unescape(String(pair[..<cut]))
                let value = String(pair[pair.index(after: cut)...])
                if value == "null" {
                    hasNull = true
                } else {
                    stored[key] = Int(value)!
                }
            }
            if hasNull {
                // Swift `[String: Int]` does not carry `null` — the behaviour is pinned by `nullGoalValueDropsTheWholeMapInsteadOfCrashing`.
                nullRows += 1
                continue
            }
            let want: String = Self.fromConfigDivergent[row[0]] ?? row[1]
            #expect(Self.sorted(GoalFileWriter.fromConfigMap(stored).entries) == want, "\(row[0])")
        }
        #expect(nullRows == 3)
        #expect(rows.first { $0[0] == "101=1||0101=2" }?[1] == "{101=2}", "Java: last in insertion order")
    }

    @Test func valueOutsideIntIsSkipped() {
        #expect(GoalFileWriter.fromConfigMap(["101": 3_000_000_000, "102": 5]).entries == [102: 5])
    }

    // MARK: - config.json

    /// What the `AppConfig` decoder does with `goals` and what `fromConfigMap` then does — pinned for Swift; the Java column
    /// of the probe (`loaded`/`default`, map, result or NPE) is in the table beside it.
    private static let swiftConfig: [String: String] = [
        #"{"101":7,"205":3}"#: "{101=7, 205=3}",
        #"{"101":null}"#: "{}",
        #"{"101":null,"205":3}"#: "{}",
        #"{"101":"7"}"#: "{}",
        #"{"101":7.9}"#: "{}",
        #"{"101":-7.9}"#: "{}",
        #"{"101":true}"#: "{}",
        #"{"101":3000000000}"#: "{}",
        #"{"101":" 7 "}"#: "{}",
        #"{"101":""}"#: "{}",
        #"{"101":[7]}"#: "{}",
        #"{"101":{}}"#: "{}",
        "null": "{}",
        "[]": "{}",
        "{}": "{}",
        #"{"x":1,"101":2}"#: "{101=2}",
        #"{"101":1,"101":2}"#: "{101=1}", // JSONDecoder takes the first occurrence of a key, Jackson the last
        #"{"101":1e2}"#: "{101=100}",
        #"{"101":"0x10"}"#: "{}",
        #"{"101":2147483647}"#: "{101=2147483647}",
        #"{"101":-2147483649}"#: "{}",
        "7": "{}",
        #""x""#: "{}",
    ]

    @Test func configGoalsAsDecodedBySwift() throws {
        let rows: [[String]] = Self.rows("G.config")
        #expect(rows.count == 24)
        let prefix = #"{"station":{"call":"OK1TST"},"goals":"#
        for row in rows {
            let json: String = ProbeRows.unescape(row[0])
            let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
            #expect(config.station.call == "OK1TST", "the rest of the configuration stays: \(json)")
            let goals: String = Self.sorted(GoalFileWriter.fromConfigMap(config.goals).entries)
            guard json.hasPrefix(prefix) else {
                #expect(goals == "{}" && row[3] == "{}", "\(json)")
                continue
            }
            let fragment = String(json.dropFirst(prefix.count).dropLast())
            #expect(goals == Self.swiftConfig[fragment], "\(json)")
        }
    }

    @Test func nullGoalValueDropsTheWholeMapInsteadOfCrashing() throws {
        let java: [String: [String]] = Dictionary(uniqueKeysWithValues: Self.rows("G.config").map { ($0[0], Array($0.dropFirst())) })
        let json = #"{"station":{"call":"OK1TST"},"goals":{"101":null,"205":3}}"#
        // Java: Jackson loads the map even with `null`, `fromConfigMap` crashes with an NPE (the Rate window and the goals editor).
        #expect(java[json] == ["loaded", "{101=null, 205=3}", "throws NullPointerException"])
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.goals.isEmpty)
        #expect(try GoalFileWriter.fromConfigMap(config.goals).goalFor(nil, nil) == GoalSet.defaultGoal)
        #expect(config.station.call == "OK1TST")
    }

    // MARK: - Time

    @Test func goalForMatchesJava() {
        Self.check("G.goalFor", expectedCount: 1140) { row in
            let goals = GoalSet.of(Self.map(row[0]))
            let start: JavaInstant? = Self.instant(row[1])
            let when: JavaInstant? = Self.instant(row[2])
            return [Self.run { () throws(JavaDateTimeException) -> String in
                String(try goals.goalFor(start, when))
            }]
        }
    }

    @Test func hoursOfMatchesJava() {
        Self.check("G.hoursOf", expectedCount: 113) { row in
            let start: JavaInstant? = Self.instant(row[0])
            let duration: Int32 = Int32(row[1])!
            return [Self.run { () throws(JavaDateTimeException) -> String in
                ProbeRows.javaList(try GoalSet.hoursOf(start, duration).map { String($0) })
            }]
        }
    }

    @Test func deriveMatchesJava() {
        Self.check("G.derive", expectedCount: 12) { row in
            let start: JavaInstant? = Self.instant(row[0])
            let band: Band? = Band(rawValue: row[1])
            var log: [Qso] = []
            for spec in row[2] == "<empty>" ? [] : row[2].components(separatedBy: "||") {
                let f: [String] = spec.components(separatedBy: "/")
                var q = Qso()
                q.call = "DL1ABC"
                q.timestampUtc = Self.instant(f[0])?.date
                q.band = Band(rawValue: f[1])
                q.deleted = f[2] == "D"
                log.append(q)
            }
            return [Self.run { () throws(JavaDateTimeException) -> String in
                Self.sorted(try GoalsFromLog.derive(log, start, band).entries)
            }]
        }
    }

    // MARK: - Files

    private static func withTemporaryDirectory(_ body: (String) throws -> Void) throws {
        let dir: String = NSTemporaryDirectory() + "goals-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try body(dir)
    }

    private static func bytes(hex: String) -> [UInt8] {
        guard hex != "<empty>" else { return [] }
        let chars: [Character] = Array(hex)
        return stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...$0 + 1]), radix: 16)! }
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { $0 < 16 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
    }

    private static func error(_ error: JavaIOError, _ dir: String) -> String {
        let simple: String = error.javaClass.components(separatedBy: ".").last ?? error.javaClass
        let message: String = JavaText.replace(error.message ?? "null", dir, "<work>")
        return "throws " + simple + ": " + esc(message)
    }

    private static func read(_ path: String, _ dir: String) -> String {
        do throws(JavaIOError) {
            return list(try GoalFileIO.readLines(path))
        } catch {
            return Self.error(error, dir)
        }
    }

    @Test func readLinesMatchesJava() throws {
        try Self.withTemporaryDirectory { dir in
            Self.check("G.read", expectedCount: 34) { row in
                let path: String = dir + "/goals-read.txt"
                FileManager.default.createFile(atPath: path, contents: Data(Self.bytes(hex: row[0])))
                defer { unlink(path) }
                return [Self.read(path, dir)]
            }
            try FileManager.default.createDirectory(atPath: dir + "/goals-dir", withIntermediateDirectories: false)
            let cases: [String: String] = ["directory": dir + "/goals-dir", "missing": dir + "/missing.txt"]
            Self.check("G.readError", expectedCount: 2) { row in
                [Self.read(cases[row[0]]!, dir)]
            }
        }
    }

    @Test func malformedLengthOfValidTextIsNil() {
        #expect(GoalFileIO.malformedLength(Array("Type=GOAL\n101 9\n\u{1F600}\u{FFFF}".utf8)) == nil)
    }

    private static func mode(_ path: String) -> String {
        var info = stat()
        guard lstat(path, &info) == 0 else { return "?" }
        let flags: [(mode_t, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"), (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x"),
        ]
        return String(flags.map { info.st_mode & $0.0 != 0 ? $0.1 : "-" })
    }

    private static func listing(_ dir: String) -> String {
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return "[" + names.sorted { JavaText.compare($0, $1) < 0 }.joined(separator: ", ") + "]"
    }

    private static func write(_ goals: [Int32: Int32], _ target: String, _ dir: String, _ work: String) -> [String] {
        var out: String
        do throws(JavaIOError) {
            try GoalFileIO.write(GoalSet.of(goals), to: target)
            let written: [UInt8] = Array(FileManager.default.contents(atPath: target) ?? Data())
            out = "ok " + hex(written) + " " + mode(target)
        } catch {
            out = Self.error(error, work)
        }
        return [out, listing(dir)]
    }

    /// A Java row with permissions measured under the probe's umask (022) rewritten to the permissions the same kind of file gets
    /// under this process's umask — `rw-r--r--` of a new file and `rwxr-xr-x` of a link.
    private static func underLocalUmask(_ row: [String], file: String, link: String) -> [String] {
        row.map { (cell: String) -> String in
            let mapped: String = JavaText.replace(cell, " rw-r--r--", " " + file)
            return JavaText.replace(mapped, " rwxr-xr-x", " " + link)
        }
    }

    /// `Files.writeString`. A new file has permissions `0666` without umask (probe: 022 → `rw-r--r--`), an existing one keeps its
    /// permissions, through a symlink its target is written, no temporary files; errors like Java.
    /// Independent of umask: the permissions of a new file and a link are taken from a reference file (`open(…, 0666)` like
    /// Java) and a link created in the same test, umask is not read.
    @Test func writeMatchesJava() throws {
        let measured: [String: [String]] = Dictionary(uniqueKeysWithValues: Self.rows("G.write").map { ($0[0], $0) })
        #expect(measured.count == 8)
        let plan: [Int32: Int32] = [101: 9, 205: 3]
        try Self.withTemporaryDirectory { work in
            let referenceFile: String = work + "/reference-file"
            let descriptor: Int32 = open(referenceFile, O_WRONLY | O_CREAT | O_EXCL, 0o666)
            try #require(descriptor >= 0)
            close(descriptor)
            try #require(symlink("reference-file", work + "/reference-link") == 0)
            let fileMode: String = Self.mode(referenceFile)
            let linkMode: String = Self.mode(work + "/reference-link")
            let java: [String: [String]] = measured.mapValues {
                Self.underLocalUmask($0, file: fileMode, link: linkMode)
            }
            let w: String = work + "/w"
            try FileManager.default.createDirectory(atPath: w, withIntermediateDirectories: false)
            var got: [String: [String]] = [:]
            got["new"] = Self.write(plan, w + "/goals.txt", w, work)

            let existing: String = w + "/existing.txt"
            FileManager.default.createFile(atPath: existing, contents: Data(repeating: 0x30, count: 41))
            chmod(existing, 0o600)
            got["existing0600"] = Self.write(plan, existing, w, work)

            let readOnly: String = w + "/readonly.txt"
            FileManager.default.createFile(atPath: readOnly, contents: Data("x".utf8))
            chmod(readOnly, 0o444)
            defer { chmod(readOnly, 0o644) }
            got["readonlyFile"] = Self.write(plan, readOnly, w, work)

            FileManager.default.createFile(atPath: w + "/target.txt", contents: Data("old".utf8))
            symlink("target.txt", w + "/link.txt")
            got["symlink"] = Self.write(plan, w + "/link.txt", w, work)
            let linkTarget: [UInt8] = Array(FileManager.default.contents(atPath: w + "/target.txt") ?? Data())
            let isLink: Bool = (try? FileManager.default.destinationOfSymbolicLink(atPath: w + "/link.txt")) != nil
            #expect([isLink ? "link" : "file", Self.hex(linkTarget)] == Self.rows("G.writeLink").first)

            try FileManager.default.createDirectory(atPath: w + "/sub", withIntermediateDirectories: false)
            got["directory"] = Self.write(plan, w + "/sub", w, work)
            got["missingParent"] = Self.write(plan, w + "/nope/goals.txt", w, work)
            got["empty"] = Self.write([:], w + "/empty.txt", w, work)

            let ro: String = work + "/ro"
            try FileManager.default.createDirectory(atPath: ro, withIntermediateDirectories: false)
            chmod(ro, 0o555)
            defer { chmod(ro, 0o755) }
            got["readonlyDir"] = Self.write(plan, ro + "/goals.txt", ro, work)

            for (name, row) in java {
                #expect(got[name] == Array(row.dropFirst()), "\(name)")
            }
        }
    }
}
