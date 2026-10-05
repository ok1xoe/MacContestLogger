import Foundation
import Testing
@testable import MCLCore

/// Swift side of the Java parity suite (maintainer-only probe, fixture `c`): replays the input rows of `ui-c-java.json.gz` against
/// the core steps the app model runs for import, merge, the exports, configuration profiles and printing:
///
/// - `imp.READ` — the steps of `ImportExportModel.importQsos`/`merge` over an in-memory logbook: `LogImporter`
///   (`readText`, `importFormat`/`mergeFormat`, `read`, `prepareImport`/`applyExchange`, `readDatabase`,
///   `prepareMerge`), `LogbookService.log`, the `IoTexts` status texts. Where Kotlin crashes on import (a reader
///   or an exchange error), the row is `THROW <class>: <message>` from `JavaThrowables.describe` — the app shows
///   "Nelze přečíst soubor" there instead, the gate compares the message;
/// - `exp.FILES` — `ExportJobs.edi`/`other` + `ExportJobs.write`, `AdifWriter.writeToFile`, `IoTexts`;
/// - `prof.MERGE` — `ProfileMerge.merge`, the configuration encoded as `ProfileMerge.fields(of:)` and
///   canonicalized as the generator does; `ProfileMerge.isValidName`; `ConfigProfiles.list`;
/// - `print.PAGE` — `PrintLayout.linesPerPage` and `PrintLayout.pages`.
///
/// The `defs` input row and the `file:` content rows of `imp.READ` (an edge file of `Fixtures/io-edge/` by name and
/// SHA-256) are not copied from the reference: Swift builds them from its own files, so a changed definition or edge
/// file asks for regeneration instead of a mismatch. Temporary files live in a directory of the item, removed at
/// the end; texts naming it carry `<dir>`.
enum UiParityCSections {

    typealias Entry = JavaYamlParityTests.ReferenceFile
    typealias Rows = [(String, [String])]
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture

    /// `ProfileMerge.fields(of:)` without the Swift-only keys (`ProfileMergeSchema.swiftOnlyProperties`): the
    /// configuration as v1.1.1 would write it, for comparing with the Java reference.
    static func javaFields(of config: AppConfig) throws -> [String: ProfileJson] {
        var fields = try ProfileMerge.fields(of: config)
        for property in ProfileMergeSchema.swiftOnlyProperties.values.joined() {
            fields[property.name] = nil
        }
        return fields
    }

    static let names: [String] = ["imp.READ", "exp.FILES", "prof.MERGE", "print.PAGE"]

    /// The log's active contest (`IoSections.ACTIVE`).
    static let active = "gate-c"
    /// 2026-10-02T00:00:00Z, the fixed clock of the logbook.
    static let baseMillis: Int64 = 1_790_899_200_000
    /// Files up to this size go out whole (`IoSections.SHORT_FILE`).
    static let shortFile = 400

    // MARK: - replay

    final class Ctx {
        let environment: UiParitySections.Environment
        let work: URL
        let edge: URL

        init(_ environment: UiParitySections.Environment, work: URL, edge: URL) {
            self.environment = environment
            self.work = work
            self.edge = edge
        }
    }

    static func replay(_ java: Entry, _ environment: UiParitySections.Environment) throws -> Entry {
        let manager = FileManager.default
        let work: URL = manager.temporaryDirectory.appendingPathComponent("ui-c-gate-" + UUID().uuidString)
        try manager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: work) }
        let edge = try #require(Bundle.module.url(forResource: "io-edge", withExtension: nil))
        let ctx = Ctx(environment, work: work, edge: edge)
        var lines: [String] = []
        lines.reserveCapacity(java.lines.count)
        for line in java.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count >= 2, fields[1] == "in" else { continue }
            if fields[0] == "defs" {
                lines.append(environment.defsRow(for: java.relative))
                continue
            }
            var inputs: [String] = Array(fields.dropFirst(2))
            if java.relative == "imp.READ", fields[0].hasPrefix("i/"), inputs.count == 3,
               inputs[2].hasPrefix("file:") {
                inputs[2] = try ownEdgeSpec(inputs[2], ctx)
                lines.append(F.line(fields[0], "in", inputs))
            } else {
                lines.append(line)
            }
            do {
                for (outPath, out) in try compute(java.relative, fields[0], inputs, ctx) {
                    lines.append(F.line(outPath, "out", out))
                }
            } catch {
                lines.append(F.line(fields[0], "out", ["SWIFT ERROR", String(describing: error)]))
            }
        }
        let sum: String = F.checksum(definition: nil, registry: "", lines: lines)
        return Entry(relative: java.relative, sha256: sum, lines: lines)
    }

    static func replayAll(_ reference: [Entry]) async throws -> [Entry] {
        let environment = try UiParitySections.Environment.load()
        return try await withThrowingTaskGroup(of: (Int, Entry).self) { group in
            for (index, entry) in reference.enumerated() {
                group.addTask {
                    let replayed = try await JavaNetParityFixture.onGateThread(entry.relative) {
                        try replay(entry, environment)
                    }
                    return (index, replayed)
                }
            }
            var results = [Entry?](repeating: nil, count: reference.count)
            for try await (index, entry) in group {
                results[index] = entry
            }
            return results.compactMap { $0 }
        }
    }

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        switch name {
        case "imp.READ":
            return path.hasPrefix("i/") ? try importRow(path, f, ctx) : try mergeRow(path, f, ctx)
        case "exp.FILES": return try exportRow(path, f, ctx)
        case "prof.MERGE": return try profileRow(path, f, ctx)
        case "print.PAGE": return try printRow(path, f)
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    // MARK: - shared

    /// `<dir>` instead of the directory.
    static func hide(_ text: String, _ dir: URL) -> String {
        text.replacingOccurrences(of: dir.path, with: "<dir>")
    }

    /// A text naming a file, composed (NFC): Foundation file URLs decompose file names (`M.ADİ` →
    /// `M.ADI` + U+0307, `Ž` → `Z` + U+030C), so the app shows and writes them decomposed where the JDK keeps the
    /// composed name — the same name on macOS file systems, a different UTF-16 text (known divergences).
    static func composed(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
    }

    /// `THROW <simple class name>: <message>` (the generator's `UiRefGen.thrown`).
    static func thrown(_ error: any Error) -> String {
        let described = JavaThrowables.describe(error)
        let simple: String = described.javaClass.split(separator: ".").last.map(String.init) ?? described.javaClass
        return "THROW " + simple + ": " + IoTexts.template(ProfileMergeJavaParityTests.withoutSwiftOnlyCount(described.message) ?? described.message)
    }

    static func date(_ field: String) throws -> Date? {
        field == "~" ? nil : Date(timeIntervalSince1970: Double(try X.int64(field)) / 1000)
    }

    static func millis(_ date: Date?) -> String {
        guard let date else { return "~" }
        return String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }

    static func optionalInt(_ field: String) throws -> Int? {
        field == "~" ? nil : try X.int(field)
    }

    static func intText(_ value: Int?) -> String {
        value.map { String($0) } ?? "~"
    }

    static func hexBytes(_ hex: Substring) throws -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { throw X.Malformed(text: String(hex)) }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    /// A QSO spec of 15 fields (`IoSections.Spec`).
    static func qso(_ f: ArraySlice<String>) throws -> Qso {
        let v: [String] = Array(f)
        guard v.count == 15 else { throw X.Malformed(text: "QSO spec \(v)") }
        var q = Qso()
        q.timestampUtc = try date(v[0])
        q.call = X.text(v[1]) ?? ""
        q.freqHz = try X.int(v[2])
        if v[3] != "~" {
            q.band = Band.from(adif: v[3])
        }
        if v[4] != "~" {
            q.mode = Mode(rawValue: v[4])
        }
        q.rstSent = X.text(v[5]) ?? ""
        q.rstRcvd = X.text(v[6]) ?? ""
        q.serialSent = try optionalInt(v[7])
        q.serialRcvd = try optionalInt(v[8])
        q.exchangeSent = X.text(v[9]) ?? ""
        q.exchangeRcvd = X.text(v[10]) ?? ""
        q.comment = X.text(v[11]) ?? ""
        q.operator = X.text(v[12]) ?? ""
        q.dxccName = X.text(v[13]) ?? ""
        q.xqso = v[14] == "1"
        return q
    }

    /// A stored QSO field by field (`IoSections.qsoFields`).
    static func qsoFields(_ position: Int, _ q: Qso) -> [String] {
        [
            String(position), millis(q.timestampUtc), F.tx(q.call), String(q.freqHz), q.band?.adif ?? "~",
            q.mode?.rawValue ?? "~", F.tx(q.rstSent), F.tx(q.rstRcvd), intText(q.serialSent), intText(q.serialRcvd),
            F.tx(q.exchangeSent), F.tx(q.exchangeRcvd), String(q.points), X.b(q.multiplier), q.runMode.rawValue,
            F.tx(q.operator), F.tx(q.comment), intText(q.dxccEntity), F.tx(q.dxccName), F.tx(q.continent),
            F.tx(q.stationId), String(q.version), millis(q.updatedAtUtc), X.b(q.deleted), X.b(q.xqso),
            F.tx(q.contestId),
        ]
    }

    static func logRows(_ path: String, _ service: LogbookService) throws -> Rows {
        var rows: Rows = []
        for (index, q) in try service.findAll().enumerated() {
            rows.append((path + "/q/" + pad(index, 3), qsoFields(index, q)))
        }
        return rows
    }

    static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    static func logbook() throws -> LogbookService {
        let fixed = Date(timeIntervalSince1970: Double(baseMillis) / 1000)
        let service = LogbookService(repository: try LogbookRepository.inMemory(), now: { fixed })
        service.activeContestId = active
        return service
    }

    /// The runtime of a context: a definition id (active under `active`), `-` inactive with DXCC, `nodxcc`
    /// inactive without DXCC.
    static func runtime(_ context: String, _ environment: UiParitySections.Environment) throws -> ContestRuntime {
        // the catalog already loaded (the convenience initializer would parse all definitions for every case)
        let catalog: [ContestDefinition] = environment.contests.map(\.definition)
        let dxcc: (any DxccLookup)? = context == "nodxcc" ? nil : environment.dxcc
        let runtime = ContestRuntime(dxcc: dxcc, registry: environment.registry, available: catalog,
                                     contestsDir: environment.contestsDir, myCall: { UiParitySections.myCall })
        if context == "nodxcc" {
            return runtime
        }
        if context != "-" {
            if let error = runtime.activate(contestId: active, definition: try environment.contest(id: context)) {
                throw X.Malformed(text: "activation of \(context): \(error.czech)")
            }
        }
        return runtime
    }

    /// The received fields of a call from a fresh session (the app's `ExchangeSource`).
    static func fields(_ runtime: ContestRuntime) -> (String) throws -> [ContestDefinition.ExchangeField] {
        let session: ContestSession? = runtime.definition == nil ? nil : runtime.freshSession()
        return { call in try session?.activeReceivedFields(call: call) ?? [] }
    }

    // MARK: - imp.READ

    /// `file:<name>:<sha>` built from Swift's own copy of the edge file.
    static func ownEdgeSpec(_ spec: String, _ ctx: Ctx) throws -> String {
        let parts = spec.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw X.Malformed(text: spec) }
        let data = try Data(contentsOf: ctx.edge.appendingPathComponent(String(parts[1])))
        return "file:" + parts[1] + ":" + JavaYamlParityTests.sha256Hex(data)
    }

    static func content(_ spec: String, _ ctx: Ctx) throws -> Data {
        if spec.hasPrefix("hex:") {
            return try hexBytes(spec.dropFirst(4))
        }
        let parts = spec.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "file" else { throw X.Malformed(text: spec) }
        return try Data(contentsOf: ctx.edge.appendingPathComponent(String(parts[1])))
    }

    /// `i/NNN`: context, file name, content.
    static func importRow(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        guard f.count == 3 else { throw X.Malformed(text: "\(path) \(f)") }
        let name: String = X.text(f[1]) ?? ""
        let dir: URL = ctx.work.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file: URL = dir.appendingPathComponent(name)
        try content(f[2], ctx).write(to: file)
        let service: LogbookService = try logbook()
        let runtime: ContestRuntime = try runtime(f[0], ctx.environment)
        let status: String = importStatus(file, runtime: runtime, service: service)
        return [(path, [F.tx(composed(hide(status, dir)))])] + (try logRows(path, service))
    }

    static func importStatus(_ file: URL, runtime: ContestRuntime, service: LogbookService) -> String {
        let fileName: String = file.lastPathComponent
        let text: String
        do {
            text = try LogImporter.readText(file)
        } catch {
            return IoTexts.unreadable(file: fileName).czech
        }
        let format: LogImporter.Format = LogImporter.importFormat(fileName: fileName, content: text)
        do {
            let qsos: [Qso] = try LogImporter.read(format, content: text)
            let prepared: [Qso] = try LogImporter.prepareImport(qsos, definition: runtime.definition,
                                                                fields: fields(runtime), dxcc: runtime.dxccLookup)
            for var q in prepared {
                try service.log(&q)
            }
            return IoTexts.imported(count: qsos.count, format: format, file: fileName).czech
        } catch {
            return thrown(error)
        }
    }

    /// `m/NNN`: context, the existing log, file name, kind, then the foreign database or the content.
    static func mergeRow(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        var at = 0
        let context: String = f[at]
        at += 1
        let existingCount: Int = try X.int(f[at])
        at += 1
        let service: LogbookService = try logbook()
        for _ in 0..<existingCount {
            var q: Qso = try qso(f[at..<(at + 15)])
            try service.log(&q)
            at += 15
        }
        let name: String = X.text(f[at]) ?? ""
        let kind: String = f[at + 1]
        at += 2
        let dir: URL = ctx.work.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file: URL = dir.appendingPathComponent(name)
        switch kind {
        case "db0", "db1", "db2":
            let count: Int = try X.int(f[at])
            at += 1
            let foreign = try LogbookRepository(url: file)
            for _ in 0..<count {
                let contestId: String = X.text(f[at]) ?? ""
                var q: Qso = try qso(f[(at + 1)..<(at + 16)])
                q.contestId = contestId
                _ = try foreign.insert(&q)
                at += 16
            }
            foreign.close()
        case "db-text":
            try Data("not a database\n".utf8).write(to: file)
        case "db-directory":
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        case "db-missing":
            break
        default:
            guard f[at].hasPrefix("hex:") else { throw X.Malformed(text: f[at]) }
            try hexBytes(f[at].dropFirst(4)).write(to: file)
        }
        let runtime: ContestRuntime = try runtime(context, ctx.environment)
        let status: String = mergeStatus(file, runtime: runtime, service: service)
        return [(path, [F.tx(composed(hide(status, dir)))])] + (try logRows(path, service))
    }

    static func mergeStatus(_ file: URL, runtime: ContestRuntime, service: LogbookService) -> String {
        let fileName: String = file.lastPathComponent
        let active: String = service.activeContestId
        let incoming: [Qso]
        do {
            if LogImporter.isDatabase(fileName: fileName) {
                incoming = try LogImporter.readDatabase(at: file, activeContestId: active)
            } else {
                let text: String = try LogImporter.readText(file)
                let format: LogImporter.Format = LogImporter.mergeFormat(fileName: fileName, content: text)
                let qsos: [Qso] = try LogImporter.read(format, content: text)
                incoming = try LogImporter.applyExchange(qsos, definition: runtime.definition, fields: fields(runtime))
            }
        } catch {
            return IoTexts.mergeUnreadable(file: fileName, message: JavaThrowables.describe(error).message).czech
        }
        do {
            let existing: [Qso] = try service.findAll()
            let merged = LogImporter.prepareMerge(existing: existing, incoming: incoming, activeContestId: active,
                                                  dxcc: runtime.dxccLookup)
            for var q in merged.toAdd {
                try service.log(&q)
            }
            return IoTexts.merged(file: fileName, added: merged.toAdd.count, skipped: merged.duplicates).czech
        } catch {
            return thrown(error)
        }
    }

    // MARK: - exp.FILES

    /// `e/NNN`: definition id or `-`, 12 station fields, the setup (category, operators, soapbox), the log.
    static func exportRow(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        guard f.count >= 17 else { throw X.Malformed(text: "\(path) \(f)") }
        var station = StationConfig()
        let s: [String] = f[1...12].map { X.text($0) ?? "" }
        station.call = s[0]
        station.gridSquare = s[1]
        station.power = s[2]
        station.antenna = s[3]
        station.name = s[4]
        station.address1 = s[5]
        station.address2 = s[6]
        station.city = s[7]
        station.country = s[8]
        station.club = s[9]
        station.email = s[10]
        station.operator = s[11]
        let category: String = X.text(f[13]) ?? ""
        var setup: ContestSetup?
        if category != "none" {
            var made = ContestSetup()
            if category != "missing" {
                made.category["OPERATOR"] = category
            }
            made.category["MODE"] = "CW"
            made.operators = X.text(f[14]) ?? ""
            made.soapbox = X.text(f[15]) ?? ""
            setup = made
        }
        let count: Int = try X.int(f[16])
        let service: LogbookService = try logbook()
        var at = 17
        for _ in 0..<count {
            var q: Qso = try qso(f[at..<(at + 15)])
            try service.log(&q)
            at += 15
        }
        let qsos: [Qso] = try service.findAll()
        let runtime: ContestRuntime = try runtime(f[0], ctx.environment)
        let definition: ContestDefinition? = runtime.definition
        let base: URL = ctx.work.appendingPathComponent(path, isDirectory: true)

        var rows: Rows = []
        rows += try exported(path + "/edi", base.appendingPathComponent("edi")) { dir in
            let built = try ExportJobs.edi(definition: definition, station: station, setup: setup, qsos: qsos,
                                           fields: fields(runtime))
            switch built {
            case .failure(let message):
                return message.czech
            case .success(let files):
                return IoTexts.ediWritten(names: ExportJobs.write(files, to: dir), dir: dir.path).czech
            }
        }
        rows += try exported(path + "/other", base.appendingPathComponent("other")) { dir in
            let name: String = definition?.metadata?.name ?? IoTexts.defaultLogName
            var score: ScoreState?
            if runtime.isActive, let session = runtime.freshSession() {
                score = try ContestReplay.replay(session, qsos).session.score()
            }
            let files: [ExportFile] = try ExportJobs.other(contestName: name, call: station.call, score: score,
                                                           qsos: qsos)
            return IoTexts.otherWritten(names: ExportJobs.write(files, to: dir), dir: dir.path).czech
        }
        rows += try exported(path + "/adif", base.appendingPathComponent("adif")) { dir in
            let target: URL = dir.appendingPathComponent("log.adi")
            try AdifWriter(contestId: definition?.cabrillo?.contestName)
                .writeToFile(qsos, station: station.toStation(), to: target)
            return ContestMessage("Exportováno do %s", .string(target.path)).czech
        }
        return rows
    }

    /// Runs an export into a fresh directory: the status (or THROW) and every file written, sorted by name.
    static func exported(_ path: String, _ dir: URL, _ body: (URL) throws -> String) throws -> Rows {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let status: String
        do {
            status = try body(dir)
        } catch {
            status = thrown(error)
        }
        var rows: Rows = [(path, [F.tx(hide(status, dir))])]
        let stored: [String] = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let names: [(stored: String, shown: String)] = stored.map { ($0, composed($0)) }.sorted { a, b in
            a.shown.utf16.lexicographicallyPrecedes(b.shown.utf16)
        }
        for (storedName, name) in names {
            let bytes = try Data(contentsOf: dir.appendingPathComponent(storedName))
            let whole: String = bytes.count <= shortFile ? F.tx(units: bytes.map { UInt16($0) }) : "~"
            rows.append((path + "/" + F.tx(name), [String(bytes.count), JavaYamlParityTests.sha256Hex(bytes), whole]))
        }
        return rows
    }

    // MARK: - prof.MERGE

    static func profileRow(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if path.hasPrefix("v/") {
            let name = String(decoding: F.untxUnits(f[0]), as: UTF16.self)
            return [(path, [X.b(ProfileMerge.isValidName(name))])]
        }
        if path.hasPrefix("l/") {
            let dir: URL = ctx.work.appendingPathComponent(path == "l/missing" ? "no-such-directory" : path)
            if path != "l/missing" {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let count: Int = try X.int(f[0])
                for index in 0..<count {
                    try Data("{}".utf8).write(to: dir.appendingPathComponent(X.text(f[1 + index]) ?? ""))
                }
            }
            return [(path, ConfigProfiles<AppConfig>(dir: dir).list().map { F.tx($0) })]
        }
        let base = Data((X.text(f[0]) ?? "").utf8)
        let profile = Data((X.text(f[1]) ?? "").utf8)
        let out: String
        do {
            let current: AppConfig = try ProfileMerge.merge(current: AppConfig(), profileData: base)
            let merged: AppConfig = try ProfileMerge.merge(current: current, profileData: profile)
            out = canonical(.object(try javaFields(of: merged)))
        } catch {
            out = thrown(error)
        }
        return [(path, [F.tx(out)])]
    }

    /// The generator's canonical JSON (`IoSections.canonical`).
    static func canonical(_ json: ProfileJson) -> String {
        switch json {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .int(let value):
            return String(value)
        case .double(let value):
            if value == value.rounded(), abs(value) < 1e15 {
                return String(Int64(value))
            }
            return "d:" + String(value.bitPattern, radix: 16)
        case .string(let text):
            return quoted(text)
        case .array(let items):
            return "[" + items.map(canonical).joined(separator: ",") + "]"
        case .object(let fields):
            let keys: [String] = fields.keys.filter { fields[$0] != .null }.sorted { a, b in
                a.utf16.lexicographicallyPrecedes(b.utf16)
            }
            let members: [String] = keys.map { key in quoted(key) + ":" + canonical(fields[key] ?? .null) }
            return "{" + members.joined(separator: ",") + "}"
        }
    }

    static func quoted(_ text: String) -> String {
        let escaped: String = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return "'" + escaped + "'"
    }

    // MARK: - print.PAGE

    /// `p/NNN`: title, text, imageable height (bits of the double in hex).
    static func printRow(_ path: String, _ f: [String]) throws -> Rows {
        guard f.count == 3, let bits = UInt64(f[2], radix: 16) else { throw X.Malformed(text: "\(path) \(f)") }
        let height = Double(bitPattern: bits)
        let title: String = X.text(f[0]) ?? ""
        let text: String = X.text(f[1]) ?? ""
        let pages: [PrintLayout.Page] = PrintLayout.pages(text: text, title: title, imageableHeight: height)
        var rows: Rows = [(path, [String(PrintLayout.linesPerPage(imageableHeight: height)), String(pages.count)])]
        for (index, page) in pages.enumerated() {
            var drawn: [String] = []
            for line in page.lines + [page.footer] {
                drawn.append(String(line.y))
                drawn.append(F.tx(line.text))
            }
            rows.append((path + "/" + pad(index, 2), drawn))
        }
        return rows
    }
}
