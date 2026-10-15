import Foundation
import MCLCore

/// Kotlin `cwDispatcher` (`Dispatchers.IO.limitedParallelism(1)`): one serial thread for the CW keyer
/// **and** fldigi's XML-RPC. The open keyer, its signature and the fldigi client live here and are only touched by
/// jobs on the lane, so `abort` always runs after the `send` asked for before it.
final class KeyerLane: Sendable {

    /// What the lane owns (only touched on the lane's thread).
    final class Devices: @unchecked Sendable {
        /// Kotlin `cwKeyer`.
        var keyer: (any CwKeyer)?
        /// Kotlin `cwKeyerSignature` (`"${method}|${winkeyerPort}"`).
        var signature: String?
        /// The keying options the open keyer was configured with (`nil` = not yet).
        var appliedOptions: CwKeyingOptions?
        /// Kotlin `fldigi`.
        var fldigi: (any FldigiPort)?
        /// Kotlin `fldigiSignature` (`"${host}:${port}"`).
        var fldigiSignature: String?
        /// The open TU/TNC or TinyFSK port.
        var serial: SerialLink?
    }

    /// How the keyer is opened when it is needed (read on the main actor when the job is queued).
    struct OpenRequest: Sendable {
        let method: CwKeyerConfig.Method
        let port: String
        let wpm: Int
        /// The translated `tr("CW klíč je vypnutý (Nastavení → CW klíč)")`.
        let disabledText: String
        /// The translated `tr("Winkeyer: vyber port v Nastavení → CW klíč")`.
        let noPortText: String
        /// Weight, word spacing and the Winkeyer setup.
        var options: CwKeyingOptions = CwKeyingOptions()
        /// Where a followed Winkeyer pot reports its speed.
        var potSpeed: (@Sendable (Int) -> Void)?
    }

    private let lane = SerialLane(name: "cw-keyer")
    private let devices = Devices()
    private let hardware: HardwarePorts
    private let activeCat: ActiveCatBox

    init(hardware: HardwarePorts, activeCat: ActiveCatBox) {
        self.hardware = hardware
        self.activeCat = activeCat
    }

    /// Runs `body` on the lane, then `then` with its result on the main actor.
    func run<T: Sendable>(_ body: @escaping @Sendable (Devices) -> T, then: @escaping @MainActor @Sendable (T) -> Void) {
        let devices: Devices = self.devices
        lane.submit({ body(devices) }, then: then)
    }

    /// Fire and forget.
    func run(_ body: @escaping @Sendable (Devices) -> Void) {
        let devices: Devices = self.devices
        lane.submit {
            body(devices)
        }
    }

    /// Waits until the jobs queued before have run.
    func settle() async {
        await lane.settle()
    }

    /// Kotlin `cwKeyerOrOpen()` (`AS:1471-1490`), on the lane: the open keyer when the signature is unchanged,
    /// otherwise the old one is closed and the configured one opened (CAT over the active rig, Winkeyer on its port).
    func keyerOrOpen(_ devices: Devices, _ request: OpenRequest) throws -> any CwKeyer {
        let signature: String = KeyerSignature.of(method: request.method, port: request.port)
        if let keyer = devices.keyer, signature == devices.signature {
            try configure(keyer, devices, request)
            return keyer
        }
        devices.keyer?.close()
        devices.keyer = nil
        devices.appliedOptions = nil
        let keyer: any CwKeyer
        switch request.method {
        case .cat:
            let box: ActiveCatBox = activeCat
            keyer = CatCwKeyer { box.cat?.rigOrNull() }
        case .winkeyer:
            if KotlinStrings.isBlank(request.port) {
                throw KeyingFailure(message: request.noPortText)
            }
            keyer = try hardware.openWinkeyer(request.port, request.wpm)
        case .none:
            throw KeyingFailure(message: request.disabledText)
        }
        devices.keyer = keyer
        devices.signature = signature
        try configure(keyer, devices, request)
        return keyer
    }

    /// The keying options go to the keyer once, and again after every change.
    private func configure(_ keyer: any CwKeyer, _ devices: Devices, _ request: OpenRequest) throws {
        if devices.appliedOptions == request.options {
            return
        }
        try keyer.configure(request.options, potSpeed: request.potSpeed)
        devices.appliedOptions = request.options
    }

    /// The digital modes' serial device on `path` (reopened after a change of the path).
    func serial(_ devices: Devices, path: String, baud: Int) throws -> SerialLink {
        if let link = devices.serial, link.path == path {
            return link
        }
        devices.serial?.close()
        devices.serial = nil
        let link = SerialLink(path: path, transport: try hardware.openSerial(path, baud))
        devices.serial = link
        return link
    }

    /// Kotlin `fldigiClient()` (`AS:1554-1562`), on the lane: a new client after the address changed.
    func fldigi(_ devices: Devices, host: String, port: Int) throws -> any FldigiPort {
        let signature: String = KeyerSignature.fldigi(host: host, port: port)
        if let client = devices.fldigi, signature == devices.fldigiSignature {
            return client
        }
        let client: any FldigiPort = try hardware.makeFldigi(host, port)
        devices.fldigi = client
        devices.fldigiSignature = signature
        return client
    }
}
