import Foundation

/// The modem lines a simple transistor interface keys (N1MM CW/Other port with DTR/RTS set to CW or PTT).
/// `SerialKeyLines` drives a real serial port; tests pass a recording fake.
public protocol CwKeyLines: AnyObject, Sendable {
    /// A line is assigned to PTT.
    var hasPtt: Bool { get }
    func setKey(_ down: Bool) throws
    func setPtt(_ on: Bool) throws
    func close()
}

/// The waits of the element scheduler. `begin` starts a timeline; each `wait` ends `ms` after the end of the
/// previous one (no drift). `false` = `cancelled` became true or `wake` was called with it true.
public protocol CwSleeper: AnyObject, Sendable {
    func begin()
    func wait(_ ms: Double, cancelled: @escaping () -> Bool) -> Bool
    func wake()
}

/// The real scheduler clock: monotonic deadlines on a condition, woken early by `wake`.
public final class MonotonicCwSleeper: CwSleeper, @unchecked Sendable {
    private let condition = NSCondition()
    private var deadline: UInt64 = 0

    public init() {}

    public func begin() {
        condition.lock()
        deadline = DispatchTime.now().uptimeNanoseconds
        condition.unlock()
    }

    public func wait(_ ms: Double, cancelled: @escaping () -> Bool) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let now: UInt64 = DispatchTime.now().uptimeNanoseconds
        // A late start (the thread was not scheduled) does not shorten the element.
        deadline = max(deadline, now &- 2_000_000) &+ UInt64(max(0, ms) * 1_000_000)
        while true {
            if cancelled() {
                return false
            }
            let current: UInt64 = DispatchTime.now().uptimeNanoseconds
            if current >= deadline {
                return true
            }
            let left = Double(deadline - current) / 1_000_000_000
            _ = condition.wait(until: Date(timeIntervalSinceNow: left))
        }
    }

    public func wake() {
        condition.lock()
        condition.broadcast()
        condition.unlock()
    }
}

/// The DTR/RTS lines of a serial port: the port opens with both lines low (nothing keyed), the chosen line keys
/// CW, the other (optional) one keys PTT.
public final class SerialKeyLines: CwKeyLines, @unchecked Sendable {
    private let port: SerialPort
    private let keyLine: CwKeyingOptions.SerialLine
    private let pttLine: CwKeyingOptions.SerialLine

    init(port: SerialPort, keyLine: CwKeyingOptions.SerialLine, pttLine: CwKeyingOptions.SerialLine) {
        self.port = port
        self.keyLine = keyLine
        self.pttLine = pttLine == keyLine ? .none : pttLine
    }

    /// Opens `path` (9600 8N1, DTR and RTS low right after opening).
    public static func open(path: String, keyLine: CwKeyingOptions.SerialLine,
                            pttLine: CwKeyingOptions.SerialLine) throws -> SerialKeyLines {
        let settings = SerialPort.Settings(baud: 9_600, dtr: false, rts: false)
        let port: SerialPort = try SerialPort.open(path: path, settings: settings)
        try? port.setDTR(false)
        try? port.setRTS(false)
        return SerialKeyLines(port: port, keyLine: keyLine, pttLine: pttLine)
    }

    public var hasPtt: Bool {
        pttLine != .none
    }

    public func setKey(_ down: Bool) throws {
        try set(keyLine, down)
    }

    public func setPtt(_ on: Bool) throws {
        try set(pttLine, on)
    }

    private func set(_ line: CwKeyingOptions.SerialLine, _ on: Bool) throws {
        switch line {
        case .none: return
        case .dtr: try port.setDTR(on)
        case .rts: try port.setRTS(on)
        }
    }

    public func close() {
        try? port.setDTR(false)
        try? port.setRTS(false)
        try? port.close()
    }
}

/// CW keyed on a serial port's DTR or RTS line (N1MM "CW keying via serial port"), with PTT on the other line
/// and/or by the rig's CAT command, a PTT delay before the first element and a PTT tail after the last one.
///
/// `send` only queues the element sequence; the keyer's own thread plays it through the injected sleeper, so the
/// caller (the keyer lane) never blocks. Messages queued back to back keep PTT on between them. `abort` stops at
/// once: key up, PTT off. Every exit of the thread (abort, close, a line error) leaves the key up and PTT off.
public final class SerialCwKeyer: CwKeyer, @unchecked Sendable {

    private enum Job {
        case message([CwElement])
        case tune(Bool)
        case release
    }

    private let lines: any CwKeyLines
    private let catPtt: (@Sendable (Bool) throws -> Void)?
    private let sleeper: any CwSleeper
    private let condition = NSCondition()
    private var queue: [Job] = []
    private var generation: Int64 = 0
    private var closed = false
    private var working = false
    private var ended = false
    private var failure: String?
    private var options: CwKeyingOptions

    // Only touched on the keyer thread.
    private var keyDown = false
    private var pttOn = false

    public init(lines: any CwKeyLines, catPtt: (@Sendable (Bool) throws -> Void)?, sleeper: any CwSleeper,
                options: CwKeyingOptions = CwKeyingOptions()) {
        self.lines = lines
        self.catPtt = catPtt
        self.sleeper = sleeper
        self.options = options.normalized()
        let thread = Thread { [self] in run() }
        thread.name = "cw-serial-keyer"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func send(_ message: CwMessage, wpm: Int) throws {
        condition.lock()
        defer { condition.unlock() }
        if let failure {
            self.failure = nil
            throw CwKeyerError(.uncheckedIO, failure)
        }
        let elements: [CwElement] = CwElements.sequence(message, wpm: wpm, weight: options.weight,
                                                        contestSpacing: options.contestSpacing)
        if elements.isEmpty || closed {
            return
        }
        queue.append(.message(elements))
        condition.broadcast()
    }

    public func abort() throws {
        replaceQueue(with: .release)
    }

    public func tune(_ on: Bool) throws {
        replaceQueue(with: on ? .tune(true) : .release)
    }

    /// The speed travels with every message.
    public func setSpeed(_ wpm: Int) throws {}

    public func configure(_ options: CwKeyingOptions, potSpeed: (@Sendable (Int) -> Void)?) throws {
        condition.lock()
        self.options = options.normalized()
        condition.unlock()
    }

    public func name() -> String {
        "DTR/RTS"
    }

    /// A message or tune is being keyed or waits in the queue.
    public func isBusy() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return working || !queue.isEmpty
    }

    /// Stops keying (key up, PTT off), ends the thread and closes the lines.
    public func close() {
        condition.lock()
        if closed {
            condition.unlock()
            return
        }
        closed = true
        queue.removeAll()
        generation &+= 1
        condition.broadcast()
        condition.unlock()
        sleeper.wake()
        condition.lock()
        while !ended {
            condition.wait()
        }
        condition.unlock()
        lines.close()
    }

    /// Waits until nothing is keyed or queued (tests); `false` = the safety guard expired.
    func waitUntilIdle(timeoutMs: Int = 30_000) -> Bool {
        let guardDate = Date(timeIntervalSinceNow: Double(timeoutMs) / 1_000)
        condition.lock()
        defer { condition.unlock() }
        while working || !queue.isEmpty {
            if !condition.wait(until: guardDate) {
                return false
            }
        }
        return true
    }

    private func replaceQueue(with job: Job) {
        condition.lock()
        queue = closed ? [] : [job]
        generation &+= 1
        condition.broadcast()
        condition.unlock()
        sleeper.wake()
    }

    // MARK: - keyer thread

    private func run() {
        while let (job, myGeneration, setup) = nextJob() {
            let cancelled: () -> Bool = { [self] in
                condition.lock()
                defer { condition.unlock() }
                return generation != myGeneration || closed
            }
            do {
                switch job {
                case .message(let elements):
                    try play(elements, setup: setup, cancelled: cancelled)
                case .tune(let on):
                    if on {
                        try pttOnWithDelay(setup, cancelled: cancelled)
                        if !cancelled() {
                            try key(true)
                        }
                    } else {
                        try releaseAll()
                    }
                case .release:
                    try releaseAll()
                }
            } catch {
                fail(error)
            }
            condition.lock()
            working = false
            condition.broadcast()
            condition.unlock()
        }
        try? releaseAll(force: true)
        condition.lock()
        ended = true
        working = false
        condition.broadcast()
        condition.unlock()
    }

    private func nextJob() -> (Job, Int64, CwKeyingOptions)? {
        condition.lock()
        defer { condition.unlock() }
        while queue.isEmpty && !closed {
            condition.wait()
        }
        if closed {
            return nil
        }
        working = true
        return (queue.removeFirst(), generation, options)
    }

    private var hasPtt: Bool {
        lines.hasPtt || catPtt != nil
    }

    private func play(_ elements: [CwElement], setup: CwKeyingOptions, cancelled: @escaping () -> Bool) throws {
        if pttOn {
            sleeper.begin()
        } else {
            try pttOnWithDelay(setup, cancelled: cancelled)
        }
        for element in elements {
            if cancelled() {
                break
            }
            try key(element.keyDown)
            if !sleeper.wait(element.ms, cancelled: cancelled) {
                break
            }
        }
        try key(false)
        if cancelled() {
            try releaseAll()
            return
        }
        guard pttOn else { return }
        // The tail; a message queued meanwhile keeps PTT on.
        let nextQueued: () -> Bool = { [self] in
            condition.lock()
            defer { condition.unlock() }
            return !queue.isEmpty
        }
        if !nextQueued() {
            _ = sleeper.wait(Double(setup.serialPttTailMs)) { cancelled() || nextQueued() }
        }
        if !nextQueued() || cancelled() {
            try ptt(false)
        }
    }

    private func pttOnWithDelay(_ setup: CwKeyingOptions, cancelled: @escaping () -> Bool) throws {
        sleeper.begin()
        guard hasPtt, !pttOn else { return }
        try ptt(true)
        _ = sleeper.wait(Double(setup.serialPttDelayMs), cancelled: cancelled)
    }

    private func key(_ down: Bool) throws {
        if down == keyDown {
            return
        }
        try lines.setKey(down)
        keyDown = down
    }

    private func ptt(_ on: Bool) throws {
        if on == pttOn {
            return
        }
        pttOn = on
        if lines.hasPtt {
            try lines.setPtt(on)
        }
        if let catPtt {
            try catPtt(on)
        }
    }

    /// Key up and PTT off; both are attempted even when the first fails. `force` sends key up even when the key
    /// is believed up (after a line error, and when the thread ends).
    private func releaseAll(force: Bool = false) throws {
        var firstError: (any Error)?
        do {
            if force {
                keyDown = true
            }
            try key(false)
        } catch {
            firstError = error
        }
        if pttOn {
            pttOn = false
            if lines.hasPtt {
                do { try lines.setPtt(false) } catch { firstError = firstError ?? error }
            }
            if let catPtt {
                do { try catPtt(false) } catch { firstError = firstError ?? error }
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private func fail(_ error: any Error) {
        try? releaseAll(force: true)
        let message: String = (error as? ByteTransportError)?.description
            ?? (error as? CwKeyerError)?.message ?? String(describing: error)
        condition.lock()
        failure = "Klíčování DTR/RTS selhalo: " + message
        queue.removeAll()
        condition.unlock()
    }
}
