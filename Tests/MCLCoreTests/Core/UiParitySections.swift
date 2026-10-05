import Foundation
import Testing
@testable import MCLCore

/// Swift side of the Java parity suite (maintainer-only probe): replays the input rows of `ui-a-java.json.gz` against the logic the
/// GUI work moved from the Kotlin UI into the core — `ContestRuntime` (`ctl.RUN`), `SentExchange` (`sent.EXCH`),
/// `FrequencyText` and `BandRows` (`freq.PARSE`), `ContestActivation.parseEpoch` (`act.EPOCH`) and
/// `ExportNames.cabrilloFileName` (`name.CAB`).
///
/// The `defs` input row is not copied from the reference: Swift builds it from its own bundle (registry digest and
/// the SHA-256 of every definition file), so an added, removed or edited definition changes the input checksum and
/// the gate reports "REGENERATE REFERENCE" instead of a mismatch.
enum UiParitySections {

    typealias Entry = JavaYamlParityTests.ReferenceFile
    typealias Rows = [(String, [String])]
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture

    static let names: [String] = ["ctl.RUN", "sent.EXCH", "freq.PARSE", "act.EPOCH", "name.CAB"]

    static let myCall = "OK1XOE"

    /// A definition file of the gate: name relative to the fixtures (`contests/x.yaml`), SHA-256, parsed definition.
    struct Definition {
        let file: String
        let sha: String
        let definition: ContestDefinition
    }

    /// The environment shared by all items (read-only after creation).
    struct Environment: @unchecked Sendable {
        let dxcc: DxccResolver
        let registry: MultiplierSetRegistry
        let registryDigest: String
        let contestsDir: URL
        let contests: [Definition]
        let sentDefinitions: [Definition]

        static func load() throws -> Environment {
            let engine = try JavaEngineParityTests.environment()
            let contestsDir: URL = try ContestDataLayoutTests.contestDataRoot().appendingPathComponent("contests")
            var contests: [Definition] = []
            for name in try JavaDefinitionParityTests.sortedNames(in: contestsDir, suffix: ".yaml") {
                contests.append(try definition("contests/" + name, contestsDir.appendingPathComponent(name)))
            }
            let synthetic = try #require(Bundle.module.url(forResource: "session-gate-synthetic", withExtension: nil))
            var sent: [Definition] = contests
            for name in ["bonus.yaml", "qtc-tour.yaml"] {
                sent.append(try definition("session-gate-synthetic/" + name, synthetic.appendingPathComponent(name)))
            }
            return Environment(dxcc: engine.dxcc, registry: engine.registry, registryDigest: engine.registryDigest,
                               contestsDir: contestsDir, contests: contests, sentDefinitions: sent)
        }

        static func definition(_ file: String, _ url: URL) throws -> Definition {
            let data = try Data(contentsOf: url)
            return Definition(file: file, sha: JavaYamlParityTests.sha256Hex(data),
                              definition: try ContestDefinitionLoader.loadFile(url))
        }

        /// The definitions an item depends on (`defs` row).
        func definitions(for item: String) -> [Definition] {
            item == "sent.EXCH" ? sentDefinitions : contests
        }

        /// The `defs` input row as the generator writes it, from the files Swift sees.
        func defsRow(for item: String) -> String {
            let defs: [Definition] = definitions(for: item)
            var fields: [String] = [registryDigest, String(defs.count)]
            for d in defs {
                fields.append(d.file)
                fields.append(d.sha)
            }
            return F.line("defs", "in", fields)
        }

        func runtime(dxcc: (any DxccLookup)?) -> ContestRuntime {
            ContestRuntime(dxcc: dxcc, registry: registry, contestsDir: contestsDir, myCall: { UiParitySections.myCall })
        }

        func contest(id: String) throws -> ContestDefinition {
            guard let found = contests.first(where: { $0.definition.id == id }) else {
                throw X.Malformed(text: "no definition \(id)")
            }
            return found.definition
        }
    }

    /// State of one item between its rows (the live runtime of `ctl.RUN` and the stored QSOs of its definition).
    final class Ctx {
        let environment: Environment
        var runtime: ContestRuntime?
        var definitionId: String = ""
        var log: [Qso] = []

        init(_ environment: Environment) {
            self.environment = environment
        }
    }

    // MARK: - replay

    /// Replays an item: after each input row of the reference the outputs computed by Swift; the `defs` row is
    /// Swift's own. A Swift error at a row = the output row `SWIFT ERROR`, not a crash of the whole gate.
    static func replay(_ java: Entry, _ environment: Environment) -> Entry {
        let ctx = Ctx(environment)
        var lines: [String] = []
        lines.reserveCapacity(java.lines.count)
        for line in java.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count >= 2, fields[1] == "in" else { continue }
            if fields[0] == "defs" {
                lines.append(environment.defsRow(for: java.relative))
                continue
            }
            lines.append(line)
            let inputs: [String] = Array(fields.dropFirst(2))
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

    /// Replays all items, each on its own thread (not in the shared pool). Order of results = order of the reference.
    static func replayAll(_ reference: [Entry]) async throws -> [Entry] {
        let environment: Environment = try Environment.load()
        return try await withThrowingTaskGroup(of: (Int, Entry).self) { group in
            for (index, entry) in reference.enumerated() {
                group.addTask {
                    let replayed = try await JavaNetParityFixture.onGateThread(entry.relative) {
                        replay(entry, environment)
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
        case "ctl.RUN": return try controller(path, f, ctx)
        case "sent.EXCH": return try sentExchange(path, f, ctx)
        case "freq.PARSE": return try frequency(path, f)
        case "act.EPOCH": return [(path, [ContestActivation.parseEpoch(X.text(f[0]) ?? "").map { String($0) } ?? "~"])]
        case "name.CAB": return try cabrilloName(path, f, ctx)
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    // MARK: - ctl.RUN

    static func controller(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let environment: Environment = ctx.environment
        if path == "idle" {
            let idle: ContestRuntime = environment.runtime(dxcc: environment.dxcc)
            var out: [String] = queries(idle)
            out.append(F.tx(idle.activate(id: "nope")?.czech))
            let noEngine: ContestRuntime = environment.runtime(dxcc: nil)
            out.append(F.tx(noEngine.activate(id: "cq-ww-cw")?.czech))
            out.append(X.b(noEngine.engineAvailable))
            let exchange = JavaLinkedMap<String>([("zone", "14")])
            let logged = try idle.log(call: "DL1ABC", band: "20m", mode: "CW", exchange: exchange)
            out.append(logged == nil ? "~" : "logged")
            return [(path, out)]
        }
        let parts: [Substring] = path.split(separator: "/")
        if parts.count == 2 {
            let id: String = X.text(f[0]) ?? ""
            let runtime: ContestRuntime = environment.runtime(dxcc: environment.dxcc)
            ctx.runtime = runtime
            ctx.definitionId = id
            ctx.log = []
            let activation: String = F.tx(runtime.activate(id: id)?.czech)
            return [(path, [activation] + queries(runtime))]
        }
        guard let runtime = ctx.runtime else { throw X.Malformed(text: "no active runtime at \(path)") }
        switch parts[2] {
        case "rq":
            ctx.log.append(try storedQso(f))
            return []
        case "replay":
            return [(path, replayRow(runtime, ctx))]
        case "miss":
            return [(path, try missingSet(ctx))]
        default:
            return [(path, try step(runtime, f))]
        }
    }

    /// One script step: `P` preview, `L` log, `F` exchange fields and completeness.
    static func step(_ runtime: ContestRuntime, _ f: [String]) throws -> [String] {
        let call: String = X.text(f[1]) ?? ""
        let band: String = X.text(f[2]) ?? ""
        let mode: String = X.text(f[3]) ?? ""
        let (exchange, next) = try linkedMap(f, from: 4)
        let ownQth: String? = X.text(f[next])
        let at = Date(timeIntervalSince1970: Double(try X.int64(f[next + 1])) / 1000)
        var out: [String] = []
        switch f[0] {
        case "P":
            do {
                try runtime.preview(call: call, band: band, mode: mode, exchange: exchange, ownQth: ownQth, at: at)
                out.append("ok")
            } catch {
                out.append(F.tx(thrown(error)))
            }
            out += result(runtime.lastPreview)
        case "L":
            do {
                let logged = try runtime.log(call: call, band: band, mode: mode, exchange: exchange, ownQth: ownQth,
                                             at: at)
                out += result(logged)
            } catch {
                out.append(F.tx(thrown(error)))
            }
            out += score(runtime.score)
        default:
            do {
                out += ids(try runtime.exchangeFields(call: call))
            } catch {
                out.append(F.tx(thrown(error)))
            }
            do {
                out.append(X.b(try runtime.isComplete(call: call, exchange: exchange)))
            } catch {
                out.append(F.tx(thrown(error)))
            }
        }
        return out
    }

    /// A QSO as stored by the logging path (`d/<id>/rq/NNN`).
    static func storedQso(_ f: [String]) throws -> Qso {
        var q = Qso()
        q.call = X.text(f[0]) ?? ""
        q.band = Band.from(adif: X.text(f[1]))
        q.mode = X.text(f[2]).flatMap { Mode(rawValue: $0) }
        q.exchangeRcvd = X.text(f[3]) ?? ""
        q.serialRcvd = f[4] == "~" ? nil : try X.int(f[4])
        q.timestampUtc = Date(timeIntervalSince1970: Double(try X.int64(f[5])) / 1000)
        q.xqso = X.bool(f[6])
        q.exchangeSent = X.text(f[7]) ?? ""
        return q
    }

    /// `replayLogged` into a second runtime, then `replayed` + `adopt` into the live one.
    static func replayRow(_ runtime: ContestRuntime, _ ctx: Ctx) -> [String] {
        let second: ContestRuntime = ctx.environment.runtime(dxcc: ctx.environment.dxcc)
        _ = second.activate(id: ctx.definitionId)
        second.replayLogged(ctx.log)
        var out: [String] = score(second.score)
        guard let outcome = runtime.replayed(ctx.log, now: { Date(timeIntervalSince1970: 4_102_444_800) }) else {
            return out + ["SWIFT: no outcome"]
        }
        out.append(String(outcome.replayed))
        out.append(String(outcome.skipped))
        out.append(X.b(runtime.adopt(outcome, forContestId: "other-contest")))
        out.append(X.b(runtime.adopt(outcome, forContestId: nil)))
        out.append(X.b(runtime.adopt(outcome, forContestId: ctx.definitionId)))
        out.append(runtime.lastPreview == nil ? "~" : "preview")
        return out + score(runtime.score)
    }

    /// Activation of the definition with its first multiplier set renamed to one the registry lacks.
    static func missingSet(_ ctx: Ctx) throws -> [String] {
        var definition: ContestDefinition = try ctx.environment.contest(id: ctx.definitionId)
        if var bindings = definition.multipliers, let index = bindings.firstIndex(where: { $0 != nil }),
           var binding = bindings[index] {
            binding.set = "missing_" + (binding.set ?? "null")
            bindings[index] = binding
            definition.multipliers = bindings
        }
        let fresh: ContestRuntime = ctx.environment.runtime(dxcc: ctx.environment.dxcc)
        let message: ContestMessage? = fresh.activate(contestId: "snapshot-" + ctx.definitionId, definition: definition)
        return [F.tx(message?.czech), X.b(fresh.isActive)]
    }

    /// The definition queries (Kotlin `ContestController`), in the generator's order.
    static func queries(_ c: ContestRuntime) -> [String] {
        var f: [String] = [X.b(c.isActive), F.tx(c.activeId), F.tx(c.activeName)]
        f.append(X.b(c.usesSerial))
        f.append(X.b(c.usesExchangeBeyondRst))
        f.append(c.primaryMode.rawValue)
        f.append(X.b(c.isMultiMode))
        f.append(c.dupeScope?.rawValue ?? "~")
        let bands: [String?] = c.bandOrder
        f.append(String(bands.count))
        f += bands.map { F.tx($0) }
        f.append(X.b(c.usesRoverQth))
        f.append(c.qtcConfig == nil ? "0" : "1")
        do {
            f += ids(try c.exchangeFields(call: ""))
        } catch {
            f.append(F.tx(thrown(error)))
        }
        return f + score(c.score)
    }

    static func ids(_ fields: [ContestDefinition.ExchangeField]) -> [String] {
        [String(fields.count)] + fields.map { F.tx($0.id) }
    }

    static func result(_ r: ContestSession.LogResult?) -> [String] {
        guard let r else { return ["~"] }
        var f: [String] = [X.b(r.counted), X.b(r.dupe), String(r.points), String(r.multipliers.count)]
        for m in r.multipliers {
            f += [F.tx(m.bindingId), F.tx(m.setId), F.tx(m.key), F.tx(m.scopeKey), m.state.rawValue]
            f += [X.b(m.countsAsMultiplier), X.b(m.isNew)]
        }
        return f
    }

    static func score(_ s: ScoreState?) -> [String] {
        guard let s else { return ["~"] }
        var f: [String] = [String(s.qsoCount), String(s.qsoPoints), String(s.multTotal), String(s.multByGroup.count)]
        for entry in s.multByGroup.entries {
            f.append(F.tx(entry.key))
            f.append(entry.value.map { String($0) } ?? "~")
        }
        return f + [String(s.bonusPoints), String(s.qtcPoints), String(s.total)]
    }

    /// Java `THROW <class>: <message>` for the Swift error that replaces the Java exception.
    static func thrown(_ error: any Error) -> String {
        switch error {
        case let error as ContestSessionError:
            switch error {
            case .expression(let inner): return thrown(inner)
            case .exchange(let inner): return thrown(inner)
            case .multiplier(let inner): return thrown(inner)
            }
        case let error as ExpressionError:
            return "THROW " + JavaEngineParityTests.javaName(error.kind) + ": " + error.message
        case let error as ExchangeError:
            let name: String = error.kind == .numberFormat ? "NumberFormatException" : "PatternSyntaxException"
            return "THROW " + name + ": " + error.message
        case let error as MultiplierError:
            return "THROW MultiplierException: " + error.description
        default:
            return "THROW Swift." + String(describing: type(of: error)) + ": " + String(describing: error)
        }
    }

    /// A map `count, k, v, …` from index `start` (texts after `tx`); returns the map and the index after it.
    static func linkedMap(_ f: [String], from start: Int) throws -> (JavaLinkedMap<String>, Int) {
        let count: Int = try X.int(f[start])
        guard start + 2 * count < f.count else { throw X.Malformed(text: "map past the end of the row") }
        var map = JavaLinkedMap<String>()
        for i in 0..<count {
            map.put(X.text(f[start + 1 + 2 * i]), X.text(f[start + 2 + 2 * i]))
        }
        return (map, start + 1 + 2 * count)
    }

    // MARK: - sent.EXCH

    static func sentExchange(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let index: Int = try X.int(f[0])
        let defs: [Definition] = ctx.environment.sentDefinitions
        guard index < defs.count else { throw X.Malformed(text: "definition index \(index)") }
        let definition: ContestDefinition? = index < 0 ? nil : defs[index].definition
        let kind: String = f[1]
        let (station, next) = try linkedMap(f, from: 2)
        var setup: ContestSetup?
        if kind == "map" {
            var made = ContestSetup()
            for entry in station.entries {
                if let key = entry.key { made.sentExchange[key] = entry.value ?? "" }
            }
            setup = made
        }
        guard let mode = Mode(rawValue: f[next]) else { throw X.Malformed(text: f[next]) }
        let serial: Int = try X.int(f[next + 1])
        let rst: String = X.text(f[next + 2]) ?? ""
        let ownQth: String? = X.text(f[next + 3])
        let rover: String = X.text(f[next + 4]) ?? ""
        let county: [String] = try X.list(f, from: next + 5).items
        let text: String = SentExchange.text(definition: definition, setup: setup, mode: mode, serial: serial,
                                             roverQth: rover, countyLine: county)
        let flat: String? = SentExchange.flat(definition: definition, setup: setup, mode: mode, serial: serial,
                                              rstSent: rst, ownQth: ownQth)
        return [(path, [F.tx(text), F.tx(flat)])]
    }

    // MARK: - freq.PARSE

    static func frequency(_ path: String, _ f: [String]) throws -> Rows {
        if path == "rows" {
            // The Java table has the 13 bands of v1.1.1; the microwave rows (post-port) are pinned in `BandRowsTests`.
            let javaRows: [BandRows.Row] = BandRows.all.filter { !$0.band.isMicrowave }
            var out: [String] = [String(javaRows.count)]
            for row in javaRows {
                out.append(String(describing: row.band).uppercased())
                out.append(F.tx(row.label))
                let cells: [Double?] = [row.cwKHz, row.phKHz, row.rttyKHz, row.diKHz]
                out += cells.map { $0.map { String($0.bitPattern, radix: 16) } ?? "~" }
            }
            return [(path, out)]
        }
        if path.hasPrefix("f/") {
            guard let bits = UInt64(f[0], radix: 16) else { throw X.Malformed(text: f[0]) }
            return [(path, [F.tx(FrequencyText.formatKHz(Double(bitPattern: bits)))])]
        }
        return [(path, [String(FrequencyText.parseHz(X.text(f[0]) ?? ""))])]
    }

    // MARK: - name.CAB

    static func cabrilloName(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let call: String = X.text(f[2]) ?? ""
        var definition: ContestDefinition?
        switch f[0] {
        case "nodef":
            definition = nil
        case "def":
            definition = try ctx.environment.contest(id: X.text(f[1]) ?? "")
        case "nocab":
            var base: ContestDefinition = try ctx.environment.contest(id: "cq-ww-cw")
            base.cabrillo = nil
            definition = base
        default:
            var base: ContestDefinition = try ctx.environment.contest(id: "cq-ww-cw")
            base.cabrillo?.contestName = X.text(f[1])
            definition = base
        }
        return [(path, [F.tx(ExportNames.cabrilloFileName(stationCall: call, definition: definition))])]
    }
}
