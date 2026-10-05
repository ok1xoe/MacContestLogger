import Foundation

/// A scripted stand-in for a line server (`rigctld`, `rotctld`) on `127.0.0.1:0`:
/// listens on its own thread, serves each connection on another. A command = the request
/// line without `\n`; the reply is looked up by the whole line, then by the first word (like the Java mock
/// servers `RigctldClientTest`/`Transcript`), otherwise `fallback`. One-shot replies from `enqueue` take
/// precedence (in queuing order).
///
/// Reply steps (`Step`, textually `Step.parse`): a line (`text\n`), `partial <text>` (without `\n`), raw
/// bytes, `delay <ms>`, `silent` (nothing), `close` (close the connection), `reset` (close with RST). Records the **exact bytes** of requests
/// per connection and the split commands.
final class FakeLineServer: @unchecked Sendable {

    enum Step: Equatable, Sendable {
        /// `text` + `\n` (UTF-8).
        case line(String)
        /// `text` without a terminator, as a separate write.
        case partial(String)
        /// Raw bytes (e.g. `\r`, bytes ≥ 0x80).
        case bytes([UInt8])
        /// A pause before the next step.
        case delay(Int)
        /// Explicitly no reply.
        case silent
        /// Close the connection (further steps are not executed).
        case close
        /// Close the connection with RST (`SO_LINGER` 0).
        case reset

        /// `silent`, `close`, `delay 300`, `partial USB`; anything else is a line.
        static func parse(_ text: String) -> Step {
            if text == "silent" { return .silent }
            if text == "close" { return .close }
            if text == "reset" { return .reset }
            if text.hasPrefix("delay "), let ms = Int(text.dropFirst(6)) { return .delay(ms) }
            if text.hasPrefix("partial ") { return .partial(String(text.dropFirst(8))) }
            return .line(text)
        }
    }

    private let lock = NSLock()
    private var script: [String: [Step]]
    private var queued: [(String, [Step])] = []
    private var fallback: [Step]
    private let onConnect: [Step]
    private var requests: [Int: [UInt8]] = [:]
    private var commandLog: [Int: [String]] = [:]
    private var accepted = 0
    private var listener: LoopbackListener!

    /// `onConnect` = steps right after the connection is accepted (before the first command) — for read tests without a query.
    init(script: [String: [Step]] = [:], fallback: [Step] = [.line("RPRT -1")], onConnect: [Step] = []) throws {
        self.script = script
        self.fallback = fallback
        self.onConnect = onConnect
        listener = try LoopbackListener(name: "fake-line-server") { [weak self] connection in
            self?.serve(connection)
        }
    }

    /// The same with text steps (`Step.parse`).
    convenience init(lines: [String: [String]], fallback: [String] = ["RPRT -1"]) throws {
        try self.init(script: lines.mapValues { $0.map(Step.parse) }, fallback: fallback.map(Step.parse))
    }

    deinit {
        listener?.stop()
    }

    var port: Int { listener.port }

    /// Replaces the reply to a command (the whole line or the first word).
    func respond(_ command: String, _ steps: [Step]) {
        lock.lock()
        script[command] = steps
        lock.unlock()
    }

    /// A one-shot reply to the nearest occurrence of the command.
    func enqueue(_ command: String, _ steps: [Step]) {
        lock.lock()
        queued.append((command, steps))
        lock.unlock()
    }

    /// The number of accepted connections. It increases only on the connection thread, i.e. **after** the client `connect` returns —
    /// do not assert it right after connecting, wait for the server's reply first.
    var connectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return accepted
    }

    /// The exact bytes of the requests of connection `index` (from 0).
    func requestBytes(_ index: Int) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        return requests[index] ?? []
    }

    /// The commands of connection `index` in order of arrival.
    func commands(_ index: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return commandLog[index] ?? []
    }

    /// The commands of all connections (per connection).
    var allCommands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return commandLog.keys.sorted().flatMap { commandLog[$0] ?? [] }
    }

    /// Stops the listener and closes open connections.
    func stop() {
        listener.stop()
    }

    private func serve(_ connection: LoopbackListener.Connection) {
        lock.lock()
        accepted += 1
        requests[connection.index] = []
        commandLog[connection.index] = []
        lock.unlock()
        if !perform(onConnect, on: connection) {
            return
        }
        var pending: [UInt8] = []
        while let chunk = connection.receive() {
            lock.lock()
            requests[connection.index, default: []].append(contentsOf: chunk)
            lock.unlock()
            pending.append(contentsOf: chunk)
            while let nl = pending.firstIndex(of: 0x0A) {
                let command = String(decoding: pending[..<nl], as: UTF8.self)
                pending.removeSubrange(...nl)
                if !perform(steps(for: command, connection: connection.index), on: connection) {
                    return
                }
            }
        }
    }

    private func steps(for command: String, connection: Int) -> [Step] {
        lock.lock()
        defer { lock.unlock() }
        commandLog[connection, default: []].append(command)
        let first = String(command.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        if let i = queued.firstIndex(where: { $0.0 == command || $0.0 == first }) {
            return queued.remove(at: i).1
        }
        return script[command] ?? script[first] ?? fallback
    }

    /// Executes the steps; `false` = the connection should be closed.
    private func perform(_ steps: [Step], on connection: LoopbackListener.Connection) -> Bool {
        for step in steps {
            switch step {
            case .line(let text):
                connection.send(Array((text + "\n").utf8))
            case .partial(let text):
                connection.send(Array(text.utf8))
            case .bytes(let bytes):
                connection.send(bytes)
            case .delay(let ms):
                Thread.sleep(forTimeInterval: Double(ms) / 1_000)
            case .silent:
                break
            case .close:
                return false
            case .reset:
                connection.reset()
                return false
            }
        }
        return true
    }
}
