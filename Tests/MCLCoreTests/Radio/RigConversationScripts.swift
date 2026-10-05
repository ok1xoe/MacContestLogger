import Darwin
import Foundation
import Testing
@testable import MCLCore

/// Scripts and their execution for the gate `RigConversationParityTests`: a mirror of
/// a maintainer-only probe over the Swift clients. The scripts are read from
/// `Fixtures/radio-gate/conversation.txt` (format in the file header) — the same file is read by the generator, the scenario
/// rows are an input of the item (fingerprint), so changing it without regenerating reports "REGENERATE REFERENCE".
///
/// Everything blocking runs on dedicated threads (`Thread`) — the whole scenario in `onOwnThread`, the server stand-ins
/// on `LoopbackListener` threads, a concurrent call (`bg`) on another `Thread`. The shared Swift pool only waits.
/// The timeout of the Swift clients is a generous 5,000 ms (the Java generator has 300 ms for silence): silence expires
/// in both (lower bound), a successful read has no tight bound and the results do not depend on the timeout length.
enum RigConversationScripts {

    typealias Entry = JavaYamlParityTests.ReferenceFile

    /// Timeout of the Swift clients (`rigctld`, `rotctld`) — a guard, not a measured value.
    static let clientTimeoutMs = 5_000

    struct Scenario: Sendable {
        let name: String
        let options: [String: String]
        /// Body rows after TAB (fields still with escapes).
        let body: [[String]]
        /// Raw rows (header + body) — the item's input.
        let raw: [String]
    }

    struct Section: Sendable {
        let name: String
        var defaults: [(String, [String])] = []
        var fallback: String?
        var raw: [String] = []
        var scenarios: [Scenario] = []
    }

    // MARK: - Scripts

    static func scriptLines() throws -> [String] {
        let url = try JavaRadioParityFixture.gateDirectory().appendingPathComponent("conversation.txt")
        var lines = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    static func parse(_ file: [String]) throws -> [Section] {
        var sections: [Section] = []
        var scenario: (name: String, options: [String: String], body: [[String]], raw: [String])?
        for line in file where !line.isEmpty && !line.hasPrefix("#") {
            let f: [String] = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            switch f[0] {
            case "section":
                sections.append(Section(name: f[1]))
            case "default":
                sections[sections.count - 1].defaults.append((unesc(f[1]), [field(f[2])]))
                sections[sections.count - 1].raw.append(line)
            case "fallback":
                sections[sections.count - 1].fallback = field(f[1])
                sections[sections.count - 1].raw.append(line)
            case "scenario":
                var options: [String: String] = [:]
                for option in f.dropFirst(2) {
                    let kv = option.split(separator: "=", maxSplits: 1).map(String.init)
                    options[kv[0]] = kv[1]
                }
                scenario = (f[1], options, [], [line])
            case "end":
                let s = try #require(scenario, "end bez scenario")
                sections[sections.count - 1].scenarios.append(Scenario(name: s.name, options: s.options, body: s.body, raw: s.raw))
                scenario = nil
            default:
                scenario?.body.append(f)
                scenario?.raw.append(line)
            }
        }
        return sections
    }

    /// Fields after escapes; `<empty>`/`<silent>` = empty.
    static func field(_ text: String) -> String {
        text == "<empty>" || text == "<silent>" ? "" : unesc(text)
    }

    /// `\uXXXX` (UTF-16 unit), `\xNN`, `\t \n \r \\`; like `RigTranscriptGen.unesc`.
    static func unesc(_ text: String) -> String {
        String(decoding: units(text), as: UTF16.self)
    }

    static func units(_ text: String) -> [UInt16] {
        let s: [UInt16] = Array(text.utf16)
        var out: [UInt16] = []
        var i = 0
        while i < s.count {
            let c = s[i]
            if c != 0x5C || i + 1 >= s.count {
                out.append(c)
                i += 1
                continue
            }
            let n = s[i + 1]
            switch n {
            case 0x75: // u
                out.append(UInt16(String(decoding: s[(i + 2)..<(i + 6)], as: UTF16.self), radix: 16) ?? 0)
                i += 6
            case 0x78: // x
                out.append(UInt16(String(decoding: s[(i + 2)..<(i + 4)], as: UTF16.self), radix: 16) ?? 0)
                i += 4
            case 0x74: out.append(0x09); i += 2
            case 0x6E: out.append(0x0A); i += 2
            case 0x72: out.append(0x0D); i += 2
            default: out.append(n); i += 2
            }
        }
        return out
    }

    /// Server reply (already after `field`) as bytes — characters up to U+00FF as `ISO-8859-1`.
    static func bytes(_ decoded: String) -> [UInt8] {
        decoded.utf16.map { UInt8(truncatingIfNeeded: $0) }
    }

    // MARK: - Output

    final class Out: @unchecked Sendable {
        private(set) var lines: [String] = []
        let prefix: String

        init(prefix: String) {
            self.prefix = prefix
        }

        func put(_ path: String, _ value: String) {
            lines.append(JavaIoParityFixture.line(prefix + path, "out", [JavaIoParityFixture.tx(value)]))
        }
    }

    static func pad(_ n: Int) -> String {
        n < 10 ? "0" + String(n) : String(n)
    }

    static func simpleName(_ javaClass: String) -> String {
        String(javaClass.split(separator: ".").last ?? Substring(javaClass))
    }

    /// Java `EXC Class: message` (+ ` <- Cause: message` only for `CatException`), port replaced by `<port>`.
    static func exc(_ error: any Error, port: Int = 0) -> String {
        var cause = ""
        let (name, message): (String, String?)
        switch error {
        case let e as CatException:
            (name, message) = ("CatException", e.message)
            if let c = e.cause {
                let (cn, cm) = javaName(c)
                cause = " <- " + cn + ": " + (cm ?? "null")
            }
        default:
            (name, message) = javaName(error)
        }
        let text = "EXC " + name + ": " + (message ?? "null") + cause
        return port > 0 ? text.replacingOccurrences(of: ":" + String(port), with: ":<port>") : text
    }

    static func javaName(_ error: any Error) -> (String, String?) {
        switch error {
        case let e as CatException: return ("CatException", e.message)
        case let e as JavaSocketError: return (simpleName(e.javaClass), e.message)
        case let e as JavaIOError: return (simpleName(e.javaClass), e.message)
        case let e as JavaIllegalArgumentError: return ("IllegalArgumentException", e.message)
        case let e as CwKeyerError: return (e.kind.rawValue, e.message)
        case let e as JavaNumberFormatError: return ("NumberFormatException", e.message)
        case let e as XmlRpc.Failure: return ("IllegalStateException", e.message)
        case let e as UncheckedIOError: return ("UncheckedIOException", e.message)
        default: return ("Swift." + String(describing: type(of: error)), String(describing: error))
        }
    }

    static func state(_ s: RigState) -> String {
        "S " + String(s.freqHz) + "|" + (s.mode?.rawValue ?? "~") + "|" + s.rawMode + "|" + String(s.passband) + "|"
            + (s.split ? "1" : "0") + "|" + String(s.txFreqHz)
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func latin1(_ bytes: [UInt8]) -> String {
        String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
    }

    static func result(port: Int = 0, _ body: () throws -> String?) -> String {
        do {
            return try body() ?? "ok"
        } catch {
            return exc(error, port: port)
        }
    }

    // MARK: - Items

    /// Runs a section; rows in generator order (scenarios concurrently, each on its own thread).
    static func run(_ section: Section) async throws -> Entry {
        var lines: [String] = []
        if !section.raw.isEmpty {
            lines.append(JavaIoParityFixture.line("/defaults", "in", section.raw.map { JavaIoParityFixture.tx($0) }))
        }
        let outputs: [[String]] = try await withThrowingTaskGroup(of: (Int, [String]).self) { group in
            for (index, scenario) in section.scenarios.enumerated() {
                group.addTask {
                    let out: Out = try await onOwnThread("conversation-" + scenario.name) {
                        let out = Out(prefix: "/" + scenario.name)
                        try runScenario(section, scenario, out)
                        return out
                    }
                    return (index, out.lines)
                }
            }
            var results = [[String]](repeating: [], count: section.scenarios.count)
            for try await (index, rows) in group {
                results[index] = rows
            }
            return results
        }
        for (scenario, rows) in zip(section.scenarios, outputs) {
            lines.append(JavaIoParityFixture.line("/" + scenario.name, "in", scenario.raw.map { JavaIoParityFixture.tx($0) }))
            lines.append(contentsOf: rows)
        }
        let sum = JavaIoParityFixture.checksum(definition: nil, registry: "", lines: lines)
        return Entry(relative: section.name, sha256: sum, lines: lines)
    }

    static func runScenario(_ section: Section, _ scenario: Scenario, _ out: Out) throws {
        switch section.name {
        case "rigctld", "cat-cw", "rig-poller": try rig(section, scenario, out)
        case "rotctld": try rot(section, scenario, out)
        case "fldigi": try fldigi(scenario, out)
        case "n1mm-udp": udp(scenario, out)
        case "otrsp": try otrsp(scenario, out)
        case "winkeyer": winkeyer(scenario, out)
        default: Issue.record("unknown section \(section.name)")
        }
    }

    static func answers(_ section: Section, _ scenario: Scenario) -> [String: [[UInt8]]] {
        var map: [String: [[UInt8]]] = [:]
        for (key, values) in section.defaults {
            map[key] = values.map { bytes($0) }
        }
        for f in scenario.body where f[0] == "ans" {
            map[unesc(f[1])] = f.dropFirst(2).map { bytes(field($0)) }
        }
        return map
    }

    // MARK: - rigctld, CAT CW, poller

    final class ModesBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = HamlibModeMapping.default

        func get() -> HamlibModeMapping {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ v: HamlibModeMapping) {
            lock.lock()
            value = v
            lock.unlock()
        }
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Bool

        init(_ value: Bool) {
            self.value = value
        }

        var get: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ v: Bool) {
            lock.lock()
            value = v
            lock.unlock()
        }
    }

    /// Rig stand-in for `rig=stub`: states, then an error; read count.
    final class StubRig: RigController, @unchecked Sendable {
        private let lock = NSLock()
        private let script: [[String]]
        private var count = 0

        init(_ script: [[String]]) {
            self.script = script
        }

        var reads: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func read() throws -> RigState {
            lock.lock()
            let f = script[min(count, script.count - 1)]
            count += 1
            lock.unlock()
            if f[1] == "fail" {
                throw CatException(field(f[2]))
            }
            return RigState(freqHz: Int64(f[2]) ?? 0, mode: mode(f[3]), rawMode: field(f[4]), passband: Int64(f[5]) ?? 0,
                            split: f[6] == "1", txFreqHz: Int64(f[7]) ?? 0)
        }

        func setFrequencyHz(_ freqHz: Int64) throws {}
        func setMode(_ mode: Mode?, freqHz: Int64) throws {}
        func setPtt(_ on: Bool) throws {}
        func sendMorse(_ text: String) throws {}
        func stopMorse() throws {}
        func setCwSpeed(_ wpm: Int) throws {}
        func isConnected() -> Bool { true }
        func close() {}
    }

    static func mode(_ name: String) -> Mode? {
        name == "~" ? nil : Mode(rawValue: name)
    }

    static func transverters(_ spec: String?) -> [TransverterEntry] {
        guard let spec else { return [] }
        return spec.split(separator: ",").map { t in
            let p = t.split(separator: ":").map(String.init)
            return TransverterEntry(name: "x", ifLowKHz: Int(p[0]) ?? 0, ifHighKHz: Int(p[1]) ?? 0, offsetKHz: Int(p[2]) ?? 0,
                                    enabled: p[3] == "1")
        }
    }

    static func message(_ f: [String], from: Int) -> CwMessage {
        var parts: [CwMessage.Part] = []
        for raw in f.dropFirst(from) {
            let p = field(raw)
            let value = String(p.dropFirst(2))
            switch p.first {
            case "t": parts.append(.text(value))
            case "p": parts.append(.prosign(value))
            default: parts.append(.speed(Int(value) ?? 0))
            }
        }
        return CwMessage(parts: parts)
    }

    struct RigContext {
        let rig: any RigController
        let cw: CatCwKeyer
        let cwRig: Flag
        let modes: ModesBox
        let out: Out
    }

    static func rig(_ section: Section, _ scenario: Scenario, _ out: Out) throws {
        let modes = ModesBox()
        let log = CatTrafficLog(maxLines: 1000)
        let xv = transverters(scenario.options["xvtr"])
        var server: ConversationServer?
        var client: RigctldClient?
        var stub: StubRig?
        let rig: any RigController
        var port = 0
        if scenario.options["rig"] == "stub" {
            let made = StubRig(scenario.body.filter { $0[0] == "stub" })
            stub = made
            rig = made
        } else {
            let made = try ConversationServer(answers: answers(section, scenario), fallback: bytes(section.fallback ?? "RPRT -1\n"))
            server = made
            port = made.port
            if scenario.options["port"] == "free" {
                made.stop()
                port = FreeLoopbackPort.take()
            }
            precondition(port != 4532 && port != 4533, "shared daemon")
            do {
                client = try RigctldClient(host: "localhost", port: port, timeoutMs: clientTimeoutMs, modes: { modes.get() },
                                           log: log)
            } catch {
                out.put("/connect", exc(error, port: port))
                return
            }
            let inner: RigctldClient = client!
            rig = xv.isEmpty ? inner : TransverterRig(inner: inner, transverters: { xv })
        }
        let cwRig = Flag(true)
        let cw = CatCwKeyer(rig: { cwRig.get ? rig : nil })
        let context = RigContext(rig: rig, cw: cw, cwRig: cwRig, modes: modes, out: out)
        var pendingBg: [String]?
        var k = 0
        for f in scenario.body {
            if f[0] == "bg" {
                pendingBg = f
                continue
            }
            guard f[0] == "call" else { continue }
            k += 1
            let path = "/" + pad(k)
            let p = port
            if let bg = pendingBg, let server {
                let done = BgResult()
                server.onCommand(unesc(bg[1])) {
                    let thread = Thread {
                        done.finish(result(port: p) { try rigCall(context, bg, at: 2, path: path + "/bg") })
                    }
                    thread.name = "conversation-bg"
                    thread.start()
                }
                out.put(path, result(port: p) { try rigCall(context, f, at: 1, path: path) })
                out.put(path + "/bg", done.wait())
                pendingBg = nil
            } else {
                out.put(path, result(port: p) { try rigCall(context, f, at: 1, path: path) })
            }
        }
        if let stub {
            out.put("/reads", String(stub.reads))
        } else if let client, let server {
            out.put("/connected", rig.isConnected() ? "true" : "false")
            client.close()
            let sent = server.sent(expected: 1)
            for (i, bytes) in sent.enumerated() {
                out.put("/sent/" + String(i), latin1(bytes))
            }
            for (i, line) in log.snapshot().enumerated() {
                out.put("/log/" + pad(i), String(line.dropFirst(14)))
            }
            server.stop()
        }
    }

    /// Result of a concurrent call (`bg`); without launch (the server did not get the command) `<bg nespuštěno>`.
    final class BgResult: @unchecked Sendable {
        private let condition = NSCondition()
        private var value: String?

        func finish(_ v: String) {
            condition.lock()
            value = v
            condition.broadcast()
            condition.unlock()
        }

        /// Waits on the scenario's own thread (guard 30 s).
        func wait() -> String {
            let deadline = Date(timeIntervalSinceNow: 30)
            condition.lock()
            defer { condition.unlock() }
            while value == nil {
                if !condition.wait(until: deadline) { break }
            }
            return value ?? "<bg nespuštěno>"
        }
    }

    static func rigCall(_ c: RigContext, _ f: [String], at: Int, path: String) throws -> String? {
        let r = c.rig
        func arg(_ i: Int) -> String { f[at + i] }
        func long(_ i: Int) -> Int64 { Int64(arg(i)) ?? 0 }
        func int(_ i: Int) -> Int { Int(arg(i)) ?? 0 }
        switch f[at] {
        case "read": return state(try r.read())
        case "setFrequencyHz": try r.setFrequencyHz(long(1))
        case "setMode": try r.setMode(mode(arg(1)), freqHz: long(2))
        case "setPtt": try r.setPtt(arg(1) == "1")
        case "sendMorse": try r.sendMorse(field(arg(1)))
        case "stopMorse": try r.stopMorse()
        case "setCwSpeed": try r.setCwSpeed(int(1))
        case "setSplit": try r.setSplit(arg(1) == "1", txFreqHz: long(2))
        case "setOtherVfoFrequencyHz": try r.setOtherVfoFrequencyHz(long(1))
        case "setRit": try r.setRit(int(1))
        case "setAntenna": try r.setAntenna(int(1))
        case "selectVfo": try r.selectVfo(arg(1) == "1")
        case "swapVfo": try r.swapVfo()
        case "isConnected": return r.isConnected() ? "true" : "false"
        case "close": r.close()
        case "modes": c.modes.set(HamlibModeMapping(dataMode: mode(arg(1)), rttyAfsk: arg(2) == "1"))
        case "cw.send": try c.cw.send(message(f, from: at + 2), wpm: int(1))
        case "cw.abort": try c.cw.abort()
        case "cw.tune": try c.cw.tune(arg(1) == "1")
        case "cw.setSpeed": try c.cw.setSpeed(int(1))
        case "cw.rig": c.cwRig.set(arg(1) == "1")
        case "cw.name": return c.cw.name()
        case "poll": return poll(r, intervalMs: long(1), out: c.out, path: path)
        default: Issue.record("unknown call \(f[at])")
        }
        return nil
    }

    final class Events: @unchecked Sendable {
        private let condition = NSCondition()
        private var items: [String] = []
        private var failed = false

        func add(_ e: String, failure: Bool = false) {
            condition.lock()
            items.append(e)
            if failure { failed = true }
            condition.broadcast()
            condition.unlock()
        }

        /// Waits for a poll error (guard 30 s) and returns the events.
        func waitForFailure() -> [String] {
            let deadline = Date(timeIntervalSinceNow: 30)
            condition.lock()
            defer { condition.unlock() }
            while !failed {
                if !condition.wait(until: deadline) { break }
            }
            return items
        }
    }

    /// `RigPoller`: states and a single error in order; after the error waits until the poller ends (guard 10 s).
    static func poll(_ r: any RigController, intervalMs: Int64, out: Out, path: String) -> String {
        let events = Events()
        let poller = RigPoller(rig: r, intervalMs: intervalMs, onState: { events.add(state($0)) },
                               onError: { events.add("E " + exc($0), failure: true) })
        poller.start()
        let seen = events.waitForFailure()
        let deadline = Date(timeIntervalSinceNow: 10)
        while poller.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        for (i, e) in seen.enumerated() {
            out.put(path + "/e/" + pad(i), e)
        }
        return "running=" + (poller.isRunning ? "true" : "false")
    }

    // MARK: - rotctld

    static func rot(_ section: Section, _ scenario: Scenario, _ out: Out) throws {
        let server = try ConversationServer(answers: answers(section, scenario), fallback: bytes(section.fallback ?? "RPRT -1\n"))
        var port = server.port
        if scenario.options["port"] == "free" {
            server.stop()
            port = FreeLoopbackPort.take()
        }
        precondition(port != 4532 && port != 4533, "shared daemon")
        let c: RotctldClient
        do {
            c = try RotctldClient(host: "localhost", port: port, timeoutMs: clientTimeoutMs)
        } catch {
            out.put("/connect", exc(error, port: port))
            return
        }
        var k = 0
        for f in scenario.body where f[0] == "call" {
            k += 1
            out.put("/" + pad(k), result {
                switch f[1] {
                case "azimuth": return JavaDouble.toString(try c.azimuth())
                case "turnTo": try c.turnTo(Double(f[2]) ?? .nan)
                case "stop": try c.stop()
                case "close": c.close()
                default: Issue.record("unknown call \(f[1])")
                }
                return nil
            })
        }
        c.close()
        for (i, bytes) in server.sent(expected: 1).enumerated() {
            out.put("/sent/" + String(i), latin1(bytes))
        }
        server.stop()
    }

    // MARK: - fldigi

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            n += 1
            return n - 1
        }
    }

    static func fldigi(_ scenario: Scenario, _ out: Out) throws {
        let replies: [[String]] = scenario.body.filter { $0[0] == "resp" }
        let server = try FakeHttpServer()
        let counter = Counter()
        server.respond { _ in
            let reply = replies[min(counter.next(), replies.count - 1)]
            if reply[1] == "close" {
                return FakeHttpServer.Response(closeWithoutReply: true)
            }
            return FakeHttpServer.Response(status: Int(reply[1]) ?? 0, body: field(reply[2]))
        }
        var port = server.port
        if scenario.options["port"] == "free" {
            server.stop()
            port = FreeLoopbackPort.take()
        }
        let c = try FldigiClient(host: "127.0.0.1", port: port)
        var k = 0
        for f in scenario.body where f[0] == "call" {
            k += 1
            out.put("/" + pad(k), result(port: port) {
                switch f[1] {
                case "version": return try c.version()
                case "modemName": return try c.modemName()
                case "trxState": return try c.trxState()
                case "rxLength": return String(try c.rxLength())
                case "carrier": return String(try c.carrier())
                case "rxText": return try c.rxText(start: Int32(f[2]) ?? 0, length: Int32(f[3]) ?? 0)
                case "setModem": try c.setModem(field(f[2]))
                case "transmit": try c.transmit(field(f[2]))
                case "abort": try c.abort()
                default: Issue.record("unknown call \(f[1])")
                }
                return nil
            })
        }
        server.stop()
        for i in server.requests.indices {
            let head = server.head(i).components(separatedBy: "\r\n")
            var contentType = "~"
            for line in head where line.lowercased().hasPrefix("content-type:") {
                contentType = JavaText.trim(String(line.dropFirst(13)))
            }
            out.put("/req/" + pad(i), head[0] + " | " + contentType + " | " + String(decoding: server.body(i), as: UTF8.self))
        }
    }

    // MARK: - N1MM rotor UDP

    static func udp(_ scenario: Scenario, _ out: Out) {
        let receiver = UdpSenderTests.Receiver()
        var k = 0
        for f in scenario.body where f[0] == "call" {
            k += 1
            let receive = f[3] == "rx"
            let port = receive ? receiver.port : Int(f[3]) ?? 0
            let rotor: String? = f[5] == "~" ? nil : field(f[5])
            let message: String
            switch f[4] {
            case "stop": message = N1mmRotorUdp.stopMessage(rotor: rotor)
            case "turn": message = N1mmRotorUdp.turnMessage(rotor: rotor, azimuth: Double(f[6]) ?? .nan, bandMhz: Int32(f[7]) ?? 0)
            default: message = field(f[5])
            }
            out.put("/" + pad(k), result {
                try N1mmRotorUdp.send(host: f[2], port: port, message: message)
                return receive ? hex(receiver.receive()) : nil
            })
        }
    }

    // MARK: - OTRSP (over a pseudo-terminal)

    static func otrsp(_ scenario: Scenario, _ out: Out) throws {
        let pty = try SerialPortTests.Pty()
        let otrsp = try Otrsp.open(portPath: pty.path, modem: SerialPortTests.FakeModem())
        var k = 0
        for f in scenario.body where f[0] == "call" {
            k += 1
            out.put("/" + pad(k), result {
                let radio = Int32(f[2]) ?? 0
                switch f[1] {
                case "tx": try otrsp.tx(radio)
                case "rx": try otrsp.rx(radio, stereo: f[3] == "1")
                case "focus": try otrsp.focus(radio, stereo: f[3] == "1")
                case "aux": try otrsp.aux(radio, value: Int32(f[3]) ?? 0)
                default: Issue.record("unknown call \(f[1])")
                }
                return nil
            })
        }
        // A barrier via the device side's own descriptor: everything written before it is already on the controller side.
        let sentinel: [UInt8] = [0xFF]
        _ = sentinel.withUnsafeBytes { Darwin.write(pty.slave, $0.baseAddress, 1) }
        var got: [UInt8] = []
        while got.last != 0xFF {
            let chunk = pty.read(1)
            if chunk.isEmpty { break }
            got.append(contentsOf: chunk)
        }
        otrsp.close()
        out.put("/bytes", hex(Array(got.dropLast())))
    }

    // MARK: - Winkeyer

    /// Bytes from the key, then end of stream; writes and closes are recorded.
    final class ScriptTransport: ByteTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var incoming: [UInt8]
        private var written: [UInt8] = []
        private var closes = 0

        init(_ incoming: [UInt8]) {
            self.incoming = incoming
        }

        func read() throws -> Int {
            lock.lock()
            defer { lock.unlock() }
            return incoming.isEmpty ? -1 : Int(incoming.removeFirst())
        }

        func write(_ bytes: [UInt8]) throws {
            lock.lock()
            written.append(contentsOf: bytes)
            lock.unlock()
        }

        func close() throws {
            lock.lock()
            closes += 1
            lock.unlock()
        }

        var sent: [UInt8] {
            lock.lock()
            defer { lock.unlock() }
            return written
        }

        var closeCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return closes
        }
    }

    static func winkeyer(_ scenario: Scenario, _ out: Out) {
        var incoming: [UInt8] = []
        for f in scenario.body where f[0] == "in" {
            let text = field(f[1])
            incoming = text.isEmpty ? [] : text.split(separator: " ").map { UInt8($0, radix: 16) ?? 0 }
        }
        let transport = ScriptTransport(incoming)
        let k = WinkeyerKeyer(transport: transport)
        _ = k.waitForReaderEnd(timeoutMs: 10_000) // end of stream → the reader thread ends, the state is settled
        var n = 0
        for f in scenario.body where f[0] == "call" {
            n += 1
            out.put("/" + pad(n), result {
                switch f[1] {
                case "hostOpen": return String(try k.hostOpen(timeoutMs: Int(f[2]) ?? 0))
                case "busy": return k.isBusy() ? "true" : "false"
                case "name": return k.name()
                case "setSpeed": try k.setSpeed(Int(f[2]) ?? 0)
                case "send": try k.send(message(f, from: 3), wpm: Int(f[2]) ?? 0)
                case "abort": try k.abort()
                case "tune": try k.tune(f[2] == "1")
                case "close": k.close()
                default: Issue.record("unknown call \(f[1])")
                }
                return nil
            })
        }
        out.put("/bytes", hex(transport.sent))
        out.put("/portCloses", String(transport.closeCount))
    }
}

/// Scripted line server of the gate (a mirror of `RigTranscriptGen.LineServer`): reply to the k-th occurrence of a key
/// (the whole command line, otherwise the first word; the last one repeats), `<delay>` = 300 ms pause before writing,
/// `<close>` = close after writing, empty = stay silent; the `onCommand` hook (concurrent call); exact bytes per connection.
final class ConversationServer: @unchecked Sendable {

    private let condition = NSCondition()
    private let answers: [String: [[UInt8]]]
    private let fallback: [UInt8]
    private var seen: [String: Int] = [:]
    private var requests: [Int: [UInt8]] = [:]
    private var ended = 0
    private var triggers: [String: @Sendable () -> Void] = [:]
    private var listener: LoopbackListener!

    init(answers: [String: [[UInt8]]], fallback: [UInt8]) throws {
        self.answers = answers
        self.fallback = fallback
        listener = try LoopbackListener(name: "conversation-server") { [weak self] connection in
            self?.serve(connection)
        }
    }

    deinit {
        listener?.stop()
    }

    var port: Int { listener.port }

    func stop() {
        listener.stop()
    }

    func onCommand(_ command: String, _ action: @escaping @Sendable () -> Void) {
        condition.lock()
        triggers[command] = action
        condition.unlock()
    }

    /// Bytes of the connection after it ends (waits until `expected` connections end; guard 10 s).
    func sent(expected: Int) -> [[UInt8]] {
        let deadline = Date(timeIntervalSinceNow: 10)
        condition.lock()
        defer { condition.unlock() }
        while ended < expected {
            if !condition.wait(until: deadline) { break }
        }
        return requests.keys.sorted().map { requests[$0] ?? [] }
    }

    private func serve(_ connection: LoopbackListener.Connection) {
        condition.lock()
        requests[connection.index] = []
        condition.unlock()
        defer {
            condition.lock()
            ended += 1
            condition.broadcast()
            condition.unlock()
        }
        var line: [UInt8] = []
        while let chunk = connection.receive() {
            for byte in chunk {
                condition.lock()
                requests[connection.index, default: []].append(byte)
                condition.unlock()
                guard byte == 0x0A else {
                    line.append(byte)
                    continue
                }
                let command = RigConversationScripts.latin1(line)
                line = []
                if !respond(command, connection) {
                    return
                }
            }
        }
    }

    /// `false` = close the connection.
    private func respond(_ command: String, _ connection: LoopbackListener.Connection) -> Bool {
        condition.lock()
        let first = String(command.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let key = answers[command] != nil ? command : first
        let n = seen[key, default: 0]
        seen[key] = n + 1
        let list = answers[key]
        var reply: [UInt8] = list.map { $0[min(n, $0.count - 1)] } ?? fallback
        let trigger = triggers.removeValue(forKey: command)
        condition.unlock()
        trigger?()
        let delay: [UInt8] = Array("<delay>".utf8)
        let close: [UInt8] = Array("<close>".utf8)
        if reply.starts(with: delay) {
            Thread.sleep(forTimeInterval: 0.3)
            reply.removeFirst(delay.count)
        }
        let closing = reply.count >= close.count && Array(reply.suffix(close.count)) == close
        if closing {
            reply.removeLast(close.count)
        }
        connection.send(reply)
        return !closing
    }
}
