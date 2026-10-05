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

    /// Kotlin `digitalReady`: a digital modem is configured.
    public var ready: Bool {
        config.config.digital.engine != .none
    }

    /// Kotlin `sendDigitalText(text, index)` (`AS:1580-1609`): `" text "` to fldigi; a failure shows
    /// `"fldigi: … (běží fldigi s XML-RPC na host:port?)"`, success is watched every 500 ms (at most 240 polls).
    public func send(_ text: String, key: Int = -1) {
        guard let keyer, !closed else { return }
        guard keyer.txAllowed() else {
            keyer.noteSendFailure()
            return
        }
        keyer.tx.announceTx()
        let token: Int64 = keyer.beginDigital(key: key)
        let host: String = config.config.digital.fldigiHost
        let port: Int = config.config.digital.fldigiPort
        let lane: KeyerLane = self.lane
        lane.run({ devices -> String?? in
            do {
                try lane.fldigi(devices, host: host, port: port).transmit(" " + text + " ")
                return .none
            } catch {
                return .some(KeyingErrors.javaMessage(error))
            }
        }, then: { [weak self] failure in
            guard let self, let keyer = self.keyer else { return }
            if case .some(let message) = failure {
                keyer.failDigital(token)
                keyer.show(KeyerTexts.fldigiFailure(message, host: host, port: port))
                keyer.noteSendFailure()
                return
            }
            self.step(DigitalTxWatch(), token: token, host: host, port: port)
        })
    }

    /// One step of the TX watch (on the main actor; the poll runs on the lane).
    private func step(_ watch: DigitalTxWatch, token: Int64, host: String, port: Int) {
        guard let keyer, !closed else { return }
        var next: DigitalTxWatch = watch
        switch next.next(tokenCurrent: keyer.lamp.token == token) {
        case .wait(let milliseconds):
            let waited: DigitalTxWatch = next
            watchTimer = clock.schedule(afterMilliseconds: Int(clamping: milliseconds)) { [weak self] in
                self?.step(waited, token: token, host: host, port: port)
            }
        case .poll:
            let lane: KeyerLane = self.lane
            let polled: DigitalTxWatch = next
            lane.run({ devices -> String? in
                try? lane.fldigi(devices, host: host, port: port).trxState()
            }, then: { [weak self] state in
                var answered: DigitalTxWatch = polled
                answered.record(state: state)
                self?.step(answered, token: token, host: host, port: port)
            })
        case .finish:
            keyer.finishDigital(token)
        case .abandon:
            break
        }
    }

    /// Kotlin `abortDigital()` (`AS:1611-1618`): only while sending — the lamp goes out and `abort` is queued.
    public func abort() -> Bool {
        guard let keyer, keyer.abortDigitalLamp() else { return false }
        watchTimer?.cancel()
        let host: String = config.config.digital.fldigiHost
        let port: Int = config.config.digital.fldigiPort
        let lane: KeyerLane = self.lane
        lane.run { devices in
            try? lane.fldigi(devices, host: host, port: port).abort()
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
