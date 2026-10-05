import Foundation
import Testing
@testable import MCLCore

/// A fake server in place of Java's `HttpServer` from `DefinitionUpdaterTest`: it returns
/// files by the path after `/data/` (decoded like `HttpExchange.getRequestURI().getPath()`),
/// missing ones → 404 with an empty body. It records the requested URLs.
///
/// Coverage difference against Java: the real network layer (`URLSessionDataFetcher`,
/// timeouts, redirects, network error texts) is not tested here.
final class FakeFetcher: DataFetcher, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var log: [String] = []

    subscript(path: String) -> String? {
        get { lock.withLock { files[path].map { String(decoding: $0, as: UTF8.self) } } }
        set { lock.withLock { files[path] = newValue.map { Data($0.utf8) } } }
    }

    var requests: [String] {
        get { lock.withLock { log } }
        set { lock.withLock { log = newValue } }
    }

    func fetch(_ url: URL) async throws -> (status: Int, data: Data) {
        lock.withLock {
            log.append(url.absoluteString)
            let path = url.path(percentEncoded: false)
            guard path.hasPrefix("/data/"), let body = files[String(path.dropFirst("/data/".count))] else {
                return (404, Data())
            }
            return (200, body)
        }
    }
}

/// Port of the Java `DefinitionUpdaterTest` (4 tests) and cases measured by the probe
/// `ProbeUpd.java` (maintainer-only probe, JDK 21).
@Suite struct DefinitionUpdaterTests {

    static let host = "http://127.0.0.1:1"
    static let base = URL(string: host + "/data/")!
    static let multiplier = "schemaVersion: 1\nid: dxcc_entities\nkind: EXTERNAL_DATA\n"

    static func server() -> FakeFetcher {
        let fetcher = FakeFetcher()
        fetcher["multipliers/dxcc_entities.yaml"] = multiplier
        fetcher["contests/abc.yaml"] = DefinitionEditing.template("abc", "ABC")
        fetcher["index.txt"] = "# index\ncontests/abc.yaml\nmultipliers/dxcc_entities.yaml\n"
        return fetcher
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DefinitionUpdaterTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Runs the update through its phases as the app does (`fetchIndex`, `loadManifest`, `download`, `apply`); the
    /// failure cases (`updateError`) go through the composed `update`, so every case covers one of the two.
    static func run(_ fetcher: FakeFetcher, _ dir: URL, base: URL = base) async throws -> DefinitionUpdater.Report {
        let updater = DefinitionUpdater(fetcher: fetcher)
        let index = try await updater.fetchIndex(base)
        let manifest = try DefinitionUpdater.loadManifest(dataDir: dir)
        let downloaded = try await updater.download(index)
        return try DefinitionUpdater.apply(downloaded, manifest: manifest, dataDir: dir)
    }

    static func statuses(_ report: DefinitionUpdater.Report) -> [String: DefinitionUpdater.Status] {
        Dictionary(report.files.map { ($0.path, $0.status) }, uniquingKeysWith: { _, last in last })
    }

    static func lines(_ report: DefinitionUpdater.Report) -> [String] {
        report.files.map { "\($0.path) | \($0.status) | \($0.detail)" }
    }

    static func read(_ dir: URL, _ path: String) throws -> String {
        try String(contentsOf: dir.appendingPathComponent(path), encoding: .utf8)
    }

    static func exists(_ dir: URL, _ path: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(path).path)
    }

    /// Manifest without the first two lines (comment and date).
    static func manifestEntries(_ dir: URL) throws -> [String] {
        let data = try Data(contentsOf: dir.appendingPathComponent(".update-manifest.properties"))
        return Array(String(decoding: data, as: UTF8.self).split(separator: "\n").dropFirst(2).map(String.init))
    }

    static func updateError(_ fetcher: FakeFetcher, _ dir: URL) async -> String? {
        do {
            _ = try await DefinitionUpdater(fetcher: fetcher).update(base, dataDir: dir)
            return nil
        } catch {
            return error.message
        }
    }

    static let abcHash = "797484be2df74744ae0ca04e0570a2d8cfe93f657146b441f081bbf32f4a10d3"
    static let dxccHash = "c781536efadb6fd57b8a962bf99d471f9d3c287e3fbb71813600719aee239468"

    // MARK: - Java DefinitionUpdaterTest

    /// The phases and the composed `update` give the same reports and files.
    @Test func phasesMatchTheComposedUpdate() async throws {
        let fetcher = Self.server()
        fetcher["contests/bad.yaml"] = "id: [unclosed"
        fetcher["index.txt"] = "contests/abc.yaml\ncontests/bad.yaml\ncontests/missing.yaml\n../x\n"
            + "multipliers/dxcc_entities.yaml\n"
        let viaPhases = try Self.tempDir()
        let composed = try Self.tempDir()
        defer {
            try? FileManager.default.removeItem(at: viaPhases)
            try? FileManager.default.removeItem(at: composed)
        }
        for round in 0..<2 {
            if round == 1 {
                fetcher["contests/abc.yaml"] = DefinitionEditing.template("abc", "ABC v2")
            }
            let phased = try await Self.run(fetcher, viaPhases)
            let whole = try await DefinitionUpdater(fetcher: fetcher).update(Self.base, dataDir: composed)
            #expect(Self.lines(phased) == Self.lines(whole))
            #expect(try Self.read(viaPhases, "contests/abc.yaml") == (try Self.read(composed, "contests/abc.yaml")))
            #expect(try Self.manifestEntries(viaPhases) == (try Self.manifestEntries(composed)))
        }
    }

    @Test func newThenUnchangedThenUpdated() async throws {
        let fetcher = Self.server()
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Self.statuses(try await Self.run(fetcher, dir))["contests/abc.yaml"] == .new)
        #expect(Self.statuses(try await Self.run(fetcher, dir))["contests/abc.yaml"] == .unchanged)

        fetcher["contests/abc.yaml"] = DefinitionEditing.template("abc", "ABC v2")
        #expect(Self.statuses(try await Self.run(fetcher, dir))["contests/abc.yaml"] == .updated)
        #expect(try Self.read(dir, "contests/abc.yaml").contains("ABC v2"))
    }

    @Test func localEditsAreKept() async throws {
        let fetcher = Self.server()
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await Self.run(fetcher, dir)
        try Data(DefinitionEditing.template("abc", "Moje úprava").utf8)
            .write(to: dir.appendingPathComponent("contests/abc.yaml"))
        fetcher["contests/abc.yaml"] = DefinitionEditing.template("abc", "ABC v2")

        #expect(Self.statuses(try await Self.run(fetcher, dir))["contests/abc.yaml"] == .skippedLocalChanges)
        #expect(try Self.read(dir, "contests/abc.yaml").contains("Moje úprava"))
    }

    @Test func invalidDefinitionAndMissingFileFail() async throws {
        let fetcher = Self.server()
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        fetcher["contests/abc.yaml"] = "id: abc\nbands: ["
        fetcher["index.txt"] = "contests/abc.yaml\ncontests/missing.yaml\n../etc/passwd\n"
        let result = Self.statuses(try await Self.run(fetcher, dir))
        #expect(result["contests/abc.yaml"] == .failed)
        #expect(result["contests/missing.yaml"] == .failed)
        #expect(result["../etc/passwd"] == .failed)
        #expect(!Self.exists(dir, "contests/abc.yaml"))
    }

    /// A copied `contest-data/` fixture in the bundle: `index.txt` lists all
    /// files. Like Java it omits only paths **starting** with a dot (the whole relative path
    /// counts, so `contests/.x` would be counted) and sorts by UTF-16 (`sorted()`).
    @Test func shippedIndexMatchesDirectory() throws {
        let root = try #require(Bundle.module.url(forResource: "contest-data", withExtension: nil))
        let rootPath = RawFileSystem.javaPath(of: root)
        let indexText = String(decoding: try Data(contentsOf: root.appendingPathComponent("index.txt")), as: UTF8.self)
        let index = DefinitionUpdater.indexLines(indexText).sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }

        var actual: [String] = []
        func walk(_ relative: String) {
            let path = relative.isEmpty ? rootPath : RawFileSystem.resolve(rootPath, relative)
            for name in RawFileSystem.listDirectory(path) ?? [] {
                let child = (relative.isEmpty ? "" : relative + "/") + String(decoding: name, as: UTF8.self)
                if RawFileSystem.isDirectory(RawFileSystem.resolve(rootPath, child)) {
                    walk(child)
                } else {
                    actual.append(child)
                }
            }
        }
        walk("")
        actual = actual.filter { $0 != "index.txt" && !$0.hasPrefix(".") }
            .sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        #expect(actual == index, "contest-data/index.txt must list all files")
        #expect(index.count > 30)
    }

    // MARK: - measured by the ProbeUpd probe

    /// A1–A4: states, `detail`, `summary()` verbatim and the manifest (lines sorted by key).
    @Test func reportsAndManifestAcrossRuns() async throws {
        let fetcher = Self.server()
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var report = try await Self.run(fetcher, dir)
        #expect(Self.lines(report) == ["contests/abc.yaml | NEW | ", "multipliers/dxcc_entities.yaml | NEW | "])
        #expect(report.summary() == "nové 2, aktualizované 0, beze změny 0, ponechané lokální úpravy 0, chyby 0")
        #expect(fetcher.requests == [Self.host + "/data/index.txt", Self.host + "/data/contests/abc.yaml",
                                     Self.host + "/data/multipliers/dxcc_entities.yaml"])
        #expect(try Self.manifestEntries(dir) == ["contests/abc.yaml=" + Self.abcHash,
                                                  "multipliers/dxcc_entities.yaml=" + Self.dxccHash])

        report = try await Self.run(fetcher, dir)
        #expect(report.summary() == "nové 0, aktualizované 0, beze změny 2, ponechané lokální úpravy 0, chyby 0")

        fetcher["contests/abc.yaml"] = DefinitionEditing.template("abc", "ABC v2")
        report = try await Self.run(fetcher, dir)
        #expect(Self.lines(report) == ["contests/abc.yaml | UPDATED | ", "multipliers/dxcc_entities.yaml | UNCHANGED | "])
        #expect(try Self.manifestEntries(dir) == [
            "contests/abc.yaml=cbb2dc3315ab65ee95ef2cf79f974633a0230d46ba937a8ceed69a0ce54b6ec8",
            "multipliers/dxcc_entities.yaml=" + Self.dxccHash,
        ])

        try Data(DefinitionEditing.template("abc", "Moje").utf8).write(to: dir.appendingPathComponent("contests/abc.yaml"))
        fetcher["contests/abc.yaml"] = DefinitionEditing.template("abc", "ABC v3")
        report = try await Self.run(fetcher, dir)
        #expect(Self.lines(report) == ["contests/abc.yaml | SKIPPED_LOCAL_CHANGES | soubor je lokálně upravený",
                                       "multipliers/dxcc_entities.yaml | UNCHANGED | "])
        #expect(report.summary() == "nové 0, aktualizované 0, beze změny 1, ponechané lokální úpravy 1, chyby 0")
        #expect(report.count(.skippedLocalChanges) == 1)
        // A skipped file does not change the manifest.
        #expect(try Self.manifestEntries(dir)[0] == "contests/abc.yaml=cbb2dc3315ab65ee95ef2cf79f974633a0230d46ba937a8ceed69a0ce54b6ec8")
    }

    /// The manifest has a Java header: a Latin-1 comment with `\uXXXX` above U+00FF
    /// (byte for byte like Java), then the date line.
    @Test func manifestHeaderIsJavaLatin1Comment() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await Self.run(Self.server(), dir)
        let data = try Data(contentsOf: dir.appendingPathComponent(".update-manifest.properties"))
        let firstLine = Array(data.prefix { $0 != 0x0A })
        // Built up in steps: one long `+` expression is something the older compiler (Xcode 16)
        // cannot type-check in time.
        var expected: [UInt8] = Array("#Hash naposledy sta\\u017Een".utf8)
        expected.append(0xFD)
        expected.append(contentsOf: Array("ch soubor\\u016F (lok".utf8))
        expected.append(0xE1)
        expected.append(contentsOf: Array("ln\\u011B upraven".utf8))
        expected.append(0xE9)
        expected.append(contentsOf: Array(" se nep\\u0159episuj".utf8))
        expected.append(contentsOf: [0xED, 0x29])
        #expect(firstLine == expected)
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        #expect(lines.count == 5)
        #expect(lines[1].first == UInt8(ascii: "#"))
        #expect(lines[4].isEmpty)
    }

    /// FAILED from downloading come in the report **before** the others; `isSafe`
    /// rejects `..`, a leading `/`, `\` and `:`. The parser message is our Czech one,
    /// the line and column Java's.
    @Test func downloadFailuresComeFirst() async throws {
        let fetcher = Self.server()
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        fetcher["contests/abc.yaml"] = "id: abc\nbands: ["
        fetcher["index.txt"] = "multipliers/dxcc_entities.yaml\ncontests/abc.yaml\ncontests/missing.yaml\n../etc/passwd\n/abs\na\\b\nc:d\n"
        let report = try await Self.run(fetcher, dir)
        let lines = Self.lines(report)
        #expect(Array(lines.prefix(6)) == [
            "contests/missing.yaml | FAILED | HTTP 404 pro " + Self.host + "/data/contests/missing.yaml",
            "../etc/passwd | FAILED | neplatná cesta",
            "/abs | FAILED | neplatná cesta",
            "a\\b | FAILED | neplatná cesta",
            "c:d | FAILED | neplatná cesta",
            "multipliers/dxcc_entities.yaml | NEW | ",
        ])
        #expect(lines.count == 7)
        #expect(lines[6].hasPrefix("contests/abc.yaml | FAILED | nevalidní definice: "), "\(lines[6])")
        // Java: "while parsing a flow node (řádek 2, sloupec 9)" — the end of the last
        // event (`[`).
        #expect(lines[6].hasSuffix(" (řádek 2, sloupec 9)"), "\(lines[6])")
        #expect(report.summary() == "nové 1, aktualizované 0, beze změny 0, ponechané lokální úpravy 0, chyby 6")
        #expect(try Self.manifestEntries(dir) == ["multipliers/dxcc_entities.yaml=" + Self.dxccHash])
    }

    /// C: an invalid definition carries the **first** finding, even if it is a WARNING
    /// (Java `issues.get(0)` — copied).
    @Test func invalidDefinitionReportsFirstIssueEvenWarning() async throws {
        let fetcher = Self.server()
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        fetcher["contests/abc.yaml"] = DefinitionEditing.template("abc", "ABC")
            .replacingOccurrences(of: "metadata:\n  name: \"ABC\"\n", with: "metadata:\n")
            .replacingOccurrences(of: "modes: [CW, SSB]\n", with: "")
        fetcher["index.txt"] = "contests/abc.yaml\n"
        var report = try await Self.run(fetcher, dir)
        #expect(Self.lines(report) == ["contests/abc.yaml | FAILED | nevalidní definice: chybí metadata.name"])

        fetcher["contests/zzz.yaml"] = DefinitionEditing.template("abc", "ABC")
            .replacingOccurrences(of: "set: dxcc_entities", with: "set: nope")
        fetcher["index.txt"] = "contests/zzz.yaml\nmultipliers/dxcc_entities.yaml\n"
        let second = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: second) }
        report = try await Self.run(fetcher, second)
        #expect(Self.lines(report) == [
            "contests/zzz.yaml | FAILED | nevalidní definice: id 'abc' se liší od názvu souboru 'zzz.yaml'",
            "multipliers/dxcc_entities.yaml | NEW | ",
        ])
    }

    /// C3: sets = `TreeSet` of local `multipliers/*.yaml` + stems of downloaded
    /// `multipliers/*.yaml` (also nested), sorted by UTF-16 and without duplicates.
    @Test func knownSetsAreLocalPlusDownloadedSorted() async throws {
        let fetcher = Self.server()
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        fetcher["contests/zzz.yaml"] = DefinitionEditing.template("zzz", "Z")
            .replacingOccurrences(of: "set: dxcc_entities", with: "set: nope")
        fetcher["multipliers/Zeta.yaml"] = "x"
        fetcher["multipliers/sub/deep.yaml"] = "x"
        fetcher["index.txt"] = "contests/zzz.yaml\nmultipliers/dxcc_entities.yaml\nmultipliers/Zeta.yaml\nmultipliers/sub/deep.yaml\n"
        let multipliers = dir.appendingPathComponent("multipliers")
        try FileManager.default.createDirectory(at: multipliers, withIntermediateDirectories: true)
        for name in ["local_set.yaml", "aaa.yaml", "dxcc_entities.yaml", "\u{E9}ta.yaml", "_u.yaml", "notyaml.txt"] {
            // POSIX `creat` with an NFC name like Java `Path`; `URL(fileURLWithPath:)`
            // would convert the name to NFD and `éta` would sort elsewhere.
            let descriptor = creat(RawFileSystem.javaPath(of: multipliers) + "/" + name, 0o644)
            #expect(descriptor >= 0)
            #expect(Darwin.write(descriptor, "x", 1) == 1)
            close(descriptor)
        }
        let report = try await Self.run(fetcher, dir)
        #expect(Self.lines(report) == [
            "contests/zzz.yaml | FAILED | nevalidní definice: multiplier 'countries' odkazuje na neexistující sadu 'nope'"
                + " (dostupné: Zeta, _u, aaa, dxcc_entities, local_set, sub/deep, \u{E9}ta)",
            "multipliers/dxcc_entities.yaml | SKIPPED_LOCAL_CHANGES | soubor je lokálně upravený",
            "multipliers/Zeta.yaml | NEW | ",
            "multipliers/sub/deep.yaml | NEW | ",
        ])
    }

    /// G: a definition referring to a set that arrives only in the downloaded files
    /// passes; without local and downloaded sets, references are not checked at all.
    @Test func downloadedSetsSatisfyReferences() async throws {
        let fetcher = Self.server()
        fetcher["contests/g.yaml"] = DefinitionEditing.template("g", "G")
            .replacingOccurrences(of: "set: dxcc_entities", with: "set: remote_only")
        fetcher["multipliers/remote_only.yaml"] = "whatever"
        fetcher["index.txt"] = "contests/g.yaml\nmultipliers/remote_only.yaml\n"
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Self.lines(try await Self.run(fetcher, dir)) == ["contests/g.yaml | NEW | ", "multipliers/remote_only.yaml | NEW | "])
        fetcher["index.txt"] = "contests/g.yaml\n"
        let second = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: second) }
        #expect(Self.lines(try await Self.run(fetcher, second)) == ["contests/g.yaml | NEW | "])
    }

    /// An index error brings down the whole `update` and writes nothing; a broken
    /// manifest (`\uXXXX`) does too — but only after the index.
    @Test func indexOrManifestFailureFailsWholeUpdate() async throws {
        let fetcher = Self.server()
        fetcher["index.txt"] = nil
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(await Self.updateError(fetcher, dir) == "HTTP 404 pro " + Self.host + "/data/index.txt")
        #expect(fetcher.requests == [Self.host + "/data/index.txt"])
        #expect(!Self.exists(dir, ".update-manifest.properties"))

        try Data("k=\\u12G4\n".utf8).write(to: dir.appendingPathComponent(".update-manifest.properties"))
        #expect(await Self.updateError(fetcher, dir) == "HTTP 404 pro " + Self.host + "/data/index.txt")
        fetcher["index.txt"] = "bandplan.yaml\n"
        fetcher["bandplan.yaml"] = "b"
        fetcher.requests = []
        #expect(await Self.updateError(fetcher, dir) == "Malformed \\uxxxx encoding.")
        #expect(fetcher.requests == [Self.host + "/data/index.txt"])
        #expect(!Self.exists(dir, "bandplan.yaml"))
    }

    /// E: a path that Java `URI.resolve` rejects (`IllegalArgumentException`)
    /// brings down the **whole** `update` — before writing anything, even if previous
    /// files were already downloaded. Index in UTF-16 units like Java.
    @Test func illegalUriCharacterFailsWholeUpdate() async throws {
        let cases: [(String, String)] = [
            ("contests/a b.yaml", "Illegal character in path at index 10: contests/a b.yaml"),
            ("contests/a%.yaml", "Malformed escape pair at index 10: contests/a%.yaml"),
            ("contests/a%zz.yaml", "Malformed escape pair at index 10: contests/a%zz.yaml"),
            ("contests/a|b.yaml", "Illegal character in path at index 10: contests/a|b.yaml"),
            ("contests/a\u{A0}b.yaml", "Illegal character in path at index 10: contests/a\u{A0}b.yaml"),
            ("contests/a[b.yaml", "Illegal character in path at index 10: contests/a[b.yaml"),
            ("contests/abc.yaml # komentář", "Illegal character in path at index 17: contests/abc.yaml # komentář"),
            ("contests/a\u{85}b.yaml", "Illegal character in path at index 10: contests/a\u{85}b.yaml"),
            ("contests/a^b.yaml", "Illegal character in path at index 10: contests/a^b.yaml"),
            ("contests/a\"b.yaml", "Illegal character in path at index 10: contests/a\"b.yaml"),
            ("contests/a{b.yaml", "Illegal character in path at index 10: contests/a{b.yaml"),
            ("contests/a`b.yaml", "Illegal character in path at index 10: contests/a`b.yaml"),
            ("contests/a<b.yaml", "Illegal character in path at index 10: contests/a<b.yaml"),
            // Beyond the probe: the query and fragment grammar of Java `URI`.
            ("😀/a b", "Illegal character in path at index 4: 😀/a b"),
            ("contests/x?a|b", "Illegal character in query at index 12: contests/x?a|b"),
            ("contests/a\u{2028}b", "Illegal character in path at index 10: contests/a\u{2028}b"),
            ("contests/a?b c", "Illegal character in query at index 12: contests/a?b c"),
            ("contests/a#b#c", "Illegal character in fragment at index 12: contests/a#b#c"),
        ]
        for (path, message) in cases {
            let fetcher = Self.server()
            fetcher["index.txt"] = "multipliers/dxcc_entities.yaml\n" + path + "\n"
            let dir = try Self.tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            #expect(await Self.updateError(fetcher, dir) == message, "\(path)")
            #expect(fetcher.requests == [Self.host + "/data/index.txt", Self.host + "/data/multipliers/dxcc_entities.yaml"])
            #expect(!Self.exists(dir, "multipliers") && !Self.exists(dir, ".update-manifest.properties"))
        }
    }

    /// E: paths that `URI.resolve` accepts. Requested URL = the Java request
    /// (normalisation of `./` and `//`, the fragment is not sent, non-ASCII in NFC and UTF-8
    /// percent-encoding), the message and report key carry the path from the index verbatim.
    @Test func acceptedUriPathsAreFetchedLikeJava() async throws {
        let cases: [(path: String, request: String, line: String)] = [
            ("contests/a%41.yaml", "/data/contests/a%41.yaml",
             "contests/a%41.yaml | FAILED | HTTP 404 pro \(Self.host)/data/contests/a%41.yaml"),
            ("contests/a#b.yaml", "/data/contests/a",
             "contests/a#b.yaml | FAILED | HTTP 404 pro \(Self.host)/data/contests/a#b.yaml"),
            ("contests/a?b.yaml", "/data/contests/a?b.yaml",
             "contests/a?b.yaml | FAILED | HTTP 404 pro \(Self.host)/data/contests/a?b.yaml"),
            ("contests/\u{E9}.yaml", "/data/contests/%C3%A9.yaml",
             "contests/\u{E9}.yaml | FAILED | HTTP 404 pro \(Self.host)/data/contests/\u{E9}.yaml"),
            ("contests/a\u{200B}b.yaml", "/data/contests/a%E2%80%8Bb.yaml",
             "contests/a\u{200B}b.yaml | FAILED | HTTP 404 pro \(Self.host)/data/contests/a\u{200B}b.yaml"),
            ("contests/😀.yaml", "/data/contests/%F0%9F%98%80.yaml",
             "contests/😀.yaml | FAILED | HTTP 404 pro \(Self.host)/data/contests/😀.yaml"),
            ("?q", "/data/?q", "?q | FAILED | HTTP 404 pro \(Self.host)/data/?q"),
            ("contests/./abc.yaml", "/data/contests/abc.yaml", "contests/./abc.yaml | NEW | "),
            ("contests//abc.yaml", "/data/contests/abc.yaml", "contests//abc.yaml | NEW | "),
        ]
        for (path, request, line) in cases {
            let fetcher = Self.server()
            fetcher["index.txt"] = "multipliers/dxcc_entities.yaml\n" + path + "\n"
            let dir = try Self.tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let report = try await Self.run(fetcher, dir)
            #expect(fetcher.requests.count == 3)
            #expect(fetcher.requests.last == Self.host + request, "\(path)")
            #expect(Self.lines(report).contains(line), "\(Self.lines(report))")
        }
        // The file from `contests/./abc.yaml` lies in `contests/abc.yaml`, the manifest key is verbatim.
        let fetcher = Self.server()
        fetcher["index.txt"] = "contests//abc.yaml\n"
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await Self.run(fetcher, dir)
        #expect(Self.exists(dir, "contests/abc.yaml"))
        #expect(try Self.manifestEntries(dir) == ["contests//abc.yaml=" + Self.abcHash])
    }

    /// L: NFC and NFD variants of the same path are two paths for Java (`String.equals`),
    /// both are downloaded (request in NFC), on APFS they point to the same file.
    @Test func canonicallyEquivalentPathsStayDistinct() async throws {
        let fetcher = Self.server()
        fetcher["multipliers/\u{E9}.yaml"] = "same"
        fetcher["index.txt"] = "multipliers/\u{E9}.yaml\nmultipliers/e\u{301}.yaml\n"
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = try await Self.run(fetcher, dir)
        #expect(report.files.count == 2)
        #expect(report.files.map(\.path).map { Array($0.utf16) } == [Array("multipliers/\u{E9}.yaml".utf16),
                                                                      Array("multipliers/e\u{301}.yaml".utf16)])
        #expect(report.files.map(\.status) == [.new, .unchanged])
        #expect(fetcher.requests.dropFirst() == [Self.host + "/data/multipliers/%C3%A9.yaml",
                                                 Self.host + "/data/multipliers/%C3%A9.yaml"])
        #expect(try Self.manifestEntries(dir).count == 2)
    }

    /// F, F2: index lines like Java `lines()` + `strip()` (BOM stays,
    /// U+2028 and U+3000 are trimmed) + without empty ones and `#`.
    @Test func indexLinesLikeJava() async throws {
        #expect(DefinitionUpdater.indexLines("\u{FEFF}m/a\r\n  c/b  \r\n\u{3000}# c\r\n\r\n   \n\u{2028}x\n")
                == ["\u{FEFF}m/a", "c/b", "x"])
        #expect(DefinitionUpdater.indexLines("a\rb") == ["a", "b"])
        #expect(DefinitionUpdater.indexLines("a\r\n\r\nb\n\n") == ["a", "b"])

        let fetcher = Self.server()
        fetcher["index.txt"] = "\u{FEFF}multipliers/dxcc_entities.yaml\r\n  contests/abc.yaml  \r\n\u{3000}# c\r\n\r\n   \n\u{2028}x\n"
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Self.lines(try await Self.run(fetcher, dir)) == [
            "\u{FEFF}multipliers/dxcc_entities.yaml | FAILED | HTTP 404 pro \(Self.host)/data/\u{FEFF}multipliers/dxcc_entities.yaml",
            "x | FAILED | HTTP 404 pro \(Self.host)/data/x",
            "contests/abc.yaml | NEW | ",
        ])
        #expect(fetcher.requests[1] == Self.host + "/data/%EF%BB%BFmultipliers/dxcc_entities.yaml")
    }

    /// A duplicate index line is downloaded twice, appears once in the report
    /// (Java `LinkedHashMap` — position of the first occurrence).
    @Test func duplicateIndexLineReportedOnce() async throws {
        let fetcher = Self.server()
        fetcher["index.txt"] = "contests/abc.yaml\ncontests/abc.yaml\nmultipliers/dxcc_entities.yaml\n"
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Self.lines(try await Self.run(fetcher, dir)) == ["contests/abc.yaml | NEW | ", "multipliers/dxcc_entities.yaml | NEW | "])
        #expect(fetcher.requests.count == 4)
    }

    /// I: `bandplan.yaml` and nested paths outside `contests/*.yaml` are not validated;
    /// a nested definition is checked with id `sub/n` (and passes with a warning only).
    @Test func onlyContestDefinitionsAreValidated() async throws {
        let fetcher = Self.server()
        fetcher["bandplan.yaml"] = "garbage: ["
        fetcher["contests/sub/n.yaml"] = DefinitionEditing.template("n", "N")
        fetcher["index.txt"] = "bandplan.yaml\ncontests/sub/n.yaml\nmultipliers/dxcc_entities.yaml\n"
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Self.lines(try await Self.run(fetcher, dir))
                == ["bandplan.yaml | NEW | ", "contests/sub/n.yaml | NEW | ", "multipliers/dxcc_entities.yaml | NEW | "])
        #expect(try Self.read(dir, "bandplan.yaml") == "garbage: [")
    }

    /// J: foreign manifest keys stay and the write sorts them by key
    /// (JDK 18+ `Properties.store`; inventory 3.8 says "by hash" — a mistake).
    @Test func manifestKeepsForeignKeysSorted() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("zzz=1\n aaa : 2\n".utf8).write(to: dir.appendingPathComponent(".update-manifest.properties"))
        let fetcher = Self.server()
        fetcher["index.txt"] = "multipliers/dxcc_entities.yaml\ncontests/abc.yaml\n"
        _ = try await Self.run(fetcher, dir)
        #expect(try Self.manifestEntries(dir) == ["aaa=2", "contests/abc.yaml=" + Self.abcHash,
                                                  "multipliers/dxcc_entities.yaml=" + Self.dxccHash, "zzz=1"])
    }

    /// A manifest written by **Java** (fixture from `Properties.store`): a local file
    /// with the hash from the manifest is updated, another one is kept.
    @Test func manifestWrittenByJavaIsHonoured() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixtures = try #require(Bundle.module.url(forResource: "java-properties", withExtension: nil))
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("store-jdk21.properties"),
                                         to: dir.appendingPathComponent(".update-manifest.properties"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("contests"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("multipliers"), withIntermediateDirectories: true)
        try Data(DefinitionEditing.template("abc", "ABC").utf8).write(to: dir.appendingPathComponent("contests/abc.yaml"))
        try Data("lokální".utf8).write(to: dir.appendingPathComponent("multipliers/dxcc_entities.yaml"))
        let fetcher = Self.server()
        fetcher["contests/abc.yaml"] = DefinitionEditing.template("abc", "ABC v2")
        let report = try await Self.run(fetcher, dir)
        #expect(report.files.map(\.status) == [.updated, .skippedLocalChanges])
        // The other pairs of the Java manifest (even those with special characters) survive.
        let manifest = try JavaProperties.load(Data(contentsOf: dir.appendingPathComponent(".update-manifest.properties")))
        #expect(manifest.count == 17)
        #expect(manifest["k=eq"] == "=:#!")
        #expect(manifest["contests/abc.yaml"] == "cbb2dc3315ab65ee95ef2cf79f974633a0230d46ba937a8ceed69a0ce54b6ec8")
    }

    /// K, K2: the target is a directory → `IOException("Is a directory")`, the parent is a file →
    /// `FileAlreadyExistsException(<parent>)`; the whole `update` fails, what was written
    /// before the error stays, the manifest is not saved.
    @Test func localFileSystemErrorsFailWholeUpdate() async throws {
        let fetcher = Self.server()
        fetcher["bandplan.yaml"] = "b"
        fetcher["index.txt"] = "multipliers/dxcc_entities.yaml\ncontests/abc.yaml\nbandplan.yaml\n"
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("contests/abc.yaml"), withIntermediateDirectories: true)
        #expect(await Self.updateError(fetcher, dir) == "Is a directory")
        #expect(Self.exists(dir, "multipliers/dxcc_entities.yaml"))
        #expect(!Self.exists(dir, "bandplan.yaml") && !Self.exists(dir, ".update-manifest.properties"))

        let dir2 = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir2) }
        try Data("file".utf8).write(to: dir2.appendingPathComponent("contests"))
        #expect(await Self.updateError(fetcher, dir2) == RawFileSystem.javaPath(of: dir2) + "/contests")

        fetcher["contests/sub/x.yaml"] = DefinitionEditing.template("x", "X")
        fetcher["index.txt"] = "contests/sub/x.yaml\n"
        #expect(await Self.updateError(fetcher, dir2) == RawFileSystem.javaPath(of: dir2) + "/contests/sub: Not a directory")
    }

    /// A root without a trailing `/` is completed; the written file has permissions 0600
    /// like Java `createTempFile`.
    @Test func baseWithoutSlashAndFileMode() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fetcher = Self.server()
        _ = try await Self.run(fetcher, dir, base: URL(string: Self.host + "/data")!)
        #expect(fetcher.requests.first == Self.host + "/data/index.txt")
        let attributes = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("contests/abc.yaml").path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("contests").path)
        #expect(leftovers == ["abc.yaml"])
    }

    @Test func isSafeRejectsEscapes() {
        #expect(!DefinitionUpdater.isSafe("../etc/passwd"))
        #expect(!DefinitionUpdater.isSafe("a..b"))
        #expect(!DefinitionUpdater.isSafe("/abs"))
        #expect(!DefinitionUpdater.isSafe("a\\b"))
        #expect(!DefinitionUpdater.isSafe("c:d"))
        #expect(DefinitionUpdater.isSafe(""))
        #expect(DefinitionUpdater.isSafe("ok/x"))
        #expect(DefinitionUpdater.isSafe("a/.b/c"))
    }

    @Test func sha256IsLowercaseHex() {
        #expect(DefinitionUpdater.sha256(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(DefinitionUpdater.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func defaultBaseAndStatusNames() {
        #expect(DefinitionUpdater.defaultBase.absoluteString
                == "https://raw.githubusercontent.com/ok1xoe/MacContestLogger/main/contest-data/")
        #expect(DefinitionUpdater.Status.allCases.map(\.rawValue)
                == ["NEW", "UPDATED", "UNCHANGED", "SKIPPED_LOCAL_CHANGES", "FAILED"])
    }
}
