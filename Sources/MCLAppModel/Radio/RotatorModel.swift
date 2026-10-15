import Foundation
import MCLCore
import Observation

/// The rotator of v1.1.1 (`AS:667-763`): the hamlib `rotctld` position read every 2 s, turning and
/// stopping over rotctld and the N1MM rotor UDP message. Every socket call runs on the rotator lane; the client lives
/// only there and is dropped after an error (Kotlin `dropRotator`). Without `rotatorHost` nothing is opened.
@Observable @MainActor
public final class RotatorModel {

    /// Kotlin `rotatorAzimuth`: the last azimuth read of the selected rotor, with its calibration (`nil` = not
    /// connected).
    public private(set) var azimuth: Double?
    /// Kotlin `rotatorStatus` (`nil` = the default `tr("Rotátor nenastaven")`, translated when shown).
    public private(set) var pollStatus: EntryStatus?
    /// The rotor the Rotator window shows and turns (`""` = the default rotator of the Antennas tab).
    public private(set) var selectedRotor: String = ""
    /// The rotors broadcast on the network (N1MM Rotor, UDP 13010) by name, with their last heading.
    public private(set) var networkRotors: [String: Double] = [:]
    /// Why the network rotor display is not receiving (`nil` = off or receiving).
    public private(set) var networkStatus: EntryStatus?

    /// `rotatorStatus` as a status text.
    public var statusText: EntryStatus {
        pollStatus ?? RotorAzimuth.notConfigured
    }

    /// The poll period (Kotlin `delay(2_000)`).
    static let pollMs = 2_000

    /// The clients by rotor (`""` = the default rotator, otherwise the rotor's name), touched only on the lane
    /// (Kotlin `rotator` under `rotatorLock`).
    private final class Clients: @unchecked Sendable {
        var byKey: [String: RotctldClient] = [:]
        var network: RotorNetworkListener?
    }

    /// One rotor to turn: its setup, the client key and the antenna's offset / bidirectional flag when the current
    /// antenna is on this rotor.
    struct Target: Equatable {
        let key: String
        let entry: RotorEntry
        let isDefault: Bool
        let offset: Int
        let bidirectional: Bool
    }

    @ObservationIgnored private let box = Clients()
    @ObservationIgnored let lane = SerialLane(name: "rotator")
    @ObservationIgnored private let hardware: HardwarePorts
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private var timer: (any RescoreTimer)?
    @ObservationIgnored private var running = false
    /// The controller's own reading of the selected rotor (before the calibration).
    @ObservationIgnored private var rawAzimuth: Double?
    /// The band of the tuned frequency (the UDP message's `freqband`), read when a turn is asked.
    @ObservationIgnored var currentBand: @MainActor () -> Band? = { nil }
    /// `azimuthTo(call)` and the last QSO's call (`turnRotorToCall`).
    @ObservationIgnored var azimuthTo: @MainActor (String) -> Int? = { _ in nil }
    @ObservationIgnored var lastQsoCall: @MainActor () -> String? = { nil }
    /// The antenna in use (its rotors, offset and bidirectional flag; `nil` = none chosen).
    @ObservationIgnored var currentAntenna: @MainActor () -> AntennaEntry? = { nil }

    init(hardware: HardwarePorts, config: ConfigModel, status: StatusModel, language: LanguageModel,
         clock: any RescoreClock) {
        self.hardware = hardware
        self.config = config
        self.status = status
        self.language = language
        self.clock = clock
    }

    // MARK: - rotors

    /// The rotors to pick in the Rotator window: the default rotator (`""`) and the named rotors of the setup.
    public var rotorChoices: [String] {
        [""] + config.config.rotor.rotors.map(\.name)
    }

    /// The F1–F10 preset bearings of the setup.
    public var presets: [Int?] {
        config.config.rotor.presets
    }

    /// Picks the rotor the window shows and turns; its position is read at once.
    public func selectRotor(_ name: String) {
        let known: String = rotorChoices.first { Self.same($0, name) } ?? ""
        guard known != selectedRotor else { return }
        selectedRotor = known
        azimuth = nil
        rawAzimuth = nil
        pollStatus = nil
        if running {
            timer?.cancel()
            timer = nil
            poll()
        }
    }

    /// The setup of a rotor by name (`""` = the default rotator); a name the setup does not know is a rotor of the
    /// rotor program, reached only by the UDP message.
    func target(_ name: String, antenna: AntennaEntry?) -> Target {
        let app: AppConfig = config.config
        let applies: Bool
        if let antenna {
            let names: [String] = antenna.rotorNames
            applies = names.isEmpty ? name.isEmpty : names.contains { Self.same($0, name) }
        } else {
            applies = false
        }
        let offset: Int = applies ? antenna?.offset ?? 0 : 0
        let bidirectional: Bool = applies ? antenna?.bidirectional ?? false : false
        if name.isEmpty {
            return Target(key: "", entry: .defaultRotor(host: app.rotatorHost, port: app.rotatorPort,
                                                         udpName: app.rotorUdpName),
                          isDefault: true, offset: offset, bidirectional: bidirectional)
        }
        let entry: RotorEntry = app.rotor.rotors.first { Self.same($0.name, name) } ?? RotorEntry(name: name)
        return Target(key: entry.name, entry: entry, isDefault: false, offset: offset, bidirectional: bidirectional)
    }

    /// The rotors a beam bearing turns: the current antenna's rotors (several = a stack), otherwise the selected one.
    func beamTargets() -> [Target] {
        let antenna: AntennaEntry? = currentAntenna()
        let names: [String] = antenna?.rotorNames ?? []
        if names.isEmpty {
            return [target(selectedRotor, antenna: antenna)]
        }
        return names.map { target($0, antenna: antenna) }
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        KotlinStrings.uppercase(a) == KotlinStrings.uppercase(b)
    }

    // MARK: - the 2 s poll

    /// Starts the poll (Kotlin `init { startRotatorPoll() }`): the first read at once, then every 2 s after the
    /// previous result; the network rotor display when it is switched on.
    func start() {
        guard !running else { return }
        running = true
        poll()
        applyNetworkSetting()
    }

    private func poll() {
        guard running else { return }
        let rotor: Target = target(selectedRotor, antenna: nil)
        let host: String = rotor.entry.host
        let port: Int = rotor.entry.port
        let key: String = rotor.key
        // Without a host there is nothing to read (Kotlin `rotatorClient()` = null): no lane, no thread every 2 s.
        guard !KotlinStrings.isBlank(host) else {
            polled(nil, rotor: rotor)
            return
        }
        let box: Clients = self.box
        let hardware: HardwarePorts = self.hardware
        lane.submit({ () -> Double? in
            guard let client = Self.client(box, hardware, key: key, host: host, port: port) else { return nil }
            do {
                return try client.azimuth()
            } catch {
                Self.drop(box, key: key)
                return nil
            }
        }, then: { [weak self] azimuth in
            self?.polled(azimuth, rotor: rotor)
        })
    }

    private func polled(_ raw: Double?, rotor: Target) {
        guard running else { return }
        if rotor.key == target(selectedRotor, antenna: nil).key {
            rawAzimuth = raw
            azimuth = raw.map { RotorPlan.reported(raw: $0, calibration: rotor.entry.calibration) }
            pollStatus = RotorAzimuth.pollStatus(host: rotor.entry.host, port: rotor.entry.port, azimuth: raw)
        }
        timer = clock.schedule(afterMilliseconds: Self.pollMs) { [weak self] in
            self?.poll()
        }
    }

    // MARK: - turning

    /// Kotlin `turnRotorTo(azimuth)`: the beam to a bearing — the current antenna's rotors with its offset and
    /// bidirectional flag (none set: the selected rotor). Per rotor the UDP message first (when a UDP host is set),
    /// then rotctld — or only the UDP status when the rotor has no rotctld but UDP is set.
    public func turnTo(_ azimuth: Double) {
        for rotor in beamTargets() {
            turn(rotor, bearing: azimuth)
        }
    }

    /// The Rotator window's turn (the field, the presets): the selected rotor, with the current antenna's offset
    /// when that antenna is on it.
    public func turnSelected(to azimuth: Double) {
        turn(target(selectedRotor, antenna: currentAntenna()), bearing: azimuth)
    }

    /// N1MM Rotor F1–F10: the selected rotor to the preset bearing (an unset button does nothing).
    public func turnToPreset(_ index: Int) {
        let presets: [Int?] = self.presets
        guard index >= 0, index < presets.count, let bearing = presets[index] else { return }
        turnSelected(to: Double(bearing))
    }

    /// Kotlin `turnRotorToCall(call, longPath)` (Alt+J / Ctrl+Alt+J). N1MM: a heading typed in the call field
    /// (0–360) turns to that heading.
    public func turnToCall(_ call: String, longPath: Bool) {
        if let heading = RotorPlan.typedHeading(call) {
            turnTo(RotorAzimuth.heading(heading, longPath: longPath))
            return
        }
        let target: String = RotorAzimuth.target(call: call, lastQsoCall: lastQsoCall())
        guard let azimuth = azimuthTo(target) else {
            show(RotorAzimuth.unknownAzimuth(target))
            return
        }
        turnTo(RotorAzimuth.heading(azimuth, longPath: longPath))
    }

    /// „Natočit rotátor" on a spot (band map, Available): by the bearing to the spot's grid when it is known (from my
    /// grid), else by the call.
    public func turnToStation(_ call: String, grid: String?) {
        if let azimuth = RotorPlan.gridBearing(from: config.config.station.gridSquare, to: grid) {
            turnTo(Double(azimuth))
        } else {
            turnToCall(call, longPath: false)
        }
    }

    /// One rotor to a beam bearing.
    private func turn(_ rotor: Target, bearing: Double) {
        let app: AppConfig = config.config
        let udpName: String = rotor.isDefault ? app.rotorUdpName : rotor.entry.name
        sendUdp(N1mmRotorUdp.turnMessage(rotor: udpName, azimuth: bearing,
                                         bandMhz: Int32(truncatingIfNeeded: RotorAzimuth.udpBandMhz(currentBand())),
                                         offset: rotor.offset, bidirectional: rotor.bidirectional))
        if KotlinStrings.isBlank(rotor.entry.host) && !KotlinStrings.isBlank(app.rotorUdpHost) {
            show(RotorAzimuth.udpTurned(bearing))
            return
        }
        let noClient: String = language.tr(RotorAzimuth.noClient)
        if KotlinStrings.isBlank(rotor.entry.host) && !rotor.isDefault {
            show(RotorAzimuth.failure(noClient))
            return
        }
        let heading: Double = RotorPlan.rotorHeading(bearing: bearing, offset: rotor.offset,
                                                     bidirectional: rotor.bidirectional, current: heading(of: rotor))
        let currentRaw: Double? = rotor.key == target(selectedRotor, antenna: nil).key ? rawAzimuth : nil
        let command = RotorPlan.command(heading: heading, rotor: rotor.entry, currentRaw: currentRaw)
        let limited: Bool = rotor.entry.hasLimits
        let host: String = rotor.entry.host
        let port: Int = rotor.entry.port
        let key: String = rotor.key
        let box: Clients = self.box
        let hardware: HardwarePorts = self.hardware
        lane.submit({ () -> String?? in
            guard let client = Self.client(box, hardware, key: key, host: host, port: port) else {
                Self.drop(box, key: key)
                return .some(noClient)
            }
            do {
                if limited {
                    try client.turnToRaw(command.azimuth)
                } else {
                    try client.turnTo(command.azimuth)
                }
                return .none
            } catch {
                Self.drop(box, key: key)
                return .some(PeripheralsModel.message(error))
            }
        }, then: { [weak self] failure in
            guard let self else { return }
            switch failure {
            case .none:
                self.show(command.clamped
                          ? RotorAzimuth.clamped(rotor: rotor.entry.name, limit: command.azimuth)
                          : RotorAzimuth.turned(bearing))
            case .some(let message):
                self.show(RotorAzimuth.failure(message))
            }
        })
    }

    /// The rotor's last known heading: the selected rotor's reading, otherwise its network broadcast.
    private func heading(of rotor: Target) -> Double? {
        if rotor.key == target(selectedRotor, antenna: nil).key, let azimuth {
            return azimuth
        }
        return networkRotors.first { Self.same($0.key, rotor.entry.name) }?.value
    }

    /// Kotlin `stopRotor()`: every rotor a turn may move (the current antenna's and the selected one) — the UDP stop,
    /// then rotctld `S` (no client = nothing to stop, still „zastaven"); a failure does not drop the client (Kotlin).
    public func stop() {
        var rotors: [Target] = beamTargets()
        let selected: Target = target(selectedRotor, antenna: nil)
        if !rotors.contains(where: { $0.key == selected.key }) {
            rotors.append(selected)
        }
        for rotor in rotors {
            stop(rotor)
        }
    }

    private func stop(_ rotor: Target) {
        let app: AppConfig = config.config
        sendUdp(N1mmRotorUdp.stopMessage(rotor: rotor.isDefault ? app.rotorUdpName : rotor.entry.name))
        if KotlinStrings.isBlank(rotor.entry.host) && !KotlinStrings.isBlank(app.rotorUdpHost) {
            show(RotorAzimuth.udpStopped)
            return
        }
        if KotlinStrings.isBlank(rotor.entry.host) && !rotor.isDefault {
            return
        }
        let host: String = rotor.entry.host
        let port: Int = rotor.entry.port
        let key: String = rotor.key
        let box: Clients = self.box
        let hardware: HardwarePorts = self.hardware
        lane.submit({ () -> String?? in
            do {
                try Self.client(box, hardware, key: key, host: host, port: port)?.stop()
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

    // MARK: - setup and the network rotors

    /// Saves the rotor setup (the Rotator window's Setup) and applies the network rotor display.
    public func saveSetup(_ setup: RotorSetup) {
        guard setup != config.config.rotor else { return }
        config.config.rotor = setup
        config.save(failureKey: "Uložení nastavení rotátoru selhalo (%s)")
        if !rotorChoices.contains(where: { Self.same($0, selectedRotor) }) {
            selectRotor("")
        }
        applyNetworkSetting()
    }

    /// Starts or stops the receiver of the network rotors to match the setup (only while running).
    func applyNetworkSetting() {
        guard running else { return }
        let setup: RotorSetup = config.config.rotor
        let wanted: Int? = setup.networkEnabled ? setup.networkPort : nil
        let box: Clients = self.box
        let hardware: HardwarePorts = self.hardware
        if wanted == nil {
            networkRotors = [:]
            networkStatus = nil
        }
        lane.submit({ () -> String?? in
            let current: RotorNetworkListener? = box.network
            if let wanted, let current, current.boundPort == wanted {
                return .none
            }
            current?.close()
            box.network = nil
            guard let wanted else { return .none }
            do {
                let listener: RotorNetworkListener = try hardware.listenRotorNetwork(wanted) { [weak self] name, heading in
                    Task { @MainActor in
                        self?.networkHeard(name, heading)
                    }
                }
                listener.start()
                box.network = listener
                return .none
            } catch {
                return .some(PeripheralsModel.message(error))
            }
        }, then: { [weak self] failure in
            guard let self else { return }
            if case .some(let message) = failure {
                self.networkStatus = RotorAzimuth.networkFailure(message)
            } else {
                self.networkStatus = nil
            }
        })
    }

    func networkHeard(_ name: String, _ heading: Double) {
        guard running, config.config.rotor.networkEnabled else { return }
        networkRotors[name] = heading
    }

    // MARK: - lifecycle

    /// Waits for the work queued on the lane (tests).
    func settle() async {
        await lane.settle()
    }

    /// Quit: the poll stops, the clients and the network receiver close (Kotlin leaves both running).
    func shutdown() async {
        running = false
        timer?.cancel()
        timer = nil
        let box: Clients = self.box
        lane.submit {
            for key in Array(box.byKey.keys) {
                Self.drop(box, key: key)
            }
            box.network?.close()
            box.network = nil
        }
        await lane.settle()
    }

    // MARK: - the clients (on the lane)

    /// Kotlin `rotatorClient()`: `nil` without a host; otherwise the cached client or a new one (a failed connect
    /// gives `nil`). The cached client is kept even when the configured host changed (Kotlin).
    nonisolated private static func client(_ box: Clients, _ hardware: HardwarePorts, key: String, host: String,
                                           port: Int) -> RotctldClient? {
        if KotlinStrings.isBlank(host) {
            return nil
        }
        if let client = box.byKey[key] {
            return client
        }
        box.byKey[key] = try? hardware.makeRotctld(host, port)
        return box.byKey[key]
    }

    /// Kotlin `dropRotator()`.
    nonisolated private static func drop(_ box: Clients, key: String) {
        box.byKey[key]?.close()
        box.byKey[key] = nil
    }

    private func show(_ message: EntryStatus) {
        status.showJoined(message.parts, separator: "")
    }
}
