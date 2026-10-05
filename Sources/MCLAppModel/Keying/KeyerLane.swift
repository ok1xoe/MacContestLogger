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
        /// Kotlin `fldigi`.
        var fldigi: (any FldigiPort)?
        /// Kotlin `fldigiSignature` (`"${host}:${port}"`).
        var fldigiSignature: String?
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
            return keyer
        }
        devices.keyer?.close()
        devices.keyer = nil
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
        return keyer
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
