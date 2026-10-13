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

    /// fldigi's audio frequency (Hz) while the Digital Interface window polls it, `nil` otherwise — N1MM applies
    /// AutoTRXUpdate only while the window is open.
    public internal(set) var carrierHz: Int?
    /// fldigi's current modem (the Digital Interface's poll).
    public internal(set) var modem: String = ""
    /// fldigi's modems (`modem.get_names`, read once per Digital Interface session) for the Op Mode menu.
    public internal(set) var modemNames: [String] = []

    /// The frequency the digital signal is on: the dial ± the audio frequency in a sideband mode
    /// (`autoTrxUpdate`), the dial otherwise.
    public func transmitHz(dialHz: Int64, rawMode: String?) -> Int64 {
        guard config.config.digital.autoTrxUpdate, let rawMode else { return dialHz }
        return DigitalFrequency.transmitHz(dialHz: dialHz, rawMode: rawMode, carrierHz: carrierHz)
    }

    /// Switches fldigi's modem (N1MM Op Mode, typing RTTY/PSK in the call field); a failure goes to the status line.
    public func setModem(_ name: String) {
        guard ready, !closed else { return }
        let host: String = config.config.digital.fldigiHost
        let port: Int = config.config.digital.fldigiPort
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
            self.modem = name
            self.status.show(DigitalTexts.modemSetKey, .string(name))
        })
    }

    /// Kotlin `digitalReady`: a digital modem is configured.
    public var ready: Bool {
        config.config.digital.engine != .none
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
        keyer.tx.announceTx()
        let appending: Bool = isHolding
        let token: Int64 = keyer.beginDigital(key: key)
        if appending {
            heldToken = token
        }
        let host: String = config.config.digital.fldigiHost
        let port: Int = config.config.digital.fldigiPort
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

    /// Alt+T / the TX button / `{TX}` alone (N1MM): fldigi transmits (idle) until `endHold`; text typed in the
    /// Digital Interface's TX window is appended (`typeHeld`). Goes through the TX gate like every transmission.
    public func startHold() {
        guard let keyer, !closed, !isHolding else { return }
        guard keyer.txAllowed() else {
            keyer.noteSendFailure()
            return
        }
        keyer.tx.announceTx()
        let token: Int64 = keyer.beginDigital(key: -1)
        heldToken = token
        let host: String = config.config.digital.fldigiHost
        let port: Int = config.config.digital.fldigiPort
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

    /// Text typed in the TX window while a transmission is held.
    public func typeHeld(_ text: String) {
        guard isHolding, !text.isEmpty else { return }
        let host: String = config.config.digital.fldigiHost
        let port: Int = config.config.digital.fldigiPort
        let lane: KeyerLane = self.lane
        lane.run { devices in
            try? lane.fldigi(devices, host: host, port: port).addTx(text)
        }
    }

    /// The RX button / Alt+T again / `{RX}` alone: fldigi finishes the text and returns to receive (`^r`).
    public func endHold() {
        guard isHolding, let token = heldToken else { return }
        heldToken = nil
        let host: String = config.config.digital.fldigiHost
        let port: Int = config.config.digital.fldigiPort
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
        let host: String = config.config.digital.fldigiHost
        let port: Int = config.config.digital.fldigiPort
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
        heldToken = nil
        let restore: String? = cwIdRestore
        cwIdRestore = nil
        let host: String = config.config.digital.fldigiHost
        let port: Int = config.config.digital.fldigiPort
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
