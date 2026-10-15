import Foundation
import ModemKit
import RTTYModem

/// One receiver of the built-in RTTY modem (N1MM embeds MMTTY; MCL runs MMTTY's core vendored from RYRY): the modem,
/// the received text as a growing buffer read like fldigi's (`rxLength` / `rxText`), the transmit state and the latest
/// spectrum for the waterfall. The Digital Interface talks to it through the same port as to fldigi, so the window,
/// the F-keys, ESM, Esc, Align, AFC/NET/Rev and AutoTRXUpdate work the same with either modem.
///
/// Thread-safe: the receive audio arrives on the capture queue, the transmit audio is pulled on the output's
/// render thread, the port's calls come from the keyer lane and the view reads the snapshot on the main actor — every
/// access to the (not thread-safe) modem is under one lock.
public final class BuiltinRttyChannel: @unchecked Sendable {

    /// The modem's rate: the shared receiver capture's rate (`AudioCapture.sampleRate`), which MMTTY supports natively.
    public static let sampleRate: Double = 12_000
    /// The modes offered in the Digital Interface's Op Mode menu (fldigi's names: `RTTY` is 45.45 Bd).
    public static let modes: [(name: String, baud: Double)] = [
        ("RTTY", 45.45), ("RTTY-50", 50), ("RTTY-75", 75), ("RTTY-100", 100), ("RTTY-110", 110),
    ]
    /// The shifts offered (Hz).
    public static let shifts: [Double] = [170, 200, 425, 850]
    /// The received text kept (UTF-16 units); older text is dropped from the front (the window keeps 4000).
    static let maxText = 65_536

    /// The tuning of the receiver: mark, shift, speed and the switches.
    public struct Tuning: Equatable, Sendable {
        public var markHz: Double = 2125
        public var shiftHz: Double = 170
        public var baud: Double = 45.45
        public var afc: Bool = true
        /// MMTTY NET: the transmit frequency follows the receive one (AFC). fldigi's Lock is NET off.
        public var net: Bool = true
        public var reverse: Bool = false

        public init() {}

        /// fldigi's carrier: the centre between mark and space.
        public var centreHz: Double {
            markHz + shiftHz / 2
        }
    }

    /// The latest spectrum (MMTTY's FFT): the magnitude per bin of `binHz`.
    public struct Spectrum: Sendable, Equatable {
        public let binHz: Double
        public let magnitudes: [Float]
    }

    /// What the window shows.
    public struct Snapshot: Sendable {
        public var tuning: Tuning
        /// The demodulator's level (MMTTY's squelch meter, 0 … ~32768).
        public var level: Double
        public var squelchOpen: Bool
        public var transmitting: Bool
        public var spectrum: Spectrum?
    }

    /// The modem cannot do what was asked (an unknown mode name, e.g. fldigi's `CW` for the CW ID).
    public struct Unsupported: Error, CustomStringConvertible {
        public let description: String
    }

    private let lock = NSLock()
    private let modem: RTTYModem
    private var text: [UInt16] = []
    private var dropped: Int = 0
    private var transmitting = false
    /// The transmission ends once the queued text is out (fldigi's `^r`).
    private var returnToRx = false
    private var stopping = false
    private var aborted = false
    private var spectrum: Spectrum?
    private var samplesSinceSpectrum = 0
    private var level: Double = 0
    private var squelchOpen = false
    private var floats: [Float] = []

    public init() {
        // 12 kHz is a supported rate: the initializer cannot fail for it.
        modem = try! RTTYModem(sampleRate: Self.sampleRate)
        modem.eventSink = { [unowned self] event in
            self.handle(event)
        }
    }

    /// The modem's events, delivered synchronously while the lock is held by the call that produced them.
    private func handle(_ event: ModemEvent) {
        switch event {
        case .rxText(let character, _):
            for unit in String(character).utf16 where unit != 0x0D {
                text.append(unit)
            }
            if text.count > Self.maxText {
                let cut: Int = text.count - Self.maxText / 2
                text.removeFirst(cut)
                dropped += cut
            }
        case .signal(let newLevel, let open):
            level = newLevel
            squelchOpen = open
        case .tuning, .shift, .overflow, .txFinished:
            break
        }
    }

    // MARK: - receive

    /// A block of the receiver audio (−1…1 at `sampleRate`). Ignored while transmitting: the own signal is decoded
    /// from the modulator (MMTTY's echo), not from the receiver.
    public func receive(_ samples: [Double]) {
        lock.withLock {
            guard !transmitting, !samples.isEmpty else { return }
            if floats.count != samples.count {
                floats = [Float](repeating: 0, count: samples.count)
            }
            for index in samples.indices {
                floats[index] = Float(samples[index])
            }
            floats.withUnsafeBufferPointer { modem.processRx($0) }
            samplesSinceSpectrum += samples.count
            if samplesSinceSpectrum >= Int(Self.sampleRate / 10) {
                samplesSinceSpectrum = 0
                spectrum = modem.spectrum().map { Spectrum(binHz: $0.binHz, magnitudes: $0.magnitudes) }
            }
        }
    }

    /// The length of all text received so far (fldigi `text.get_rx_length`; never shrinks).
    public var rxLength: Int32 {
        lock.withLock { Int32(clamping: dropped + text.count) }
    }

    /// Received text from `start`, at most `length` units (fldigi `text.get_rx`); text already dropped is skipped.
    public func rxText(start: Int32, length: Int32) -> String {
        lock.withLock {
            let from: Int = min(max(Int(start) - dropped, 0), text.count)
            let to: Int = min(from + max(Int(length), 0), text.count)
            return String(decoding: text[from..<to], as: UTF16.self)
        }
    }

    public var snapshot: Snapshot {
        lock.withLock {
            Snapshot(tuning: readTuning(), level: level, squelchOpen: squelchOpen, transmitting: transmitting,
                     spectrum: spectrum)
        }
    }

    // MARK: - tuning

    public var tuning: Tuning {
        lock.withLock { readTuning() }
    }

    private func readTuning() -> Tuning {
        var tuning = Tuning()
        if case .double(let mark)? = modem.get(parameter: "mark") {
            tuning.markHz = mark
        }
        if case .double(let shift)? = modem.get(parameter: "shift") {
            tuning.shiftHz = shift
        }
        if case .double(let baud)? = modem.get(parameter: "baud") {
            tuning.baud = baud
        }
        if case .bool(let on)? = modem.get(parameter: "afc") {
            tuning.afc = on
        }
        if case .bool(let on)? = modem.get(parameter: "net") {
            tuning.net = on
        }
        if case .bool(let on)? = modem.get(parameter: "reverse") {
            tuning.reverse = on
        }
        return tuning
    }

    /// Applies a whole tuning (a value out of the modem's range is left as it was).
    public func apply(_ tuning: Tuning) {
        lock.withLock {
            try? modem.set(parameter: "baud", value: .double(tuning.baud))
            try? modem.set(parameter: "shift", value: .double(tuning.shiftHz))
            try? modem.set(parameter: "mark", value: .double(Self.clampMark(tuning.markHz, shift: tuning.shiftHz)))
            try? modem.set(parameter: "afc", value: .bool(tuning.afc))
            try? modem.set(parameter: "net", value: .bool(tuning.net))
            try? modem.set(parameter: "reverse", value: .bool(tuning.reverse))
        }
    }

    /// Changes the tuning with `change` (read, modified, applied under one lock).
    public func update(_ change: (inout Tuning) -> Void) {
        var tuning: Tuning = self.tuning
        change(&tuning)
        apply(tuning)
    }

    /// fldigi's carrier (`modem.set_carrier`, a click on the waterfall, Align): the centre between mark and space.
    public func setCentre(_ hz: Double) {
        update { $0.markHz = hz - $0.shiftHz / 2 }
    }

    /// The mark kept inside the modem's 100…3000 Hz with the space too.
    static func clampMark(_ mark: Double, shift: Double) -> Double {
        min(max(mark, 100), 3000 - max(shift, 0))
    }

    /// A raw numeric modem parameter (squelch level, filters: RYRY's parameter ids); `false` = refused.
    @discardableResult
    public func set(_ id: String, number: Double) -> Bool {
        lock.withLock {
            let integer: Bool = modem.parameters.contains { descriptor in
                if case .int = descriptor.kind { descriptor.id == id } else { false }
            }
            let value: ParameterValue = integer ? .int(Int(number.rounded())) : .double(number)
            return (try? modem.set(parameter: id, value: value)) != nil
        }
    }

    /// A raw switch of the modem (`squelch`, `atc`, `bpf`, `lms`…); `false` = refused.
    @discardableResult
    public func set(_ id: String, flag: Bool) -> Bool {
        lock.withLock { (try? modem.set(parameter: id, value: .bool(flag))) != nil }
    }

    /// A raw choice of the modem (`demodType`: `iir`, `fir`, `pll`, `fft`); `false` = refused.
    @discardableResult
    public func set(_ id: String, choice: String) -> Bool {
        lock.withLock { (try? modem.set(parameter: id, value: .string(choice))) != nil }
    }

    /// A numeric parameter's value (`nil` = unknown or not numeric).
    public func number(_ id: String) -> Double? {
        lock.withLock {
            switch modem.get(parameter: id) {
            case .double(let value)?: value
            case .int(let value)?: Double(value)
            default: nil
            }
        }
    }

    public func flag(_ id: String) -> Bool? {
        lock.withLock {
            if case .bool(let value)? = modem.get(parameter: id) { value } else { nil }
        }
    }

    public func choice(_ id: String) -> String? {
        lock.withLock {
            if case .string(let value)? = modem.get(parameter: id) { value } else { nil }
        }
    }

    /// The modem's demodulators (MMTTY: IIR, FIR, PLL, FFT).
    public static let demodulators: [String] = ["iir", "fir", "pll", "fft"]

    /// Every modem parameter for a profile (the TX echo is the program's, not the profile's).
    public func profileValues() -> [String: BuiltinModemProfile.Value] {
        lock.withLock {
            var values: [String: BuiltinModemProfile.Value] = [:]
            for descriptor in modem.parameters where descriptor.id != "echo" {
                switch modem.get(parameter: descriptor.id) {
                case .double(let value)?: values[descriptor.id] = .number(value)
                case .int(let value)?: values[descriptor.id] = .number(Double(value))
                case .bool(let value)?: values[descriptor.id] = .flag(value)
                case .string(let value)?: values[descriptor.id] = .choice(value)
                case nil: break
                }
            }
            return values
        }
    }

    /// Applies a profile's values (unknown or out-of-range values are skipped); the shift before the mark, so the
    /// mark keeps its place.
    public func apply(profile values: [String: BuiltinModemProfile.Value]) {
        lock.withLock {
            let integers: Set<String> = Set(modem.parameters.compactMap { descriptor in
                if case .int = descriptor.kind { descriptor.id } else { nil }
            })
            let order: [String] = ["baud", "shift"] + values.keys.filter { $0 != "baud" && $0 != "shift" && $0 != "mark" }
                .sorted() + ["mark"]
            for id in order where id != "echo" {
                guard let value = values[id] else { continue }
                let converted: ParameterValue
                switch value {
                case .number(let number): converted = integers.contains(id) ? .int(Int(number.rounded())) : .double(number)
                case .flag(let flag): converted = .bool(flag)
                case .choice(let choice): converted = .string(choice)
                }
                try? modem.set(parameter: id, value: converted)
            }
        }
    }

    /// MMTTY's XY scope (mark against space): collection on or off.
    public func setXYScope(_ on: Bool) {
        lock.withLock { modem.setXYScope(on) }
    }

    /// The last full batch of XY points (x = mark, y = space), `nil` = none new.
    public func xyPoints() -> [(x: Float, y: Float)]? {
        lock.withLock { modem.xyScope()?.map { (x: $0.x, y: $0.y) } }
    }

    /// The right button on the spectrum (MMTTY): a notch at `hz`.
    public func notch(_ hz: Double) {
        lock.withLock { modem.notchClick(hz: hz) }
    }

    /// The current mode's name (`RTTY`, `RTTY-50`…; the speed when it is not one of them).
    public var modeName: String {
        let baud: Double = tuning.baud
        if let mode = Self.modes.first(where: { abs($0.baud - baud) < 0.01 }) {
            return mode.name
        }
        return "RTTY-" + String(Int(baud.rounded()))
    }

    /// fldigi `modem.set_by_name`: one of `modes`; anything else (PSK, CW…) is not available in the built-in modem.
    public func setMode(_ name: String) throws {
        guard let mode = Self.modes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw Unsupported(description: name)
        }
        update { $0.baud = mode.baud }
    }

    // MARK: - transmit

    /// Text for the transmit queue (fldigi `text.add_tx`): `^r` ends the transmission once the text before it is out.
    public func addTx(_ text: String) {
        lock.withLock {
            let parts: [String] = text.components(separatedBy: "^r")
            for (index, part) in parts.enumerated() {
                if !part.isEmpty {
                    modem.queueTx(text: part)
                }
                if index < parts.count - 1 {
                    returnToRx = true
                }
            }
        }
    }

    /// fldigi `text.clear_tx`: the text not yet sent is dropped (a running transmission goes on idling).
    public func clearTx() {
        lock.withLock {
            returnToRx = false
            modem.abortTx()
            if transmitting && !aborted {
                modem.beginTx(tune: false)
            }
        }
    }

    /// fldigi `main.tx`: transmit on. `true` = the transmission starts now (the caller opens the output and keys PTT).
    @discardableResult
    public func txOn() -> Bool {
        lock.withLock {
            guard !transmitting else { return false }
            transmitting = true
            stopping = false
            aborted = false
            modem.beginTx(tune: false)
            return true
        }
    }

    /// fldigi `main.abort`: the transmission ends at once and the queue is dropped. `true` = it was transmitting.
    @discardableResult
    public func abort() -> Bool {
        lock.withLock {
            returnToRx = false
            guard transmitting else { return false }
            aborted = true
            modem.abortTx()
            return true
        }
    }

    /// fldigi `main.get_trx_state`: `TX` from transmit on until the transmission has fully ended (`finishTx`).
    public var trxState: String {
        lock.withLock { transmitting ? "TX" : "RX" }
    }

    public var isTransmitting: Bool {
        lock.withLock { transmitting }
    }

    /// The transmit audio (pulled by the output; silence when not transmitting). `level` scales the modulator's
    /// output (0…1). `false` = the transmission is over (the rest of the buffer is silence): the caller releases
    /// PTT and then calls `finishTx`.
    public func generate(into buffer: UnsafeMutableBufferPointer<Float>, level: Float) -> Bool {
        lock.withLock {
            guard transmitting, !aborted else {
                for index in buffer.indices {
                    buffer[index] = 0
                }
                return false
            }
            if returnToRx && !stopping && modem.txPending == 0 {
                stopping = true
                modem.stopTx()
            }
            let status: TxStatus = modem.generateTx(into: buffer)
            if level != 1 {
                for index in buffer.indices {
                    buffer[index] *= level
                }
            }
            return status == .active
        }
    }

    /// The Baudot codes the modulator started since the last call (an FSK keyer sends them).
    public func takeFskCodes() -> [UInt8] {
        lock.withLock { modem.takeFskCodes() }
    }

    /// The transmission has fully ended (output stopped, PTT released): back to receive.
    public func finishTx() {
        lock.withLock {
            transmitting = false
            stopping = false
            aborted = false
            returnToRx = false
        }
    }
}
