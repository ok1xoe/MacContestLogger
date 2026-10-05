import Foundation
import MCLCore
import Observation

/// The rotator of v1.1.1 (`AS:667-763`): the hamlib `rotctld` position read every 2 s, turning and
/// stopping over rotctld and the N1MM rotor UDP message. Every socket call runs on the rotator lane; the client lives
/// only there and is dropped after an error (Kotlin `dropRotator`). Without `rotatorHost` nothing is opened.
@Observable @MainActor
public final class RotatorModel {

    /// Kotlin `rotatorAzimuth`: the last azimuth read (`nil` = not connected).
    public private(set) var azimuth: Double?
    /// Kotlin `rotatorStatus` (`nil` = the default `tr("Rotátor nenastaven")`, translated when shown).
    public private(set) var pollStatus: EntryStatus?

    /// `rotatorStatus` as a status text.
    public var statusText: EntryStatus {
        pollStatus ?? RotorAzimuth.notConfigured
    }

    /// The poll period (Kotlin `delay(2_000)`).
    static let pollMs = 2_000

    /// The client, touched only on the lane (Kotlin `rotator` under `rotatorLock`).
    private final class Client: @unchecked Sendable {
        var client: RotctldClient?
    }

    @ObservationIgnored private let box = Client()
    @ObservationIgnored let lane = SerialLane(name: "rotator")
    @ObservationIgnored private let hardware: HardwarePorts
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private var timer: (any RescoreTimer)?
    @ObservationIgnored private var running = false
    /// The band of the tuned frequency (the UDP message's `freqband`), read when a turn is asked.
    @ObservationIgnored var currentBand: @MainActor () -> Band? = { nil }
    /// `azimuthTo(call)` and the last QSO's call (`turnRotorToCall`).
    @ObservationIgnored var azimuthTo: @MainActor (String) -> Int? = { _ in nil }
    @ObservationIgnored var lastQsoCall: @MainActor () -> String? = { nil }

    init(hardware: HardwarePorts, config: ConfigModel, status: StatusModel, language: LanguageModel,
         clock: any RescoreClock) {
        self.hardware = hardware
        self.config = config
        self.status = status
        self.language = language
        self.clock = clock
    }

    // MARK: - the 2 s poll

    /// Starts the poll (Kotlin `init { startRotatorPoll() }`): the first read at once, then every 2 s after the
    /// previous result.
    func start() {
        guard !running else { return }
        running = true
        poll()
    }

    private func poll() {
        guard running else { return }
        let host: String = config.config.rotatorHost
        let port: Int = config.config.rotatorPort
        // Without a host there is nothing to read (Kotlin `rotatorClient()` = null): no lane, no thread every 2 s.
        guard !KotlinStrings.isBlank(host) else {
            polled(nil)
            return
        }
        let box: Client = self.box
        let hardware: HardwarePorts = self.hardware
        lane.submit({ () -> Double? in
            guard let client = Self.client(box, hardware, host: host, port: port) else { return nil }
            do {
                return try client.azimuth()
            } catch {
                Self.drop(box)
                return nil
            }
        }, then: { [weak self] azimuth in
            self?.polled(azimuth)
        })
    }

    private func polled(_ azimuth: Double?) {
        guard running else { return }
        self.azimuth = azimuth
        pollStatus = RotorAzimuth.pollStatus(host: config.config.rotatorHost, port: config.config.rotatorPort,
                                             azimuth: azimuth)
        timer = clock.schedule(afterMilliseconds: Self.pollMs) { [weak self] in
            self?.poll()
        }
    }

    // MARK: - turning

    /// Kotlin `turnRotorTo(azimuth)`: the UDP message first (when a UDP host is set), then rotctld — or only the
    /// UDP status when rotctld is not configured but UDP is.
    public func turnTo(_ azimuth: Double) {
        let app: AppConfig = config.config
        sendUdp(N1mmRotorUdp.turnMessage(rotor: app.rotorUdpName, azimuth: azimuth,
                                         bandMhz: Int32(truncatingIfNeeded: RotorAzimuth.udpBandMhz(currentBand()))))
        if KotlinStrings.isBlank(app.rotatorHost) && !KotlinStrings.isBlank(app.rotorUdpHost) {
            show(RotorAzimuth.udpTurned(azimuth))
            return
        }
        let host: String = app.rotatorHost
        let port: Int = app.rotatorPort
        let box: Client = self.box
        let hardware: HardwarePorts = self.hardware
        let noClient: String = language.tr(RotorAzimuth.noClient)
        lane.submit({ () -> String?? in
            guard let client = Self.client(box, hardware, host: host, port: port) else {
                Self.drop(box)
                return .some(noClient)
            }
            do {
                try client.turnTo(azimuth)
                return .none
            } catch {
                Self.drop(box)
                return .some(PeripheralsModel.message(error))
            }
        }, then: { [weak self] failure in
            guard let self else { return }
            switch failure {
            case .none:
                self.show(RotorAzimuth.turned(azimuth))
            case .some(let message):
                self.show(RotorAzimuth.failure(message))
            }
        })
    }

    /// Kotlin `turnRotorToCall(call, longPath)` (Alt+J / Ctrl+Alt+J).
    public func turnToCall(_ call: String, longPath: Bool) {
        let target: String = RotorAzimuth.target(call: call, lastQsoCall: lastQsoCall())
        guard let azimuth = azimuthTo(target) else {
            show(RotorAzimuth.unknownAzimuth(target))
            return
        }
        turnTo(RotorAzimuth.heading(azimuth, longPath: longPath))
    }

    /// Kotlin `stopRotor()`: the UDP stop, then rotctld `S` (no client = nothing to stop, still „zastaven"); a
    /// failure does not drop the client (Kotlin).
    public func stop() {
        let app: AppConfig = config.config
        sendUdp(N1mmRotorUdp.stopMessage(rotor: app.rotorUdpName))
        if KotlinStrings.isBlank(app.rotatorHost) && !KotlinStrings.isBlank(app.rotorUdpHost) {
            show(RotorAzimuth.udpStopped)
            return
        }
        let host: String = app.rotatorHost
        let port: Int = app.rotatorPort
        let box: Client = self.box
        let hardware: HardwarePorts = self.hardware
        lane.submit({ () -> String?? in
            do {
                try Self.client(box, hardware, host: host, port: port)?.stop()
                return .none
            } catch {
                return .some(PeripheralsModel.message(error))
            }
        }, then: { [weak self] failure in
            guard let self else { return }
            switch failure {
            case .none:
                self.show(RotorAzimuth.stopped)
            case .some(let message):
                self.show(RotorAzimuth.failure(message))
            }
        })
    }

    /// Kotlin `sendRotorUdp(message)`: only with a UDP host; a failure shows `tr("Rotátor UDP: %s")`.
    private func sendUdp(_ message: String) {
        let host: String = config.config.rotorUdpHost
        guard !KotlinStrings.isBlank(host) else { return }
        let port: Int = config.config.rotorUdpPort
        let hardware: HardwarePorts = self.hardware
        lane.submit({ () -> String?? in
            do {
                try hardware.rotorUdp(host, port, message)
                return .none
            } catch {
                return .some(PeripheralsModel.message(error))
            }
        }, then: { [weak self] failure in
            if case .some(let message) = failure {
                self?.show(RotorAzimuth.udpFailure(message))
            }
        })
    }

    // MARK: - lifecycle

    /// Waits for the work queued on the lane (tests).
    func settle() async {
        await lane.settle()
    }

    /// Quit: the poll stops and the client closes (Kotlin leaves both running).
    func shutdown() async {
        running = false
        timer?.cancel()
        timer = nil
        let box: Client = self.box
        lane.submit {
            Self.drop(box)
        }
        await lane.settle()
    }

    // MARK: - the client (on the lane)

    /// Kotlin `rotatorClient()`: `nil` without a host; otherwise the cached client or a new one (a failed connect
    /// gives `nil`). The cached client is kept even when the configured host changed (Kotlin).
    nonisolated private static func client(_ box: Client, _ hardware: HardwarePorts, host: String,
                                           port: Int) -> RotctldClient? {
        if KotlinStrings.isBlank(host) {
            return nil
        }
        if let client = box.client {
            return client
        }
        box.client = try? hardware.makeRotctld(host, port)
        return box.client
    }

    /// Kotlin `dropRotator()`.
    nonisolated private static func drop(_ box: Client) {
        box.client?.close()
        box.client = nil
    }

    private func show(_ message: EntryStatus) {
        status.showJoined(message.parts, separator: "")
    }
}
