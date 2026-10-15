import Foundation
import MCLCore

/// The built-in RTTY modem's two receivers (DI1 = VFO A / radio 1, DI2 = VFO B / radio 2) and their transmit path:
/// the AFSK audio on a sound output and PTT over CAT. The keyer lane reaches a receiver through `port(_:)`, which
/// answers the same calls as fldigi's XML-RPC, so the Digital Interface, the F-keys, ESM and Esc need no second path.
///
/// Thread-safe: the ports are called on the keyer lane, the output pulls audio on its render thread, and the end of a
/// transmission (output stopped, PTT released, back to receive) runs on the hub's own serial queue.
final class BuiltinModemHub: @unchecked Sendable {

    /// What the hub reads when a transmission starts (set from the main actor).
    struct Settings: Equatable, Sendable {
        /// The transmit level (0.01…1).
        var level: Double = 0.5
        /// The sound output of each side (empty = the system default).
        var devices: [String] = ["", ""]
        /// One tuning for both receivers (`BuiltinModemSetup.linkedTuning`).
        var linked: Bool = false
        /// Built-in FSK keying on a serial port instead of AFSK (`nil` = AFSK).
        var fsk: Fsk?
    }

    /// The FSK port, its keying and PTT lines and the polarity.
    struct Fsk: Equatable, Sendable {
        var port: String
        var line: CwKeyingOptions.SerialLine
        var pttLine: CwKeyingOptions.SerialLine
        var invert: Bool
    }

    let channels: [BuiltinRttyChannel] = [BuiltinRttyChannel(), BuiltinRttyChannel()]
    private let lock = NSLock()
    private var settings = Settings()
    private var streams: [(any ModemAudioStream)?] = [nil, nil]
    /// Raised by every start and end of a side's transmission: a late end of an old stream does not stop a new one.
    private var generations: [Int] = [0, 0]
    private var ptt: VoicePtt?
    private let openOutput: @Sendable (String?, Double, @escaping @Sendable (UnsafeMutableBufferPointer<Float>) -> Void)
        throws -> any ModemAudioStream
    private let queue = DispatchQueue(label: "builtin-modem-tx")
    private let openKeyLines: @Sendable (String, CwKeyingOptions.SerialLine, CwKeyingOptions.SerialLine) throws
        -> any CwKeyLines
    /// The FSK keyer's clock (tests: a clock that does not wait).
    var fskClock: any FskClock = HostFskClock()

    init(hardware: HardwarePorts) {
        openOutput = hardware.openModemOutput
        openKeyLines = hardware.openKeyLines
    }

    private static func clamp(_ side: Int) -> Int {
        min(max(side, 0), 1)
    }

    /// The FSK keying of the options (`nil` = no port set: AFSK).
    static func fsk(_ setup: BuiltinModemSetup) -> Fsk? {
        let port: String = setup.text(.fskPort).trimmingCharacters(in: .whitespaces)
        guard !port.isEmpty else { return nil }
        return Fsk(port: port, line: setup.fskLine, pttLine: setup.fskPttLine, invert: setup.flag(.fskInvert))
    }

    /// The fldigi-like port of a side.
    func port(_ side: Int) -> BuiltinModemPort {
        BuiltinModemPort(hub: self, side: Self.clamp(side))
    }

    func configure(_ settings: Settings) {
        lock.withLock { self.settings = settings }
    }

    var currentSettings: Settings {
        lock.withLock { settings }
    }

    /// The PTT shared with the voice keyer (its rig fencing, the release owed after a lost connection and the quit).
    func usePtt(_ ptt: VoicePtt) {
        lock.withLock { self.ptt = ptt }
    }

    /// Before a transmission (main actor): the rig to key and whether over CAT.
    func arm(lane: RigLane?, viaCat: Bool) {
        let ptt: VoicePtt? = lock.withLock { self.ptt }
        ptt?.arm(target: lane, viaCat: viaCat)
    }

    // MARK: - tuning

    /// A tuning change of a side; with linked tuning the other receiver gets the same change.
    func tune(_ side: Int, _ change: (inout BuiltinRttyChannel.Tuning) -> Void) {
        let side: Int = Self.clamp(side)
        channels[side].update(change)
        if currentSettings.linked {
            channels[1 - side].apply(channels[side].tuning)
        }
    }

    // MARK: - transmit

    /// Transmit on (keyer lane): PTT, then the output pulls the modulator. A failure ends the transmission at once.
    func startTx(_ side: Int) throws {
        let side: Int = Self.clamp(side)
        let channel: BuiltinRttyChannel = channels[side]
        guard channel.txOn() else { return }
        let (settings, ptt, generation): (Settings, VoicePtt?, Int) = lock.withLock {
            generations[side] += 1
            return (self.settings, self.ptt, generations[side])
        }
        if let fsk = settings.fsk {
            try startFsk(side, fsk, channel: channel, ptt: ptt, generation: generation)
            return
        }
        do {
            try ptt?.set(true)
            let level = Float(settings.level)
            let device: String = side < settings.devices.count ? settings.devices[side] : ""
            let stream: any ModemAudioStream = try openOutput(device.isEmpty ? nil : device,
                                                              BuiltinRttyChannel.sampleRate) { [weak self] buffer in
                if !channel.generate(into: buffer, level: level) {
                    self?.ended(side, generation: generation)
                }
            }
            let current: Bool = lock.withLock {
                guard generations[side] == generation else { return false }
                streams[side] = stream
                return true
            }
            if !current {
                stream.stop()
            }
        } catch {
            try? ptt?.set(false)
            channel.finishTx()
            throw error
        }
    }

    /// FSK (MMTTY EXTFSK): the key line of the serial port keyed with the modulator's Baudot codes, PTT on the port's
    /// PTT line or as for AFSK. No audio goes out.
    private func startFsk(_ side: Int, _ fsk: Fsk, channel: BuiltinRttyChannel, ptt: VoicePtt?,
                          generation: Int) throws {
        var lines: (any CwKeyLines)?
        do {
            let opened: any CwKeyLines = try openKeyLines(fsk.port, fsk.line, fsk.pttLine)
            lines = opened
            if opened.hasPtt {
                try opened.setPtt(true)
            } else {
                try ptt?.set(true)
            }
            let baud: Double = channel.tuning.baud
            let keyer = SoftFskKeyer(lines: opened, baud: baud, invert: fsk.invert, clock: fskClock, source: {
                var buffer = [Float](repeating: 0, count: 512)
                let active: Bool = buffer.withUnsafeMutableBufferPointer { channel.generate(into: $0, level: 0) }
                return (channel.takeFskCodes(), !active)
            }, onEnd: { [weak self] in
                self?.ended(side, generation: generation)
            })
            let stream = FskStream(keyer: keyer, lines: opened)
            let current: Bool = lock.withLock {
                guard generations[side] == generation else { return false }
                streams[side] = stream
                return true
            }
            guard current else {
                stream.stop()
                return
            }
            try keyer.start()
        } catch {
            if let lines {
                if lines.hasPtt {
                    try? lines.setPtt(false)
                }
                lines.close()
            }
            lock.withLock {
                if generations[side] == generation {
                    streams[side] = nil
                }
            }
            try? ptt?.set(false)
            channel.finishTx()
            throw error
        }
    }

    /// The modulator ran out (render thread): the end runs on the hub's queue.
    private func ended(_ side: Int, generation: Int) {
        queue.async { [weak self] in
            self?.finish(side, generation: generation)
        }
    }

    private func finish(_ side: Int, generation: Int?) {
        let (stream, ptt, current): ((any ModemAudioStream)?, VoicePtt?, Bool) = lock.withLock {
            guard generation == nil || generations[side] == generation else { return (nil, nil, false) }
            generations[side] += 1
            let stream = streams[side]
            streams[side] = nil
            return (stream, self.ptt, true)
        }
        guard current else { return }
        stream?.stop()
        try? ptt?.set(false)
        channels[side].finishTx()
    }

    /// Esc (fldigi `main.abort`): the transmission ends now.
    func abort(_ side: Int) {
        let side: Int = Self.clamp(side)
        if channels[side].abort() {
            finish(side, generation: nil)
        }
    }

    /// Waits for the ends queued before (tests).
    func settle() {
        queue.sync {}
    }

    /// The quit: both sides stop transmitting.
    func shutdown() {
        abort(0)
        abort(1)
        settle()
    }
}

/// The FSK keyer and its port as a transmit stream: stopping it stops the keyer, releases the port's PTT line and
/// closes the port.
final class FskStream: ModemAudioStream, @unchecked Sendable {
    private let keyer: SoftFskKeyer
    private let lines: any CwKeyLines
    private let lock = NSLock()
    private var stopped = false

    init(keyer: SoftFskKeyer, lines: any CwKeyLines) {
        self.keyer = keyer
        self.lines = lines
    }

    func stop() {
        guard lock.withLock({ () -> Bool in
            defer { stopped = true }
            return !stopped
        }) else { return }
        keyer.stop()
        if lines.hasPtt {
            try? lines.setPtt(false)
        }
        lines.close()
    }
}

/// One receiver of the built-in modem behind fldigi's calls (`FldigiPort`), used by the keyer lane.
final class BuiltinModemPort: FldigiPort, @unchecked Sendable {
    private let hub: BuiltinModemHub
    let side: Int

    init(hub: BuiltinModemHub, side: Int) {
        self.hub = hub
        self.side = side
    }

    private var channel: BuiltinRttyChannel {
        hub.channels[side]
    }

    func transmit(_ text: String) throws {
        try transmit(text, returnToRx: true, clearFirst: true)
    }

    func transmit(_ text: String, returnToRx: Bool, clearFirst: Bool) throws {
        if clearFirst {
            channel.clearTx()
        }
        channel.addTx(text + (returnToRx ? "^r" : ""))
        try hub.startTx(side)
    }

    func trxState() throws -> String {
        channel.trxState
    }

    func abort() throws {
        hub.abort(side)
        channel.clearTx()
    }

    func rxLength() throws -> Int32 {
        channel.rxLength
    }

    func rxText(start: Int32, length: Int32) throws -> String {
        channel.rxText(start: start, length: length)
    }

    func modemName() throws -> String {
        channel.modeName
    }

    func carrier() throws -> Int32 {
        Int32(channel.tuning.centreHz.rounded())
    }

    func modemNames() throws -> [String] {
        BuiltinRttyChannel.modes.map(\.name)
    }

    func setModem(_ name: String) throws {
        guard let mode = BuiltinRttyChannel.modes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else {
            throw KeyingFailure(message: name + ": " + DigitalTexts.builtinOnlyRtty)
        }
        hub.tune(side) { $0.baud = mode.baud }
    }

    func addTx(_ text: String) throws {
        channel.addTx(text)
    }

    func txOn() throws {
        try hub.startTx(side)
    }

    func clearTx() throws {
        channel.clearTx()
    }

    func isOn(_ toggle: FldigiClient.Switch) throws -> Bool {
        let tuning: BuiltinRttyChannel.Tuning = channel.tuning
        switch toggle {
        case .afc: return tuning.afc
        case .lock: return !tuning.net
        case .reverse: return tuning.reverse
        }
    }

    func set(_ toggle: FldigiClient.Switch, _ on: Bool) throws {
        hub.tune(side) { tuning in
            switch toggle {
            case .afc: tuning.afc = on
            case .lock: tuning.net = !on
            case .reverse: tuning.reverse = on
            }
        }
    }

    func setCarrier(_ hz: Int) throws {
        hub.tune(side) { $0.markHz = Double(hz) - $0.shiftHz / 2 }
    }
}
