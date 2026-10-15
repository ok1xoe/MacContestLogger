import Foundation
import MCLCore
import Observation

/// fldigi for RTTY/PSK (`AppState` `AS:1538-1618`): the text goes over XML-RPC on the keyer lane (shared with the CW
/// keyer), lights the F-key with the CW keyer's lamp and token, and is watched until fldigi is back on
/// receive (`DigitalTxWatch`: the burst of polls after the first `RX` is dropped).
@Observable @MainActor
public final class DigitalKeyerModel {

    @ObservationIgnored weak var keyer: KeyerModel?
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let lane: KeyerLane
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private var watchTimer: (any RescoreTimer)?
    @ObservationIgnored private var closed: Bool = false

    init(config: ConfigModel, status: StatusModel, lane: KeyerLane, clock: any RescoreClock) {
        self.config = config
        self.status = status
        self.lane = lane
        self.clock = clock
    }

    /// What the Digital Interface of one side (DI1 = VFO A / rig 1, DI2 = VFO B / rig 2) knows about its fldigi.
    public struct Side: Equatable, Sendable {
        /// fldigi's audio frequency (Hz) while the window polls it, `nil` otherwise — N1MM applies AutoTRXUpdate only
        /// while the window is open.
        public var carrierHz: Int?
        /// fldigi's current modem (the poll).
        public var modem: String = ""
        /// fldigi's modems (`modem.get_names`, once per window session) for the Op Mode menu.
        public var modemNames: [String] = []
        /// AFC, Lock and Rev as last read or set; `nil` = not known.
        public var switches: [FldigiClient.Switch: Bool] = [:]
    }

    /// DI1 and DI2.
    public internal(set) var sides: [Side] = [Side(), Side()]
    /// The side the F-keys and the macros act on now (wired by the app: DI2 while the VFO B / rig 2 entry window is
    /// active and a second fldigi is configured).
    @ObservationIgnored var activeSide: @MainActor () -> Int = { 0 }
    /// The side the running transmission went to (Esc, the TX window, the end of a held transmission).
    @ObservationIgnored private var txSide: Int = 0

    var current: Int {
        min(max(activeSide(), 0), 1)
    }

    /// fldigi's endpoint of a side (DI2 falls back to DI1's when no second fldigi is configured).
    func endpoint(_ side: Int) -> (host: String, port: Int) {
        config.config.digital.endpoint(side)
    }

    /// The active side's audio frequency (see `Side`).
    public internal(set) var carrierHz: Int? {
        get { sides[current].carrierHz }
        set { sides[current].carrierHz = newValue }
    }

    public internal(set) var modem: String {
        get { sides[current].modem }
        set { sides[current].modem = newValue }
    }

    public internal(set) var modemNames: [String] {
        get { sides[current].modemNames }
        set { sides[current].modemNames = newValue }
    }

    /// The frequency the digital signal is on: the dial ± the audio frequency in a sideband mode
    /// (`autoTrxUpdate`), the dial otherwise.
    public func transmitHz(dialHz: Int64, rawMode: String?, side: Int? = nil) -> Int64 {
        guard let rawMode else { return dialHz }
        let digital: DigitalConfig = config.config.digital
        let carrier: Int? = sides[min(max(side ?? current, 0), 1)].carrierHz
        var hz: Int64 = digital.autoTrxUpdate
            ? DigitalFrequency.transmitHz(dialHz: dialHz, rawMode: rawMode, carrierHz: carrier) : dialHz
        if dialHz > 0 {
            hz += DigitalFrequency.shiftCompensation(rawMode: rawMode, enabled: digital.shiftCompEnabled,
                                                     offsetHz: digital.shiftCompHz)
        }
        return hz
    }

    /// The active side's AFC, Lock and Rev as last read or set (N1MM's buttons); `nil` = not known.
    public internal(set) var switches: [FldigiClient.Switch: Bool] {
        get { sides[current].switches }
        set { sides[current].switches = newValue }
    }

    /// AFC / Lock / Rev on or off (the buttons, `{ENABLEAFC}`, `{DISABLEAFC}`, `{ENABLENET}`, `{DISABLENET}`, AFC with
    /// CQ, NET with the Run change).
    public func set(_ toggle: FldigiClient.Switch, _ on: Bool, side: Int? = nil) {
        guard ready, !closed else { return }
        let index: Int = min(max(side ?? current, 0), 1)
        sides[index].switches[toggle] = on
        let (host, port): (String, Int) = endpoint(index)
        let lane: KeyerLane = self.lane
        lane.run { devices in
            try? lane.fldigi(devices, host: host, port: port).set(toggle, on)
        }
    }

    /// N1MM NET (MMTTY: the TX frequency follows the RX one): fldigi's Lock off. NET off = Lock on.
    public func setNet(_ on: Bool) {
        set(.lock, !on)
    }

    /// N1MM Align: the rig moves so that the signal under fldigi's cursor lands on the alignment frequency, and the
    /// cursor moves there too. `qsy` retunes the rig (the entry window's rig port); `false` = nothing to align.
    @discardableResult
    public func align(dialHz: Int64, rawMode: String?, qsy: (Int64) -> Void) -> Bool {
        guard ready, let rawMode, let carrier = carrierHz else { return false }
        let target: Int = config.config.digital.alignHz(modem: modem)
        guard let dial = DigitalFrequency.alignedDialHz(dialHz: dialHz, rawMode: rawMode, carrierHz: carrier,
                                                        targetHz: target) else { return false }
        qsy(dial)
        carrierHz = target
        let (host, port): (String, Int) = endpoint(current)
        let lane: KeyerLane = self.lane
        lane.run { devices in
            try? lane.fldigi(devices, host: host, port: port).setCarrier(target)
        }
        return true
    }

    /// Switches fldigi's modem (N1MM Op Mode, typing RTTY/PSK in the call field); a failure goes to the status line.
    public func setModem(_ name: String, side: Int? = nil) {
        guard ready, !closed else { return }
        let index: Int = min(max(side ?? current, 0), 1)
        let (host, port): (String, Int) = endpoint(index)
        let lane: KeyerLane = self.lane
        lane.run({ devices -> String?? in
            do {
                try lane.fldigi(devices, host: host, port: port).setModem(name)
                return .none
            } catch {
                return .some(KeyingErrors.javaMessage(error))
            }
        }, then: { [weak self] failure in
            guard let self else { return }
            if case .some(let message) = failure {
                let text: EntryStatus = KeyerTexts.fldigiFailure(message, host: host, port: port)
                self.status.showJoined(text.parts, separator: "")
                return
            }
            self.sides[index].modem = name
            let key: String = self.config.config.digital.engine == .builtin
                ? DigitalTexts.builtinModemSetKey : DigitalTexts.modemSetKey
            self.status.show(key, .string(name))
        })
    }

    /// The built-in modem's settings for the transmission about to start and the rig its PTT keys (the active one,
    /// as for the voice keyer). Nothing for fldigi, which keys the rig itself.
    func prepareBuiltinTx() {
        guard config.config.digital.engine == .builtin else { return }
        syncBuiltin()
        let setup: BuiltinModemSetup = config.config.builtinModem
        lane.builtin.arm(lane: keyer?.activeRigLane(), viaCat: setup.flag(.pttViaCat))
    }

    /// The built-in modem's options from the configuration (level, outputs, linked tuning).
    func syncBuiltin() {
        let setup: BuiltinModemSetup = config.config.builtinModem
        lane.builtin.configure(BuiltinModemHub.Settings(
            level: setup.outputLevel, devices: [setup.outputDevice(side: 0), setup.outputDevice(side: 1)],
            linked: setup.flag(.linkedTuning)))
    }

    /// Kotlin `digitalReady`: a digital modem is configured.
    public var ready: Bool {
        config.config.digital.engine != .none || hardwareRoute != nil
    }

    /// The token of a transmission held open (N1MM `{TX}` without `{RX}`, Alt+T, the TX window): the lamp stays lit
    /// and fldigi transmits until `endHold`, Esc or the quit.
    @ObservationIgnored private var heldToken: Int64?
    /// The modem to restore after the CW ID (`nil` = no CW ID running).
    @ObservationIgnored private var cwIdRestore: String?
    /// The Digital Interface's RX window clear (`{CLRRX}`); set by the open window.
    @ObservationIgnored var clearRxWindow: (@MainActor () -> Void)?
    /// Raised when the TX window should take the focus (Ctrl+K in a digital mode).
    public internal(set) var txFocusRequest: Int = 0

    /// fldigi transmits a held transmission (the TX window, Alt+T, `{TX}` without `{RX}`).
    public var isHolding: Bool {
        guard let heldToken, let keyer else { return false }
        return keyer.lamp.token == heldToken && keyer.digitalSending
    }

    /// Kotlin `sendDigitalText(text, index)` (`AS:1580-1609`): `" text "` to fldigi; a failure shows
    /// `"fldigi: … (běží fldigi s XML-RPC na host:port?)"`, success is watched every 500 ms (at most 240 polls).
    /// `returnToRx == false` (N1MM `{TX}` without `{RX}`) keeps fldigi transmitting: the transmission is held
    /// until `endHold`, Esc or the quit. Text sent while a transmission is held is appended to it.
    public func send(_ text: String, key: Int = -1, returnToRx: Bool = true) {
        guard let keyer, !closed else { return }
        guard keyer.txAllowed() else {
            keyer.noteSendFailure()
            return
        }
        if let route = hardwareRoute {
            sendHardware(text, key: key, returnToRx: returnToRx, route: route)
            return
        }
        guard so2rLockoutAllows() else {
            keyer.noteSendFailure()
            return
        }
        keyer.tx.announceTx()
        let appending: Bool = isHolding
        let token: Int64 = keyer.beginDigital(key: key)
        if appending {
            heldToken = token
        }
        if !isHolding {
            txSide = current
        }
        prepareBuiltinTx()
        let (host, port): (String, Int) = endpoint(txSide)
        let lane: KeyerLane = self.lane
        lane.run({ devices -> String?? in
            do {
                try lane.fldigi(devices, host: host, port: port).transmit(" " + text + " ", returnToRx: returnToRx,
                                                                           clearFirst: !appending)
                return .none
            } catch {
                return .some(KeyingErrors.javaMessage(error))
            }
        }, then: { [weak self] failure in
            guard let self, let keyer = self.keyer else { return }
            if case .some(let message) = failure {
                self.heldToken = nil
                keyer.failDigital(token)
                keyer.show(KeyerTexts.fldigiFailure(message, host: host, port: port))
                keyer.noteSendFailure()
                return
            }
            if returnToRx {
                self.heldToken = nil
                self.step(DigitalTxWatch(), token: token, host: host, port: port, cwId: true)
            } else {
                self.heldToken = token
            }
        })
    }

    // MARK: - RTTY hardware (TU/TNC, TinyFSK, WinKeyer 3.1)

    /// The entry window's mode (wired by the app): RTTY may go through a hardware keyer.
    @ObservationIgnored var activeMode: @MainActor () -> Mode? = { nil }
    /// The hardware transmission's end (the keyers do not report it: an estimate from the text's length).
    @ObservationIgnored private var hardwareTimer: (any RescoreTimer)?

    /// The RTTY interface for this moment, `nil` = fldigi.
    var hardwareRoute: RttyInterface? {
        let route: RttyInterface = config.config.digital.rttyRoute
        guard route != .fldigi, activeMode() == .rtty else { return nil }
        return route
    }

    /// The bytes or the WinKeyer call of one hardware write, prepared on the main actor.
    private enum HardwareWrite: Sendable {
        case serial(path: String, baud: Int, bytes: [UInt8])
        case winkeyer(text: String, settings: WinkeyerRtty.Settings, request: KeyerLane.OpenRequest)
        case winkeyerRaw([UInt8], request: KeyerLane.OpenRequest)
    }

    /// The write of a hardware route: `text` framed for the device, `start` / `end` adding the keying around it.
    private func hardwareWrite(_ route: RttyInterface, text: String, start: Bool, end: Bool) -> HardwareWrite? {
        guard let keyer else { return nil }
        let digital: DigitalConfig = config.config.digital
        let body: [UInt8] = Array(BaudotText.filter(text).replacingOccurrences(of: "\n", with: "\r\n").utf8)
        switch route {
        case .tinyFsk:
            let bytes: [UInt8] = (start ? [TinyFsk.txOn] : []) + body + (end ? [TinyFsk.txEnd] : [])
            return .serial(path: digital.tinyFskPort, baud: 9_600, bytes: bytes)
        case .tnc:
            let commands = digital.tncCommands
            let bytes: [UInt8] = (start ? TncCommands.bytes(commands.tx) : []) + body
                + (end ? TncCommands.bytes(commands.rx) : [])
            return .serial(path: digital.tncPort, baud: digital.tncBaud, bytes: bytes)
        case .winkeyer:
            if start && end {
                return .winkeyer(text: text, settings: digital.winkeyerRtty, request: keyer.openRequest())
            }
            let bytes: [UInt8] = (start ? WinkeyerRtty.mode(digital.winkeyerRtty) + [0x5B] : []) + body + (end ? [0x5D] : [])
            return .winkeyerRaw(bytes, request: keyer.openRequest())
        case .fldigi:
            return nil
        }
    }

    /// Runs a hardware write on the keyer lane; `nil` = done, else the error text.
    private func perform(_ write: HardwareWrite, then: @escaping @MainActor (String?) -> Void) {
        let lane: KeyerLane = self.lane
        lane.run({ devices -> String? in
            do {
                switch write {
                case .serial(let path, let baud, let bytes):
                    guard !KotlinStrings.isBlank(path) else { return DigitalTexts.noSerialPort }
                    try lane.serial(devices, path: path, baud: baud).write(bytes)
                case .winkeyer(let text, let settings, let request):
                    guard let rtty = try lane.keyerOrOpen(devices, request) as? any RttyKeyer else {
                        return DigitalTexts.noWinkeyerRtty
                    }
                    try rtty.sendRtty(text, settings: settings)
                case .winkeyerRaw(let bytes, let request):
                    guard let rtty = try lane.keyerOrOpen(devices, request) as? any RttyKeyer else {
                        return DigitalTexts.noWinkeyerRtty
                    }
                    try rtty.sendRawRtty(bytes)
                }
                return nil
            } catch {
                return KeyingErrors.javaMessage(error) ?? "?"
            }
        }, then: then)
    }

    /// An RTTY message through the hardware keyer: the lamp is lit while the text is (estimated to be) sent; with
    /// `returnToRx == false` the transmission is held as with fldigi.
    private func sendHardware(_ text: String, key: Int, returnToRx: Bool, route: RttyInterface) {
        guard let keyer else { return }
        let appending: Bool = isHolding
        keyer.tx.announceTx()
        let token: Int64 = keyer.beginDigital(key: key)
        if appending {
            heldToken = token
        }
        guard let write = hardwareWrite(route, text: " " + text + " ", start: !appending, end: returnToRx) else { return }
        perform(write) { [weak self] failure in
            guard let self, let keyer = self.keyer else { return }
            if let failure {
                self.heldToken = nil
                keyer.failDigital(token)
                keyer.show(.verbatim(route.rawValue + ": " + failure))
                keyer.noteSendFailure()
                return
            }
            if returnToRx {
                self.heldToken = nil
                self.finishHardware(token, after: BaudotText.durationMs(text,
                                                                        baud: self.config.config.digital.winkeyerRtty.baud))
            } else {
                self.heldToken = token
            }
        }
    }

    private func finishHardware(_ token: Int64, after milliseconds: Int) {
        hardwareTimer?.cancel()
        hardwareTimer = clock.schedule(afterMilliseconds: milliseconds) { [weak self] in
            self?.keyer?.finishDigital(token)
        }
    }

    /// Alt+T / the TX button / `{TX}` alone (N1MM): fldigi transmits (idle) until `endHold`; text typed in the
    /// Digital Interface's TX window is appended (`typeHeld`). Goes through the TX gate like every transmission.
    public func startHold() {
        guard let keyer, !closed, !isHolding else { return }
        guard keyer.txAllowed() else {
            keyer.noteSendFailure()
            return
        }
        if let route = hardwareRoute {
            keyer.tx.announceTx()
            let token: Int64 = keyer.beginDigital(key: -1)
            heldToken = token
            if let write = hardwareWrite(route, text: "", start: true, end: false) {
                perform(write) { [weak self] failure in
                    guard let self, let failure, let keyer = self.keyer else { return }
                    self.heldToken = nil
                    keyer.failDigital(token)
                    keyer.show(.verbatim(route.rawValue + ": " + failure))
                }
            }
            return
        }
        guard so2rLockoutAllows() else {
            keyer.noteSendFailure()
            return
        }
        keyer.tx.announceTx()
        let token: Int64 = keyer.beginDigital(key: -1)
        heldToken = token
        if !isHolding {
            txSide = current
        }
        prepareBuiltinTx()
        let (host, port): (String, Int) = endpoint(txSide)
        let lane: KeyerLane = self.lane
        lane.run({ devices -> String?? in
            do {
                let client: any FldigiPort = try lane.fldigi(devices, host: host, port: port)
                try client.clearTx()
                try client.txOn()
                return .none
            } catch {
                return .some(KeyingErrors.javaMessage(error))
            }
        }, then: { [weak self] failure in
            guard let self, let keyer = self.keyer, case .some(let message) = failure else { return }
            self.heldToken = nil
            keyer.failDigital(token)
            keyer.show(KeyerTexts.fldigiFailure(message, host: host, port: port))
            keyer.noteSendFailure()
        })
    }

    /// N1MM „TX lockout (digital)": the other Digital Interface transmits. First wins refuses this transmission (a
    /// status text, nothing keyed); last wins stops the other one (fldigi `abort`) and lets this one go. Only
    /// with a second fldigi: one fldigi cannot transmit twice.
    private func so2rLockoutAllows() -> Bool {
        guard let keyer, keyer.digitalSending, txSide != current, config.config.digital.hasSecondFldigi else {
            return true
        }
        let other: Int = txSide
        switch DigitalTxLockout.from(config.config.digital.so2rTxLockout) {
        case .off:
            return true
        case .firstWins:
            keyer.show(.tr("TX LOCKOUT: DI%s vysílá — nevysílám", .int(other + 1)))
            return false
        case .lastWins:
            heldToken = nil
            watchTimer?.cancel()
            let (host, port): (String, Int) = endpoint(other)
            let lane: KeyerLane = self.lane
            lane.run { devices in
                try? lane.fldigi(devices, host: host, port: port).abort()
            }
            keyer.show(.tr("TX LOCKOUT: DI%s zastaveno", .int(other + 1)))
            return true
        }
    }

    /// Text typed in the TX window while a transmission is held.
    public func typeHeld(_ text: String) {
        guard isHolding, !text.isEmpty else { return }
        if let route = hardwareRoute {
            if let write = hardwareWrite(route, text: text, start: false, end: false) {
                perform(write) { _ in }
            }
            return
        }
        let (host, port): (String, Int) = endpoint(txSide)
        let lane: KeyerLane = self.lane
        lane.run { devices in
            try? lane.fldigi(devices, host: host, port: port).addTx(text)
        }
    }

    /// The RX button / Alt+T again / `{RX}` alone: fldigi finishes the text and returns to receive (`^r`).
    public func endHold() {
        guard isHolding, let token = heldToken else { return }
        heldToken = nil
        if let route = hardwareRoute {
            if let write = hardwareWrite(route, text: "", start: false, end: true) {
                perform(write) { [weak self] _ in self?.finishHardware(token, after: 300) }
            }
            return
        }
        let (host, port): (String, Int) = endpoint(txSide)
        let lane: KeyerLane = self.lane
        lane.run({ devices -> Bool in
            (try? lane.fldigi(devices, host: host, port: port).addTx("^r")) != nil
        }, then: { [weak self] _ in
            self?.step(DigitalTxWatch(), token: token, host: host, port: port, cwId: true)
        })
    }

    /// Alt+T, `{ALT-T}`: transmit on or back to receive.
    public func toggleHold() {
        if isHolding {
            endHold()
        } else {
            startHold()
        }
    }

    /// `{CLRTX}`: fldigi's TX buffer cleared.
    public func clearTxBuffer() {
        let (host, port): (String, Int) = endpoint(txSide)
        let lane: KeyerLane = self.lane
        lane.run { devices in
            try? lane.fldigi(devices, host: host, port: port).clearTx()
        }
    }

    /// One step of the TX watch (on the main actor; the poll runs on the lane). At its end the CW ID follows when
    /// it is on (`cwId`), and the modem it borrowed is restored before the lamp goes out.
    private func step(_ watch: DigitalTxWatch, token: Int64, host: String, port: Int, cwId: Bool) {
        guard let keyer, !closed else { return }
        var next: DigitalTxWatch = watch
        switch next.next(tokenCurrent: keyer.lamp.token == token) {
        case .wait(let milliseconds):
            let waited: DigitalTxWatch = next
            watchTimer = clock.schedule(afterMilliseconds: Int(clamping: milliseconds)) { [weak self] in
                self?.step(waited, token: token, host: host, port: port, cwId: cwId)
            }
        case .poll:
            let lane: KeyerLane = self.lane
            let polled: DigitalTxWatch = next
            lane.run({ devices -> String? in
                try? lane.fldigi(devices, host: host, port: port).trxState()
            }, then: { [weak self] state in
                var answered: DigitalTxWatch = polled
                answered.record(state: state)
                self?.step(answered, token: token, host: host, port: port, cwId: cwId)
            })
        case .finish:
            if cwId, let text = cwIdText {
                sendCwId(text, token: token, host: host, port: port)
            } else if let restore = cwIdRestore {
                cwIdRestore = nil
                let lane: KeyerLane = self.lane
                lane.run({ devices in
                    try? lane.fldigi(devices, host: host, port: port).setModem(restore)
                }, then: { [weak self] in
                    self?.keyer?.finishDigital(token)
                })
            } else {
                keyer.finishDigital(token)
            }
        case .abandon:
            break
        }
    }

    /// N1MM CWID: the configured text (`*` / `{MYCALL}` = my call), `nil` when off or blank.
    var cwIdText: String? {
        let digital: DigitalConfig = config.config.digital
        guard digital.cwIdEnabled else { return nil }
        let call: String = KotlinStrings.uppercase(config.config.station.call)
        let text: String = KotlinStrings.trim(digital.cwIdText.replacingOccurrences(of: "{MYCALL}", with: call)
            .replacingOccurrences(of: "*", with: call))
        return text.isEmpty ? nil : KotlinStrings.uppercase(text)
    }

    /// The CW ID after a digital transmission: fldigi's modem switched to CW, the text sent, then (at the end of the
    /// watch) the previous modem restored. The lamp stays lit, so Esc stops it as any transmission.
    private func sendCwId(_ text: String, token: Int64, host: String, port: Int) {
        guard let keyer, keyer.lamp.token == token else { return }
        let lane: KeyerLane = self.lane
        lane.run({ devices -> String? in
            guard let client = try? lane.fldigi(devices, host: host, port: port),
                  let previous = try? client.modemName() else { return nil }
            do {
                try client.setModem("CW")
                try client.transmit(" " + text + " ", returnToRx: true, clearFirst: true)
                return previous
            } catch {
                try? client.setModem(previous)
                return nil
            }
        }, then: { [weak self] previous in
            guard let self else { return }
            guard let previous else {
                self.keyer?.finishDigital(token)
                return
            }
            self.cwIdRestore = previous
            self.step(DigitalTxWatch(), token: token, host: host, port: port, cwId: false)
        })
    }

    /// Kotlin `abortDigital()` (`AS:1611-1618`): only while sending — the lamp goes out and `abort` is queued (a
    /// held transmission ends; a modem borrowed by the CW ID is restored).
    public func abort() -> Bool {
        guard let keyer, keyer.abortDigitalLamp() else { return false }
        watchTimer?.cancel()
        hardwareTimer?.cancel()
        heldToken = nil
        if let route = hardwareRoute {
            // Esc: TinyFSK / WinKeyer `\` (stop and clear), the TNC's abort command.
            let digital: DigitalConfig = config.config.digital
            switch route {
            case .tinyFsk:
                perform(.serial(path: digital.tinyFskPort, baud: 9_600, bytes: [TinyFsk.abort])) { _ in }
            case .tnc:
                perform(.serial(path: digital.tncPort, baud: digital.tncBaud,
                                bytes: TncCommands.bytes(digital.tncCommands.esc))) { _ in }
            case .winkeyer:
                perform(.winkeyerRaw(WinkeyerRtty.abort, request: keyer.openRequest())) { _ in }
            case .fldigi:
                break
            }
            return true
        }
        let restore: String? = cwIdRestore
        cwIdRestore = nil
        let (host, port): (String, Int) = endpoint(txSide)
        let lane: KeyerLane = self.lane
        lane.run { devices in
            guard let client = try? lane.fldigi(devices, host: host, port: port) else { return }
            try? client.abort()
            if let restore {
                try? client.setModem(restore)
            }
        }
        return true
    }

    /// The digital part of the quit: fldigi is aborted only when it sends; the watch stops.
    func shutdown() {
        _ = abort()
        closed = true
        watchTimer?.cancel()
    }
}
