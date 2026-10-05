import Foundation
import Testing
@testable import MCLCore

/// Swift side of the Java parity suite (maintainer-only probe, fixture `g`): replays the input rows of `ui-g-java.json.gz` against the
/// network and integration core (the product code, composed as the app model composes it):
///
/// - `net.MSG` — `NetMessages` (receive, `chatTime`, the send plans) over chat, PASS and STACK messages, three streams
///   with state, the cap of 500 lines and the peers' online / offline / stale states;
/// - `net.SERIAL` — `SerialReservation` over ticks on a virtual clock, replies and writes;
/// - `net.STATUS` — `StationStatusBuilder.status`;
/// - `ext.INGEST` — `ExternalQsoIngest` (N1MM and ADIF) and the contest runtime over the whole corpus in four contexts;
/// - `bc.MAP` — `BroadcastMapping` and `BroadcastXml`;
/// - `wsjtx.DEC` — `WsjtxDecodes` (enrichment, cap, filters, cell texts) over the corpus decodes;
/// - `svc.POLICY` — `ScoreReportPolicy` with `ScoreXml`, `ClubLogQueuePolicy` and `ClockCheck`.
///
/// The messages, peers, N1MM and ADIF records, decodes and QSOs come from the synthetic corpus
/// `Fixtures/ui-gate/net-g.txt` of the bundle (the generator writes it): the rows that carry a corpus record are rebuilt
/// from Swift's own copy, and the `defs` and `corpus` rows are Swift's own too — an edited corpus or definition changes
/// the input checksum and the gate asks for regeneration instead of reporting a mismatch. The texts of the ingest rows
/// (the N1MM XML, the ADIF record) are inputs the generator built; they stay as the reference has them. No socket, no
/// UDP, no HTTP, no NTP, no plugin: the station network is a list of peers.
enum UiParityGSections {

    typealias Entry = JavaYamlParityTests.ReferenceFile
    typealias Rows = [(String, [String])]
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture
    typealias U = UiParitySections
    typealias N = NetworkLogicTests

    static let names: [String] = ["net.MSG", "net.SERIAL", "net.STATUS", "ext.INGEST", "bc.MAP", "wsjtx.DEC", "svc.POLICY"]

    static let ownCall = "OK1XOE"
    static let myGrid = "JN79"
    static let contestNr: Int32 = 123_456_789
    static let t0 = "2026-10-04T12:34:56Z"

    // MARK: - the corpus

    /// The corpus file: lines `KIND TAB field…`, ASCII, the fields as `tx` writes them.
    struct Corpus: Sendable {
        var m: [[String]] = []
        var p: [[String]] = []
        var x: [[String]] = []
        var a: [[String]] = []
        var d: [[String]] = []
        var q: [[String]] = []
        var w: [[String]] = []
        var sha = ""

        var counts: String {
            [m, p, x, a, d, q, w].map { String($0.count) }.joined(separator: " ")
        }

        static func parse(_ data: Data) throws -> Corpus {
            var corpus = Corpus()
            corpus.sha = JavaYamlParityTests.sha256Hex(data)
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts: [String] = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                let record: [String] = Array(parts.dropFirst())
                switch parts[0] {
                case "M": corpus.m.append(record)
                case "P": corpus.p.append(record)
                case "X": corpus.x.append(record)
                case "A": corpus.a.append(record)
                case "D": corpus.d.append(record)
                case "Q": corpus.q.append(record)
                case "W": corpus.w.append(record)
                default: throw X.Malformed(text: String(line))
                }
            }
            return corpus
        }
    }

    /// The environment shared by all items (read-only after creation).
    struct Environment: @unchecked Sendable {
        let base: U.Environment
        let data: URL
        let bandPlan: BandPlan
        let digi: DigiFrequencies
        let gridDb: GridDatabase
        let fieldMap: GridFieldMap
        let corpus: Corpus

        static func load() throws -> Environment {
            let base: U.Environment = try U.Environment.load()
            let data: URL = try ContestDataLayoutTests.contestDataRoot()
            let gate: URL = try #require(Bundle.module.url(forResource: "ui-gate", withExtension: nil))
            let file: Data = try Data(contentsOf: gate.appendingPathComponent("net-g.txt"))
            return Environment(base: base, data: data, bandPlan: BandPlan.fromDir(data),
                               digi: DigiFrequencies.fromDir(data), gridDb: GridDatabase.fromDir(data),
                               fieldMap: GridFieldMap.fromDir(data, base.dxcc), corpus: try Corpus.parse(file))
        }

        var defsRow: String {
            base.defsRow(for: "ctl.RUN")
        }

        var corpusRow: String {
            F.line("corpus", "in", [corpus.sha, corpus.counts])
        }

        /// A runtime over the gate's definitions with `contest` activated (`nil` = none).
        func runtime(_ contest: String?) throws -> ContestRuntime {
            let runtime = ContestRuntime(dxcc: base.dxcc, registry: base.registry, contestsDir: base.contestsDir,
                                         myCall: { UiParityGSections.ownCall }, myGrid: { UiParityGSections.myGrid })
            if let contest, let error = runtime.activate(id: contest) {
                throw X.Malformed(text: "activation of \(contest): \(error.czech)")
            }
            return runtime
        }

        func analyzer(_ runtime: ContestRuntime) -> SpotAnalyzer {
            SpotAnalyzer(runtime: runtime, bandPlan: bandPlan, digiFrequencies: digi, gridDatabase: gridDb,
                         gridFieldMap: fieldMap, callbook: { _ in nil }, gridLog: nil, now: { Date() })
        }
    }

    // MARK: - replay

    /// A contest with its log, as the app's `qsos` list and runtime hold them.
    final class Context {
        let runtime: ContestRuntime
        var logged: [Qso] = []

        init(_ runtime: ContestRuntime) {
            self.runtime = runtime
        }
    }

    struct Serial {
        var reservation = SerialReservation()
        var now: Int64 = 1_000_000
        var enabled = true
        var net = true
    }

    /// The list of the cap run: a fresh runtime without a log (the generator's `cap` rig has none either).
    struct CapList {
        var list: WsjtxDecodes
        var fed: Int
        let analyzer: SpotAnalyzer
        let context: Context
    }

    struct Decoding {
        let context: Context
        var list = WsjtxDecodes()
        var status: WsjtxMessages.Status?
        var analyzer: SpotAnalyzer?
    }

    /// The state of one item between its rows.
    final class Ctx {
        let environment: Environment
        var streams: [String: NetMessages] = [:]
        var serial: [String: Serial] = [:]
        var contexts: [String: Context] = [:]
        var decodings: [String: Decoding] = [:]
        var capLists: [String: CapList] = [:]

        init(_ environment: Environment) {
            self.environment = environment
        }

        func context(_ key: String, contest: String?) throws -> Context {
            if let existing = contexts[key] { return existing }
            let made = Context(try environment.runtime(contest))
            contexts[key] = made
            return made
        }
    }

    /// One computed row: the input row when Swift rebuilds it (a corpus record), and the outputs.
    struct Step {
        var input: [String]?
        var rows: Rows
    }

    static func replay(_ java: Entry, _ environment: Environment) -> Entry {
        let ctx = Ctx(environment)
        var lines: [String] = []
        lines.reserveCapacity(java.lines.count)
        for line in java.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count >= 2, fields[1] == "in" else { continue }
            if fields[0] == "defs" {
                lines.append(environment.defsRow)
                continue
            }
            if fields[0] == "corpus" {
                lines.append(environment.corpusRow)
                continue
            }
            let inputs: [String] = Array(fields.dropFirst(2))
            do {
                let step: Step = try compute(java.relative, fields[0], inputs, ctx)
                lines.append(step.input.map { F.line(fields[0], "in", $0) } ?? line)
                for (outPath, out) in step.rows {
                    lines.append(F.line(outPath, "out", out))
                }
            } catch {
                lines.append(line)
                lines.append(F.line(fields[0], "out", ["SWIFT ERROR", String(describing: error)]))
            }
        }
        let sum: String = F.checksum(definition: nil, registry: "", lines: lines)
        return Entry(relative: java.relative, sha256: sum, lines: lines)
    }

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

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        switch name {
        case "net.MSG": return try messages(path, f, ctx)
        case "net.SERIAL": return try serial(path, f, ctx)
        case "net.STATUS": return try status(path, f)
        case "ext.INGEST": return try ingestRow(path, f, ctx)
        case "bc.MAP": return try broadcast(path, f, ctx)
        case "wsjtx.DEC": return try decodes(path, f, ctx)
        case "svc.POLICY": return try policy(path, f, ctx)
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    // MARK: - field helpers

    static func text(_ field: String) -> String {
        X.text(field) ?? ""
    }

    static func optional(_ field: String) -> String? {
        X.text(field)
    }

    static func int(_ field: String) throws -> Int {
        guard let value = Int(field) else { throw X.Malformed(text: field) }
        return value
    }

    static func int64(_ field: String) throws -> Int64 {
        guard let value = Int64(field) else { throw X.Malformed(text: field) }
        return value
    }

    static func tx(_ value: String?) -> String {
        F.tx(value)
    }

    static func record(_ list: [[String]], _ index: Int) throws -> [String] {
        guard list.indices.contains(index) else { throw X.Malformed(text: "record \(index)") }
        return list[index]
    }

    /// The row input of a corpus record: the index and the record's fields as the corpus file has them.
    static func carried(_ index: Int, _ record: [String]) -> [String] {
        [String(index)] + record
    }

    static func wire(_ m: [String]) throws -> NetMessageWire {
        NetMessageWire(type: optional(m[0]), id: "id", fromStation: optional(m[1]), fromOperator: optional(m[2]),
                       toStation: optional(m[3]), text: optional(m[4]), call: optional(m[5]), freqHz: try int(m[6]),
                       mode: "", timestampUtc: optional(m[7]))
    }

    // MARK: - net.MSG

    /// The cells of a chat line as the generator writes them: tx'd fields joined with a tab (and the time first).
    static func lineText(_ line: ChatLine, time: String?) -> String {
        var parts: [String] = [tx(line.from), tx(line.to), tx(line.text), X.b(line.own)]
        if let time { parts.insert(time, at: 0) }
        return parts.joined(separator: "\t")
    }

    static func stackText(_ messages: NetMessages) -> String {
        messages.stack.map { $0 + "\n" }.joined()
    }

    static func spotsText(_ effects: [NetEffect]) -> String {
        var out = ""
        for effect in effects {
            guard case .addSpot(let spot) = effect else { continue }
            out += "\(spot.spotter)\t\(spot.freqHz)\t\(spot.dxCall)\t\(spot.comment)\n"
        }
        return out
    }

    /// One reducer step: status, unread counter, number of lines, the new line (when one was added), the stack, the
    /// spots and the number of lines added.
    static func receive(_ messages: inout NetMessages, _ m: [String]) throws -> [String] {
        let message: NetMessageWire = try wire(m)
        let cat: Int? = optional(m[8]).flatMap { Int($0) }
        let tuned: Int = try int(text(m[9]))
        let before: Int = messages.lines.count
        let effects = messages.receive(message, catFreqHz: cat, tunedHz: tuned, now: N.now)
        let parsed: Bool = message.timestampUtc.flatMap { JavaInstant.parseIsoInstant($0) } != nil
        let added: Int = messages.lines.count - before
        var last = "~"
        if added > 0, let line = messages.lines.last {
            let time: String = (!parsed && line.time == N.nowText) ? "NOW" : line.time
            last = tx(lineText(line, time: time))
        }
        return [tx(N.czech(effects)), String(messages.unread), String(messages.lines.count), last,
                tx(stackText(messages)), tx(spotsText(effects)), String(added)]
    }

    static func peers(_ corpus: Corpus, mask: String) throws -> [StationNetwork.Peer] {
        var out: [StationNetwork.Peer] = []
        let flags: [Character] = Array(mask)
        for (index, rec) in corpus.p.enumerated() where index < flags.count && flags[index] == "1" {
            let stale: Bool = text(rec[10]) == "1"
            let online: Bool = text(rec[8]) == "1"
            let status = StationStatusWire(stationId: text(rec[0]), operator: text(rec[1]), stationType: "",
                                           band: text(rec[2]), mode: text(rec[3]), freqHz: try int(text(rec[4])),
                                           runMode: text(rec[5]), qsoCount: Int32(try int(text(rec[6]))),
                                           transmitting: text(rec[7]) == "1", online: online, timestampUtc: t0,
                                           entryCall: text(rec[9]))
            out.append(StationNetwork.Peer(status: status, receivedAt: .epoch, online: online && !stale,
                                           age: stale ? .seconds(101) : .seconds(1)))
        }
        return out
    }

    /// The transport clock of a scenario: `+1 s` once peers were published, `+101 s` with a stale one among them.
    static func stamp(_ corpus: Corpus, net: Bool, mask: String) -> String {
        guard net else { return t0 }
        let flags: [Character] = Array(mask)
        let stale: Bool = corpus.p.indices.contains { $0 < flags.count && flags[$0] == "1" && text(corpus.p[$0][10]) == "1" }
        return stale ? "2026-10-04T12:36:37Z" : "2026-10-04T12:34:57Z"
    }

    static func messages(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        let corpus: Corpus = ctx.environment.corpus
        let head: String = String(path.split(separator: "/").first ?? "")
        switch head {
        case "r":
            let index: Int = try int(f[0])
            let rec: [String] = try record(corpus.m, index)
            var messages = NetMessages()
            return Step(input: carried(index, rec), rows: [(path, try receive(&messages, rec))])
        case "cap":
            var messages = NetMessages()
            for i in 1...505 {
                let w = NetMessageWire(type: "CHAT", id: "id", fromStation: "OP2", fromOperator: "", toStation: "",
                                       text: "m\(i)", call: "", freqHz: 0, mode: "", timestampUtc: "2026-10-04T12:34:56Z")
                _ = messages.receive(w, catFreqHz: nil, tunedHz: 0, now: N.now)
            }
            let first: String = tx(lineText(messages.lines[0], time: messages.lines[0].time))
            let lastLine: ChatLine = messages.lines[messages.lines.count - 1]
            return Step(input: nil, rows: [(path, [String(messages.lines.count), first,
                                                   tx(lineText(lastLine, time: lastLine.time)), String(messages.unread)])])
        case "ct":
            let index: Int = Int(path.dropFirst(3)) ?? -1
            let rec: [String] = try record(corpus.m, index)
            let ts: String? = optional(rec[7])
            let out: String = NetMessages.chatTime(ts, now: N.now)
            let parsed: Bool = ts.flatMap { JavaInstant.parseIsoInstant($0) } != nil
            return Step(input: nil, rows: [(path, [(!parsed && out == N.nowText) ? "NOW" : out])])
        case "t":
            return try send(path, f, corpus)
        default:
            // a stream `s<k>/NNN` or its end `s<k>/end`
            if path.hasSuffix("/end") {
                let messages: NetMessages = ctx.streams[head] ?? NetMessages()
                let all: String = messages.lines.map { lineText($0, time: nil) + "\n" }.joined()
                return Step(input: nil, rows: [(path, [tx(all), String(messages.unread), tx(stackText(messages))])])
            }
            let index: Int = try int(f[0])
            let rec: [String] = try record(corpus.m, index)
            var messages: NetMessages = ctx.streams[head] ?? NetMessages()
            let out: [String] = try receive(&messages, rec)
            ctx.streams[head] = messages
            return Step(input: carried(index, rec), rows: [(path, out)])
        }
    }

    /// The send-side scenarios `t/NNN`, composed from the core plans exactly as the app model composes them.
    static func send(_ path: String, _ f: [String], _ corpus: Corpus) throws -> Step {
        let op: String = f[0]
        func net(_ field: String, _ maskField: String) throws -> (Bool, String, [StationNetwork.Peer]?) {
            let connected: Bool = X.bool(field)
            let mask: String = maskField
            return (connected, mask, connected ? try peers(corpus, mask: mask) : nil)
        }
        func myFreq(_ cat: String, _ tuned: String) throws -> Int {
            let catFreq: Int? = optional(cat).flatMap { Int($0) }
            return try catFreq ?? int(tuned)
        }
        switch op {
        case "C": // to, text, net, mask, fail, failMessage, pending
            let (connected, mask, list) = try net(f[3], f[4])
            var sim = NetworkSendTests.Sim(peers: list, timestamp: stamp(corpus, net: connected, mask: mask))
            sim.messages.passPending = text(f[7])
            sim.sendChat(to: text(f[1]), text: text(f[2]), fail: X.bool(f[5]), failMessage: optional(f[6]))
            return Step(input: nil, rows: [(path, [tx(sim.observe())])])
        case "S": // typed, pending, net, mask, cat, tuned
            let (connected, mask, list) = try net(f[3], f[4])
            var sim = NetworkSendTests.Sim(peers: list, timestamp: stamp(corpus, net: connected, mask: mask))
            sim.messages.passPending = text(f[2])
            sim.startPass(typed: text(f[1]), myFreq: try myFreq(f[5], f[6]))
            return Step(input: nil, rows: [(path, [tx(sim.observe())])])
        case "P": // to, call, net, mask, cat, tuned, fail, pending
            let (connected, mask, list) = try net(f[3], f[4])
            var sim = NetworkSendTests.Sim(peers: list, timestamp: stamp(corpus, net: connected, mask: mask))
            sim.messages.passPending = text(f[8])
            sim.passCall(to: text(f[1]), call: text(f[2]), myFreq: try myFreq(f[5], f[6]), fail: X.bool(f[7]))
            return Step(input: nil, rows: [(path, [tx(sim.observe())])])
        case "K": // to, call, net, mask, fail, pending
            let (connected, mask, list) = try net(f[3], f[4])
            var sim = NetworkSendTests.Sim(peers: list, timestamp: stamp(corpus, net: connected, mask: mask))
            sim.messages.passPending = text(f[6])
            sim.stackCall(to: text(f[1]), call: text(f[2]), fail: X.bool(f[5]))
            return Step(input: nil, rows: [(path, [tx(sim.observe())])])
        case "O": // net, mask, pending, n, calls…
            let (connected, mask, list) = try net(f[1], f[2])
            var sim = NetworkSendTests.Sim(peers: list, timestamp: stamp(corpus, net: connected, mask: mask))
            sim.messages.passPending = text(f[3])
            let count: Int = try int(f[4])
            for index in 0..<count {
                let w = NetMessageWire(type: "STACK", id: "id", fromStation: "OP2", fromOperator: "", toStation: "",
                                       text: "", call: text(f[5 + index]), freqHz: 0, mode: "", timestampUtc: t0)
                let effects = sim.messages.receive(w, catFreqHz: nil, tunedHz: 0, now: sim.now)
                sim.status = N.czech(effects)
            }
            var observed = ""
            for _ in 0...count {
                sim.pop()
                observed += "[" + NetworkProbeTable.esc(sim.prefill) + "|" + NetworkProbeTable.esc(sim.status) + "]"
            }
            return Step(input: nil, rows: [(path, [tx(observed), tx(sim.observe())])])
        default:
            throw X.Malformed(text: "send op \(op)")
        }
    }

    // MARK: - net.SERIAL

    static func serial(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        let key: String = String(path.split(separator: "/").first ?? "")
        var state: Serial = ctx.serial[key] ?? Serial()
        let pendingBefore: String? = state.reservation.pendingRequestId
        var requests = 0
        func tick() {
            if state.reservation.tick(nowMs: state.now, enabled: state.enabled, hasNet: state.net,
                                      newId: { UUID().uuidString }) != nil {
                requests += 1
            }
        }
        switch f[0] {
        case "T": // dt, enabled, net
            state.now += try int64(f[1])
            state.enabled = X.bool(f[2])
            state.net = X.bool(f[3])
            tick()
        case "R": // which, serial
            let which: Int = try int(f[1])
            let id: String? = which == 0 ? state.reservation.pendingRequestId : (which == 1 ? "other-id" : nil)
            state.reservation.reply(SerialReply(stationId: "OP1", requestId: id, serial: Int32(try int(f[2]))))
        case "W": // which
            let which: Int = try int(f[1])
            let reserved: Int? = state.reservation.reserved
            let serialSent: Int? = which == 0 ? reserved : (which == 1 ? (reserved.map { $0 + 1 } ?? 77) : nil)
            if state.reservation.consumed(serial: serialSent) {
                tick()
            }
        default:
            throw X.Malformed(text: "serial op \(f[0])")
        }
        ctx.serial[key] = state
        let pending: String? = state.reservation.pendingRequestId
        let kind: String = pending == nil ? "none" : (pending == pendingBefore ? "same" : "new")
        let reserved: String = state.reservation.reserved.map { String($0) } ?? "null"
        return Step(input: nil, rows: [(path, [tx(reserved), kind, String(requests)])])
    }

    // MARK: - net.STATUS

    static func status(_ path: String, _ f: [String]) throws -> Step {
        var catFreq: Int?
        var catMode: Mode?
        if f[0] != "~" {
            let parts = f[0].split(separator: "/", omittingEmptySubsequences: false)
            catFreq = Int(parts[0])
            catMode = Mode(rawValue: String(parts[1]))
        }
        let w = StationStatusBuilder.status(
            stationId: text(f[9]), operatorCall: text(f[8]),
            stationType: OperatingGuard.StationType(rawValue: f[6]) ?? .none, catFreqHz: catFreq, catMode: catMode,
            tunedFreqHz: try int(f[1]), runMode: f[2] == "RUN" ? .run : .searchAndPounce, qsoCount: try int(f[3]),
            sending: X.bool(f[4]) || X.bool(f[5]), typedCall: text(f[7]))
        return Step(input: nil, rows: [(path, [tx(w.stationId), tx(w.operator), tx(w.stationType), tx(w.band), tx(w.mode),
                                               String(w.freqHz), tx(w.runMode), String(w.qsoCount), X.b(w.transmitting),
                                               X.b(w.online), tx(w.timestampUtc), tx(w.entryCall)])])
    }

    // MARK: - ext.INGEST

    static func qsoText(_ q: Qso, withTime: Bool) -> String {
        func string(_ value: String) -> String { tx(value.isEmpty ? nil : value) }
        func number(_ value: Int?) -> String { value.map { String($0) } ?? "null" }
        let time: String = withTime ? q.timestampUtc.map { JavaInstant(date: $0).toString() } ?? "null" : "-"
        let cols: [String] = [
            string(q.call), q.band?.adif ?? "~", q.mode?.rawValue ?? "~", String(q.freqHz), string(q.rstSent),
            string(q.rstRcvd), string(q.exchangeSent), string(q.exchangeRcvd), number(q.serialSent),
            number(q.serialRcvd), string(q.comment), q.runMode.rawValue, String(q.imported), time,
        ]
        return cols.joined(separator: "|")
    }

    static func hasTimestamp(_ input: String) -> Bool {
        let pattern = "(?s).*timestamp>\\d{4}-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d<.*"
        return input.range(of: pattern, options: .regularExpression) != nil || input.contains("qso_date")
    }

    /// One ingest: the outcome class, the counted flag, the status and the QSO (the generator's `ingest`).
    static func ingest(_ context: Context, isN1mm: Bool, label: String, input: String) -> [String] {
        let runtime: ContestRuntime = context.runtime
        // The closure is only called synchronously inside this function, on the gate's thread.
        nonisolated(unsafe) let fields = runtime
        let snapshot = IngestSnapshot(
            qsos: context.logged, isContestActive: runtime.isActive,
            exchangeFields: { call throws(ExpressionError) in try fields.exchangeFields(call: call) },
            nextSerial: context.logged.count + 1, runMode: .searchAndPounce, ownCall: ownCall)
        let outcome: IngestOutcome = isN1mm
            ? ExternalQsoIngest.n1mm(input, snapshot: snapshot)
            : ExternalQsoIngest.adif(input, source: label, snapshot: snapshot)
        switch outcome {
        case .drop:
            return ["drop", "-", "~", "~"]
        case .status(let status):
            return ["status", "-", tx(status.czech), "~"]
        case .log(let ingested):
            context.logged.append(ingested.qso)
            let withTime: Bool = hasTimestamp(input)
            do {
                let result = try runtime.log(call: ingested.call, band: ingested.bandAdif, mode: ingested.modeName,
                                             exchange: ingested.receivedRaw)
                let counted: Bool = result?.counted ?? true
                return ["log", String(counted), tx(ingested.status(counted: counted).czech),
                        qsoText(ingested.qso, withTime: withTime)]
            } catch {
                let status = ExternalQsoIngest.failureStatus(source: ingested.source, message: ErrorText.message(error))
                return ["logfail", "-", tx(status.czech), qsoText(ingested.qso, withTime: withTime)]
            }
        }
    }

    static func ingestRow(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        let parts: [String] = path.split(separator: "/").map(String.init)
        let contest: String = parts[1]
        let context: Context = try ctx.context("ingest/" + contest, contest: contest == "none" ? nil : contest)
        let corpus: Corpus = ctx.environment.corpus
        let isN1mm: Bool = f[0] == "X"
        let index: Int = try int(f[1])
        let rec: [String] = try record(isN1mm ? corpus.x : corpus.a, index)
        let input: String = text(f[f.count - 1])
        let label: String = isN1mm ? "n1mm" : text(rec[0])
        let out: [String] = ingest(context, isN1mm: isN1mm, label: label, input: input)
        return Step(input: [f[0], String(index)] + rec + [f[f.count - 1]], rows: [(path, out)])
    }

    /// A `prep` row: a QSO logged to set a context up (`ctx`, source label and ADIF text in).
    static func prep(_ path: String, _ f: [String], _ context: Context) -> Step {
        Step(input: nil, rows: [(path, ingest(context, isN1mm: false, label: text(f[1]), input: text(f[2])))])
    }

    // MARK: - bc.MAP

    static func qso(_ rec: [String]) throws -> Qso {
        var q = Qso()
        q.call = text(rec[0])
        if let ms = optional(rec[1]).flatMap({ Int64($0) }) {
            q.timestampUtc = Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        q.freqHz = try int(text(rec[2]))
        q.mode = optional(rec[3]).flatMap { Mode(rawValue: $0) }
        q.continent = text(rec[4])
        q.rstSent = text(rec[5])
        q.rstRcvd = text(rec[6])
        q.serialSent = optional(rec[7]).flatMap { Int($0) }
        q.serialRcvd = optional(rec[8]).flatMap { Int($0) }
        q.points = try int(text(rec[9]))
        q.multiplier = text(rec[10]) == "1"
        q.uuid = text(rec[11])
        return q
    }

    static func mask(_ value: String) -> String {
        value.replacingOccurrences(of: "\\d{4}-\\d{2}-\\d{2}T[\\d:.]+Z", with: "<instant>", options: .regularExpression)
            .replacingOccurrences(of: "\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}", with: "<instant>", options: .regularExpression)
    }

    static func broadcast(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        let parts: [String] = path.split(separator: "/").map(String.init)
        let contest: String = parts[1]
        let context: Context = try ctx.context("bc/" + contest, contest: contest == "none" ? nil : contest)
        let runtime: ContestRuntime = context.runtime
        let name: String? = runtime.activeName
        switch parts[0] {
        case "prep":
            return prep(path, f, context)
        case "k":
            let index: Int = try int(f[0])
            let rec: [String] = try record(ctx.environment.corpus.q, index)
            let q: Qso = try qso(rec)
            let data = BroadcastMapping.contactData(q, contestName: name, contestNr: contestNr, stationCall: ownCall)
            // Divergence (a deliberate divergence from Java v1.1.1): the JVM fixture only knows edits that changed neither call nor time.
            let replace = BroadcastMapping.replace(old: q, new: q, contestName: name, contestNr: contestNr, stationCall: ownCall)
            let replaced = BroadcastXml.contactReplace(replace.data, oldCall: replace.oldCall, oldTs: replace.oldTimestamp)
            return Step(input: carried(index, rec), rows: [(path, [tx(BroadcastXml.contactInfo(data)), tx(replaced)])])
        case "score":
            let score = BroadcastMapping.scoreData(isContestActive: runtime.isActive, score: runtime.score,
                                                   activeName: name, activeId: runtime.activeId, stationCall: ownCall,
                                                   operatorCall: ownCall, now: Date(timeIntervalSince1970: 1_791_021_600))
            return Step(input: nil, rows: [(path, [score.map { tx(mask(BroadcastXml.dynamicResults($0))) } ?? "~"])])
        case "appinfo":
            let info = BroadcastMapping.appInfoData(contestNr: contestNr, contestName: name, stationCall: ownCall)
            return Step(input: nil, rows: [(path, [tx(BroadcastXml.appInfo(info))])])
        case "radio": // connected, hasState, freq, mode, raw, passband, run
            var rig: RigState?
            if X.bool(f[1]) {
                rig = RigState(freqHz: try int64(f[2]), mode: Mode(rawValue: f[3]), rawMode: text(f[4]),
                               passband: try int64(f[5]))
            }
            let radio = BroadcastMapping.radioData(stationCall: ownCall, catConnected: X.bool(f[0]), rig: rig,
                                                   operatorCall: ownCall, runMode: f[6] == "RUN" ? .run : .searchAndPounce)
            return Step(input: nil, rows: [(path, [radio.map { tx(BroadcastXml.radioInfo($0)) } ?? "~"])])
        default:
            throw X.Malformed(text: "broadcast row \(path)")
        }
    }

    // MARK: - wsjtx.DEC

    static let statuses: [WsjtxMessages.Status?] = [
        nil,
        wsjtxStatus(0, "FT8"), wsjtxStatus(14_074_000, "FT8", sending: true), wsjtxStatus(14_074_000, nil),
        wsjtxStatus(21_074_000, "FT4"), wsjtxStatus(14_025_000, "CW"), wsjtxStatus(21_025_000, "CW"),
        wsjtxStatus(7_074_000, "FT8"), wsjtxStatus(28_074_000, "FT8"),
    ]

    static func wsjtxStatus(_ dial: Int64, _ mode: String?, sending: Bool = false) -> WsjtxMessages.Status {
        WsjtxMessages.Status(id: "WSJT-X", dialFrequencyHz: dial, mode: mode, dxCall: nil, report: nil, txMode: nil,
                             txEnabled: sending, transmitting: sending)
    }

    static func decode(_ d: [String]) throws -> WsjtxMessages.Decode {
        WsjtxMessages.Decode(id: "WSJT-X", isNew: true, timeMs: Int32(try int(text(d[0]))), snr: Int32(try int(text(d[1]))),
                             deltaTime: 0.2, deltaFrequency: Int32(try int(text(d[2]))), mode: optional(d[3]),
                             message: optional(d[4]), lowConfidence: false, offAir: false)
    }

    static func cells(_ row: WsjtxDecodes.Row) -> String {
        let c = WsjtxDecodes.rowText(row)
        return [c.time, c.snr, c.deltaFrequency, c.message, c.label].joined(separator: "|")
    }

    static let flags: [(Bool, Bool, Bool)] = [(false, false, false), (true, false, false), (false, true, false),
                                              (false, false, true), (true, true, true), (true, false, true)]

    static func add(_ list: inout WsjtxDecodes, _ d: WsjtxMessages.Decode, status: WsjtxMessages.Status?,
                    analyzer: SpotAnalyzer, logged: [Qso], from: UdpEndpoint) {
        let checker = DupeChecker(existing: logged)
        list.add(d, from: from, status: status, analyzer: analyzer, isDupe: { call, band in
            checker.isDupe(call: call, band: band)
        })
    }

    static func decodes(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        let parts: [String] = path.split(separator: "/").map(String.init)
        let contest: String = parts[1]
        let from = try UdpEndpoint.resolve(host: "127.0.0.1", port: 2237)
        let environment: Environment = ctx.environment
        switch parts[0] {
        case "prep":
            let context: Context = try ctx.context("dec/" + contest, contest: contest == "none" ? nil : contest)
            return prep(path, f, context)
        case "cap":
            let target: Int = try int(f[0])
            var entry: CapList
            if let existing = ctx.capLists[contest] {
                entry = existing
            } else {
                let context = Context(try environment.runtime(contest == "none" ? nil : contest))
                entry = CapList(list: WsjtxDecodes(), fed: 0, analyzer: environment.analyzer(context.runtime), context: context)
            }
            while entry.fed <= target {
                let i: Int = entry.fed
                let d = WsjtxMessages.Decode(id: "WSJT-X", isNew: true, timeMs: 0, snr: Int32(i), deltaTime: 0.2,
                                             deltaFrequency: Int32(i), mode: "~", message: "CQ DL\(i)A JO31",
                                             lowConfidence: false, offAir: false)
                add(&entry.list, d, status: wsjtxStatus(14_074_000, "FT8"), analyzer: entry.analyzer, logged: [], from: from)
                entry.fed += 1
            }
            ctx.capLists[contest] = entry
            let rows = entry.list.rows
            return Step(input: nil, rows: [(path, [String(rows.count), String(rows[0].decode.deltaFrequency),
                                                   String(rows[rows.count - 1].decode.deltaFrequency)])])
        default:
            break
        }
        let context: Context = try ctx.context("dec/" + contest, contest: contest == "none" ? nil : contest)
        var state: Decoding = ctx.decodings[contest] ?? Decoding(context: context)
        if state.analyzer == nil {
            state.analyzer = environment.analyzer(context.runtime)
        }
        guard let analyzer = state.analyzer else { throw X.Malformed(text: "no analyzer") }
        defer { ctx.decodings[contest] = state }
        let leaf: String = parts[parts.count - 1]
        if leaf == "status" {
            let index: Int = try int(f[0])
            state.status = statuses[index]
            return Step(input: nil, rows: [(path, [tx(WsjtxDecodes.statusText(status: statuses[index]).czech)])])
        }
        if leaf == "size" {
            return Step(input: nil, rows: [(path, [String(state.list.rows.count)])])
        }
        if leaf.hasPrefix("f"), let index = Int(leaf.dropFirst()) {
            let (onlyCq, hideDupes, onlyMults) = flags[index]
            let rows = state.list.filtered(onlyCq: onlyCq, hideDupe: hideDupes, onlyMult: onlyMults)
            let shown: String = rows.prefix(12).map { cells($0) + "\n" }.joined()
            return Step(input: nil, rows: [(path, [String(rows.count), tx(shown)])])
        }
        let index: Int = try int(f[0])
        let rec: [String] = try record(environment.corpus.d, index)
        let before: Int = state.list.rows.count
        add(&state.list, try decode(rec), status: state.status, analyzer: analyzer, logged: context.logged, from: from)
        let row: WsjtxDecodes.Row = state.list.rows[0]
        return Step(input: carried(index, rec), rows: [(path, [
            String(state.list.rows.count - before), String(row.freqHz), X.b(row.dupe), String(row.newMultCount),
            tx(row.parsed.caller), tx(row.parsed.target), X.b(row.parsed.cq), tx(row.parsed.grid), tx(cells(row)),
        ])])
    }

    // MARK: - svc.POLICY

    static let now = JavaInstant.ofEpochSecond(1_791_021_600, 123_456_000)!

    static func policy(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        let parts: [String] = path.split(separator: "/").map(String.init)
        switch parts[0] {
        case "p":
            if parts.count == 3 { // p/NNN/prep
                let context: Context = try ctx.context("policy/" + parts[1], contest: optional(f[0]))
                return prep(path, f, context)
            }
            return try score(path, f, ctx, key: parts[1])
        case "l":
            return try clubLogGate(path, f, ctx)
        case "o":
            return try clubLogOutcome(path, f)
        case "n":
            return try clock(path, f)
        default:
            throw X.Malformed(text: "policy row \(path)")
        }
    }

    static func score(_ path: String, _ f: [String], _ ctx: Ctx, key: String) throws -> Step {
        let contest: String? = optional(f[0])
        let context: Context = try ctx.context("policy/" + key, contest: contest)
        let runtime: ContestRuntime = context.runtime
        let enabled: Bool = X.bool(f[1])
        let force: Bool = X.bool(f[2])
        let age: Int64 = try int64(f[3])
        let sameRevision: Bool = X.bool(f[4])
        let code: Int = try int(f[5])
        var config = AppConfig()
        config.scoreReportingMinutes = try int(f[6]) // the configuration keeps at least 2 minutes
        let minutes: Int = config.scoreReportingMinutes
        let failure: Int = try int(f[7])
        let last = JavaInstant.ofEpochSecond(now.epochSecond - age, Int64(now.nano))!
        let revision: Int64 = 7
        let lastRevision: Int64 = sameRevision ? 7 : 3
        let definition: ContestDefinition? = runtime.definition
        let due = ScoreReportPolicy.due(force: force, enabled: enabled, hasDefinition: definition != nil, revision: revision,
                                        lastRevision: lastRevision, now: now, lastAt: last, minutes: minutes)
        var posts = 0
        var url = "-"
        var moved = false
        var revisionAfter: Int64 = lastRevision
        var status: String = ScoreReportPolicy.idleStatus
        var xml = "<none>"
        if due, let definition, let score = runtime.score {
            let station = ScoreReportPolicy.station(call: ownCall, operators: "OK1XOE OK1ABC", club: "OKCC", cqZone: "15",
                                                    ituZone: "28", gridSquare: "JN79xx",
                                                    category: ["OPERATOR": "SINGLE-OP", "POWER": "LOW"])
            let contestName = ScoreReportPolicy.contestName(cabrilloName: definition.cabrillo?.contestName,
                                                            definitionId: definition.id)
            guard let session = runtime.freshSession() else { throw X.Malformed(text: "no session") }
            let breakdown = try ScoreBreakdown.compute(session, context.logged)
            xml = ScoreXml.build(contestName: contestName, station: station, score: score, breakdown: breakdown,
                                 withBreakdown: true, version: "vývojová verze", now: now.date)
            posts = 1
            url = "http://gate.invalid/post/"
            let message: String? = failure == 1 ? "Connection refused" : (failure == 2 ? nil : "")
            let result: ScoreReportPolicy.PostResult = failure == 0 ? .http(code) : .failure(message)
            let outcome = ScoreReportPolicy.outcome(result, total: score.total, now: now)
            status = outcome.status.czech
            moved = true
            if outcome.accepted { revisionAfter = revision }
        }
        return Step(input: nil, rows: [(path, ["posts=\(posts)", "url=\(url)", "atMoved=\(moved)", "rev=\(revisionAfter)",
                                               tx(mask(status)), tx(mask(xml))])])
    }

    static func clubLogGate(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Step {
        var cl = ClubLogConfig()
        cl.enabled = X.bool(f[0])
        cl.email = text(f[1])
        cl.appPassword = text(f[2])
        cl.callsign = text(f[3])
        cl.apiKey = text(f[4])
        let configured: Bool = cl.configured()
        var queue: [String] = []
        for k in 0..<2 where ClubLogQueuePolicy.shouldQueue(configured: configured) {
            var q: Qso = try qso(try record(ctx.environment.corpus.q, k))
            if q.call.isEmpty { q.call = "DL1ABC" }
            queue.append(AdifWriter().record(q))
        }
        let records: String = queue.map { $0 + "\n" }.joined()
        let idle: String = Translator.source.translate(ClubLogQueuePolicy.idleStatus)
        return Step(input: nil, rows: [(path, [X.b(configured), String(queue.count), tx(records), tx(idle)])])
    }

    static func clubLogOutcome(_ path: String, _ f: [String]) throws -> Step {
        let outcome: ClubLogClient.Outcome
        switch f[0] {
        case "OK": outcome = .OK
        case "REJECTED": outcome = .REJECTED
        default: outcome = .RETRY
        }
        let queued: Int = try int(f[1])
        var queue: [String] = (0...queued).map { "rec\($0)" }
        let record: String = queue.removeFirst()
        let result = ClubLogQueuePolicy.handle(outcome, queued: queue.count)
        let action: String
        switch result.action {
        case .done:
            action = "done"
        case .drop:
            action = "drop"
        case .retryFront(let delayMs):
            queue.insert(record, at: 0)
            action = "retry \(delayMs) front=\(queue[0])"
        }
        return Step(input: nil, rows: [(path, [action, tx(result.status.czech), String(queue.count)])])
    }

    static func clock(_ path: String, _ f: [String]) throws -> Step {
        let server: String = text(f[0])
        let correct: Bool = X.bool(f[1])
        let offset: Int64 = try int64(f[2])
        let failure: Int = try int(f[3])
        var calls = "[]"
        var offsetText = "null"
        var status: EntryStatus = .tr(ClockCheck.neverChecked)
        var statusMessage = ""
        var messages: [String] = []
        if let host = ClockCheck.server(server) {
            calls = "[\(host):\(ClockCheck.port):\(ClockCheck.timeoutMs)]"
            if failure == 0 {
                let result = ClockCheck.result(offsetMs: offset, server: host, correct: correct)
                offsetText = String(offset)
                status = result.status
                if let warn = result.warnStatus {
                    statusMessage = warn.czech
                    messages.append(result.status.czech)
                }
            } else {
                let message: String? = failure == 1 ? "timed out" : (failure == 2 ? nil : "")
                status = ClockCheck.failure(server: host, message: message)
            }
        } else {
            status = ClockCheck.disabled
        }
        return Step(input: nil, rows: [(path, ["calls=\(calls)", "offset=\(offsetText)", tx(status.czech), tx(statusMessage),
                                               "msgs=\(messages.count)", tx(messages.first ?? "-")])])
    }
}
