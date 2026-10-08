import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// A CW keyer that records what it is asked (nothing is keyed). `send` can be held until `release()` (a slow keyer)
/// and any call can be made to fail.
final class FakeCwKeyer: CwKeyer, @unchecked Sendable {
    private let lock = NSCondition()
    private var log: [String] = []
    private var holding = false
    private var failure: String?
    private var tuneFailure: String?

    /// The calls in order: `send TEXT@wpm`, `abort`, `speed N`, `tune on|off`, `close`.
    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    func failWith(_ message: String?) {
        lock.lock()
        failure = message
        lock.unlock()
    }

    /// The next `tune` call fails once.
    func failNextTune(_ message: String) {
        lock.lock()
        tuneFailure = message
        lock.unlock()
    }

    /// `send` blocks (on the keyer lane) until `release()`.
    func hold() {
        lock.lock()
        holding = true
        lock.unlock()
    }

    func release() {
        lock.lock()
        holding = false
        lock.broadcast()
        lock.unlock()
    }

    private func record(_ event: String) throws {
        lock.lock()
        defer { lock.unlock() }
        log.append(event)
        if let failure {
            throw CwKeyerError(.illegalState, failure)
        }
    }

    func send(_ message: CwMessage, wpm: Int) throws {
        lock.lock()
        while holding {
            lock.wait()
        }
        lock.unlock()
        try record("send " + message.plainText() + "@" + String(wpm))
    }

    func abort() throws {
        try record("abort")
    }

    func setSpeed(_ wpm: Int) throws {
        try record("speed " + String(wpm))
    }

    func tune(_ on: Bool) throws {
        lock.lock()
        let once: String? = tuneFailure
        tuneFailure = nil
        lock.unlock()
        try record(on ? "tune on" : "tune off")
        if let once {
            throw CwKeyerError(.io, once)
        }
    }

    func name() -> String {
        "Fake"
    }

    func close() {
        lock.lock()
        log.append("close")
        lock.unlock()
    }
}

/// A message recording that writes nothing (the input never opens).
final class FakeRecording: MessageRecording, @unchecked Sendable {
    let target: JavaPath
    private let lock = NSLock()
    private var calls: [String] = []
    private let stopFailure: String?

    init(target: JavaPath, stopFailure: String? = nil) {
        self.target = target
        self.stopFailure = stopFailure
    }

    var events: [String] {
        lock.withLock { calls }
    }

    func stop() throws {
        lock.withLock { calls.append("stop") }
        if let stopFailure {
            throw AudioIOError(stopFailure)
        }
    }

    func cancel() {
        lock.withLock { calls.append("cancel") }
    }
}

/// The keying hardware of a test: the CW keyer, the voice output and recording, speech, fldigi and the receiver audio
/// are fakes; everything is recorded in one ordered log (with the CAT PTT of the fake rig it shows the order of a
/// voice message). Nothing real is opened, keyed, played or recorded.
final class FakeKeyingHardware: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    private var keyers: [FakeCwKeyer] = []
    private var recordings: [FakeRecording] = []
    private var winkeyerFailure: String?
    private var audioFailure: String?
    private var recordFailure: String?
    private var recordStopFailure: String?
    private var microphoneAllowed = true
    private var playFailure: String?
    private var played: [[UInt8]] = []
    private var audioGeneration: UInt64?
    private let speechGate = NSCondition()
    private var speechHeld = false
    private var playProbe: (@Sendable () -> String)?
    private let audioStartGate = NSCondition()
    private var audioStartHeld = false
    private let playbackGate = NSCondition()
    private var playbackHeld = false
    private let delayGate = NSCondition()
    private var delayHeld = false
    /// The fake fldigi server's port (loopback only).
    var fldigiPort: Int?

    /// The generation of the last started (deviceless) capture: blocks are fed with `capture.accept`.
    var lastAudioGeneration: UInt64? {
        lock.withLock { audioGeneration }
    }

    /// Speech synthesis blocks (on the voice lane) until `releaseSpeech()`.
    func holdSpeech() {
        speechGate.lock()
        speechHeld = true
        speechGate.unlock()
    }

    func releaseSpeech() {
        speechGate.lock()
        speechHeld = false
        speechGate.broadcast()
        speechGate.unlock()
    }

    /// The receiver audio's start blocks (on the audio lane, after its event is recorded) until
    /// `releaseAudioStart()`.
    func holdAudioStart() {
        audioStartGate.lock()
        audioStartHeld = true
        audioStartGate.unlock()
    }

    func releaseAudioStart() {
        audioStartGate.lock()
        audioStartHeld = false
        audioStartGate.broadcast()
        audioStartGate.unlock()
    }

    /// Every voice `play` (after its event is recorded) stays on the air on the voice keyer's queue until the message
    /// is cancelled — Esc, a newer message, a disconnect or the quit — or `releasePlayback()`: a message never ends by
    /// itself, however long a loaded runner takes to look. Bounded (two minutes) only so that a failing test does not
    /// hold the queue's thread for good.
    func holdPlayback() {
        playbackGate.lock()
        playbackHeld = true
        playbackGate.unlock()
    }

    func releasePlayback() {
        playbackGate.lock()
        playbackHeld = false
        playbackGate.broadcast()
        playbackGate.unlock()
    }

    /// The voice keyer's PTT delay lasts until the message is cancelled (Esc, a newer message, a disconnect, the quit)
    /// or `releasePttDelay()` — whatever the configured delay, so "nothing played after the stop" holds however slow
    /// the runner is. Bounded (two minutes) only so that a failing test does not hold the queue's thread for good.
    func holdPttDelay() {
        delayGate.lock()
        delayHeld = true
        delayGate.unlock()
    }

    func releasePttDelay() {
        delayGate.lock()
        delayHeld = false
        delayGate.broadcast()
        delayGate.unlock()
    }

    /// The PTT delay: held (see `holdPttDelay`), otherwise `ms` or until cancelled, polled every 10 ms like the real
    /// wait.
    private func pttDelay(_ ms: Int64, _ cancelled: () -> Bool) {
        let held: Date = Date(timeIntervalSinceNow: 120)
        let normal: Date = Date(timeIntervalSinceNow: Double(max(ms, 0)) / 1000)
        delayGate.lock()
        defer { delayGate.unlock() }
        while !cancelled() {
            let deadline: Date = delayHeld ? held : normal
            if Date() >= deadline {
                return
            }
            _ = delayGate.wait(until: min(deadline, Date(timeIntervalSinceNow: 0.01)))
        }
    }

    /// Waits while the playback is held, checking `cancelled` every 10 ms like the real output.
    private func waitWhilePlaybackHeld(_ cancelled: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 120)
        playbackGate.lock()
        defer { playbackGate.unlock() }
        while playbackHeld && !cancelled() && Date() < deadline {
            _ = playbackGate.wait(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    /// Appended to every `play` event (the PTT state at that moment).
    func probePlay(_ probe: @escaping @Sendable () -> String) {
        lock.withLock { playProbe = probe }
    }

    var events: [String] {
        lock.withLock { log }
    }

    var openedKeyers: [FakeCwKeyer] {
        lock.withLock { keyers }
    }

    var lastKeyer: FakeCwKeyer? {
        openedKeyers.last
    }

    var messageRecordings: [FakeRecording] {
        lock.withLock { recordings }
    }

    /// The PCM handed to the playback (one entry per playback).
    var playedPcm: [[UInt8]] {
        lock.withLock { played }
    }

    func record(_ event: String) {
        lock.withLock { log.append(event) }
    }

    func failWinkeyer(_ message: String?) {
        lock.withLock { winkeyerFailure = message }
    }

    func failAudio(_ message: String?) {
        lock.withLock { audioFailure = message }
    }

    func failRecording(_ message: String?) {
        lock.withLock { recordFailure = message }
    }

    /// The system's microphone permission: `false` = denied.
    func allowMicrophone(_ allowed: Bool) {
        lock.withLock { microphoneAllowed = allowed }
    }

    func failRecordingStop(_ message: String?) {
        lock.withLock { recordStopFailure = message }
    }

    func failPlayback(_ message: String?) {
        lock.withLock { playFailure = message }
    }

    /// `base` (the rig fakes) with the keying ports replaced by these fakes.
    func ports(over base: HardwarePorts) -> HardwarePorts {
        var ports: HardwarePorts = base
        ports.openWinkeyer = { [self] port, wpm in
            record("winkeyer open \(port) \(wpm)")
            if let failure = lock.withLock({ winkeyerFailure }) {
                throw CwKeyerError(.io, failure)
            }
            let keyer = FakeCwKeyer()
            lock.withLock { keyers.append(keyer) }
            return keyer
        }
        ports.voicePttDelay = { [self] ms, cancelled in
            pttDelay(ms, cancelled)
        }
        ports.voicePlayer = { [self] device in
            { [self] file, cancelled in
                let probe: String = lock.withLock { playProbe }?() ?? ""
                record("play \(file.description.split(separator: "/").last ?? "") on \(device() ?? "-")" + probe)
                if cancelled() {
                    return
                }
                if let failure = lock.withLock({ playFailure }) {
                    throw AudioIOError(failure)
                }
                waitWhilePlaybackHeld(cancelled)
            }
        }
        ports.recordMessage = { [self] target, device in
            record("record \(target.description.split(separator: "/").last ?? "") from \(device ?? "-")")
            if let failure = lock.withLock({ recordFailure }) {
                throw AudioIOError("Záznamové zařízení není dostupné: " + failure)
            }
            let recording = FakeRecording(target: target, stopFailure: lock.withLock { recordStopFailure })
            lock.withLock { recordings.append(recording) }
            return recording
        }
        ports.microphoneAccess = { [self] in
            record("microphone access")
            return lock.withLock { microphoneAllowed }
        }
        ports.synthesize = { [self] _, _, text in
            speechGate.lock()
            while speechHeld {
                speechGate.wait()
            }
            speechGate.unlock()
            record("say " + text)
            return nil
        }
        ports.makeFldigi = { [self] _, _ in
            guard let port = fldigiPort else { throw JavaIOError(nil, javaClass: "java.net.ConnectException") }
            guardTestPort(port)
            return try FldigiClient(host: "127.0.0.1", port: port, connectTimeoutMs: 5_000, requestTimeoutMs: 5_000)
        }
        ports.startAudio = { [self] capture, device throws(AudioIOError) in
            record("audio start \(device ?? "-")")
            audioStartGate.lock()
            while audioStartHeld {
                audioStartGate.wait()
            }
            audioStartGate.unlock()
            if let failure = lock.withLock({ audioFailure }) {
                throw AudioIOError("Zvukový vstup není dostupný: " + failure)
            }
            let generation: UInt64 = capture.startWithoutDevice()
            lock.withLock { audioGeneration = generation }
        }
        ports.playPcm = { [self] bytes, _, _, _ throws(AudioIOError) in
            if let failure = lock.withLock({ playFailure }) {
                throw AudioIOError(failure)
            }
            lock.withLock { played.append(bytes) }
        }
        return ports
    }
}

/// A fake fldigi XML-RPC server on `127.0.0.1` (an ephemeral port, never 4532/4533): answers every method by the
/// responder and records the method names. One thread accepts and serves, never in Swift's shared pool.
final class FakeFldigiServer: @unchecked Sendable {
    let port: Int
    private let socket: Int32
    private let lock = NSLock()
    private var calls: [String] = []
    private var stopped = false
    private var responder: @Sendable (String) -> (status: Int, value: String)

    init(responder: @escaping @Sendable (String) -> (status: Int, value: String) = { _ in (200, "") }) throws {
        self.responder = responder
        let fd: Int32 = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound: Int32 = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        socket = fd
        port = Int(UInt16(bigEndian: actual.sin_port))
        guardTestPort(port)
        let thread = Thread { [self] in acceptLoop() }
        thread.name = "fake-fldigi"
        thread.start()
    }

    deinit {
        stop()
    }

    /// The XML-RPC methods called so far.
    var methods: [String] {
        lock.withLock { calls }
    }

    func respond(_ responder: @escaping @Sendable (String) -> (status: Int, value: String)) {
        lock.withLock { self.responder = responder }
    }

    func stop() {
        let wasStopped: Bool = lock.withLock { () -> Bool in
            let was = stopped
            stopped = true
            return was
        }
        if wasStopped {
            return
        }
        let wake: Int32 = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard wake >= 0 else { return }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(wake, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        close(wake)
    }

    private func acceptLoop() {
        while true {
            let client: Int32 = accept(socket, nil, nil)
            let isStopped: Bool = lock.withLock { stopped }
            if client < 0 || isStopped {
                if client >= 0 {
                    close(client)
                }
                close(socket)
                return
            }
            var on: Int32 = 1
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 10, tv_usec: 0)
            _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            serve(client)
            close(client)
        }
    }

    private func serve(_ client: Int32) {
        var request: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let text = String(decoding: request, as: UTF8.self)
            if let end = text.range(of: "\r\n\r\n") {
                let head: String = String(text[..<end.lowerBound])
                let length: Int = Self.contentLength(head)
                let bodyBytes: Int = request.count - text.utf8.distance(from: text.startIndex, to: end.upperBound)
                if bodyBytes >= length {
                    break
                }
            }
            let count: Int = read(client, &buffer, buffer.count)
            if count <= 0 {
                return
            }
            request.append(contentsOf: buffer[0..<count])
        }
        let text = String(decoding: request, as: UTF8.self)
        let method: String = Self.methodName(text)
        let responder = lock.withLock { () -> @Sendable (String) -> (status: Int, value: String) in
            calls.append(method)
            return self.responder
        }
        let answer = responder(method)
        let body: String = "<?xml version=\"1.0\"?><methodResponse><params><param><value><string>" + answer.value
            + "</string></value></param></params></methodResponse>"
        let bytes: [UInt8] = Array(body.utf8)
        var reply: String = "HTTP/1.1 \(answer.status) X\r\n"
        reply += "Content-Type: text/xml\r\n"
        reply += "Content-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        let all: [UInt8] = Array(reply.utf8) + bytes
        var offset = 0
        while offset < all.count {
            let written: Int = all[offset...].withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
            if written <= 0 {
                return
            }
            offset += written
        }
    }

    private static func contentLength(_ head: String) -> Int {
        for line in head.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private static func methodName(_ text: String) -> String {
        guard let start = text.range(of: "<methodName>"),
              let end = text.range(of: "</methodName>", range: start.upperBound..<text.endIndex) else { return "" }
        return String(text[start.upperBound..<end.lowerBound])
    }
}

/// An app over a temporary data directory with fake rig and keying hardware, the live keyer behind the entry window
/// and a manual keyer clock.
@MainActor
struct KeyingApp {
    let app: TestApp
    let hardware: FakeHardware
    let keying: FakeKeyingHardware
    let clock: ManualClock
    /// The refresh clock of the radio tool windows (CW reader, waterfall, digital interface).
    let radioClock: ManualClock

    var model: AppModel { app.model }
    var keyer: KeyerModel { app.model.keyer }
    var entry: EntryModel { app.model.entry }
    var status: String { app.model.status.message }

    static func make(configure: @escaping (inout AppConfig, URL) throws -> Void = { _, _ in },
                     setUp: (FakeKeyingHardware) -> Void = { _ in },
                     adjust: (inout AppModel.Environment) -> Void = { _ in },
                     pollIntervalMs: Int64? = nil) async throws -> KeyingApp {
        let hardware = FakeHardware(pollIntervalMs: pollIntervalMs)
        let keying = FakeKeyingHardware()
        setUp(keying)
        let clock = ManualClock()
        let radioClock = ManualClock()
        let app = try await TestApp.make(configure: configure, adjust: { environment in
            environment.hardware = keying.ports(over: hardware.ports)
            environment.keyerClock = clock
            environment.rotatorClock = ManualClock()
            environment.radioWindowClock = radioClock
            adjust(&environment)
        })
        return KeyingApp(app: app, hardware: hardware, keying: keying, clock: clock, radioClock: radioClock)
    }

    /// Waits for the keyer, voice, audio and recording lanes and lets their results run on the main actor.
    func settle() async {
        await keyer.settle()
        await model.audio.settle()
        await model.recording.settle()
        await runMainQueue()
        await keyer.settle()
        await runMainQueue()
    }

    /// Connects rig 1 to `fake` and waits for its first state.
    func connectRig(_ fake: FakeRigctld) async {
        model.rig.toggle(vfo: 0)
        await eventually("rig connected") { model.rig.snapshot(vfo: 0).state != nil }
        _ = fake
    }
}

/// A Winkeyer configuration on a fake port (the port is only a name for the fake opener).
func winkeyerConfig(_ config: inout AppConfig) {
    config.cwKeyer.method = .winkeyer
    config.cwKeyer.winkeyerPort = "fake-winkeyer"
}
