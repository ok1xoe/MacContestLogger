import Foundation
import MCLCore

/// The hamlib rig list of the „Nastavení TCVR" sheet. `list()` blocks (it runs `rigctl -l`); the model calls it on a
/// thread of its own.
public protocol RigListPort: Sendable {
    func list() -> [HamlibRigModel]
}

/// The rig scan of the „Nastavení TCVR" sheet. Tests pass fakes; the scan is never run by scripted runs.
public protocol RigScanPort: Sendable {
    /// `cat.disconnect("scan")` before the scan: the scan opens the rig's serial port itself.
    func disconnectCat(reason: String) async
    /// `RigScanner.scan`: blocks for seconds per candidate; the model calls it on a thread of its own.
    func scan(device: String, candidates: [RigScanner.Candidate],
              listener: any RigScanner.Listener) -> RigScanner.Outcome?
}

/// The serial ports and the sound devices the tabs offer. The calls block (IOKit, CoreAudio); the model calls them
/// on a thread of its own.
public protocol DevicePort: Sendable {
    /// `SerialPorts.available()`.
    func serialPorts() -> [String]
    /// `SoundCard.outputDevices()`.
    func outputDevices() -> [String]
    /// `SoundCard.inputDevices()`.
    func inputDevices() -> [String]
}

/// „Vyzkoušet" of the fldigi modem: `FldigiClient(host, port)`, then `version()` and `modemName()`.
/// Blocks (up to the client's timeouts); the model calls it on a thread of its own. Errors are the client's.
public protocol FldigiProbePort: Sendable {
    func probe(host: String, port: Int) throws -> (version: String, modem: String)
}

/// The outside world of the Settings tab tools, injected through `AppModel.Environment`. The defaults touch
/// nothing (empty lists, a scan that finds nothing, an fldigi that does not answer); the running app passes `live`.
public struct SettingsToolPorts: Sendable {
    public var rigList: any RigListPort
    public var rigScan: any RigScanPort
    public var devices: any DevicePort
    public var fldigi: any FldigiProbePort

    public init(rigList: any RigListPort = NoRigList(), rigScan: any RigScanPort = NoRigScan(),
                devices: any DevicePort = NoDevices(), fldigi: any FldigiProbePort = NoFldigi()) {
        self.rigList = rigList
        self.rigScan = rigScan
        self.devices = devices
        self.fldigi = fldigi
    }

    /// The running app: hamlib, IOKit, CoreAudio and fldigi. The scan's CAT disconnect reaches the app's rig model
    /// once `bootstrap` has linked it (`LiveRigScan.link`).
    public static var live: SettingsToolPorts {
        SettingsToolPorts(rigList: LiveRigList(), rigScan: LiveRigScan(), devices: LiveDevices(), fldigi: LiveFldigi())
    }
}

// MARK: - inert defaults

public struct NoRigList: RigListPort {
    public init() {}
    public func list() -> [HamlibRigModel] { [] }
}

public struct NoRigScan: RigScanPort {
    public init() {}
    public func disconnectCat(reason: String) async {}
    public func scan(device: String, candidates: [RigScanner.Candidate],
                     listener: any RigScanner.Listener) -> RigScanner.Outcome? {
        nil
    }
}

public struct NoDevices: DevicePort {
    public init() {}
    public func serialPorts() -> [String] { [] }
    public func outputDevices() -> [String] { [] }
    public func inputDevices() -> [String] { [] }
}

public struct NoFldigi: FldigiProbePort {
    public init() {}
    public func probe(host: String, port: Int) throws -> (version: String, modem: String) {
        throw JavaIOError(nil, javaClass: "java.net.ConnectException")
    }
}

// MARK: - the running app

struct LiveRigList: RigListPort {
    func list() -> [HamlibRigModel] {
        HamlibRigList.list()
    }
}

struct LiveRigScan: RigScanPort {
    /// The app's rig model (set by `bootstrap`).
    let link = RigLink()

    /// `cat.disconnect("scan")` on the active rig, awaited before the scan opens the rig's serial port (`HW:221`).
    func disconnectCat(reason: String) async {
        guard let rig = await link.model() else { return }
        await rig.disconnectForScan(reason: reason)
    }

    func scan(device: String, candidates: [RigScanner.Candidate],
              listener: any RigScanner.Listener) -> RigScanner.Outcome? {
        RigScanner.scan(device: device, candidates: candidates, listener: listener)
    }
}

struct LiveDevices: DevicePort {
    func serialPorts() -> [String] {
        SerialPorts.available()
    }

    func outputDevices() -> [String] {
        SoundCard.outputDevices()
    }

    func inputDevices() -> [String] {
        SoundCard.inputDevices()
    }
}

struct LiveFldigi: FldigiProbePort {
    func probe(host: String, port: Int) throws -> (version: String, modem: String) {
        let client = try FldigiClient(host: host, port: port)
        let version: String = try client.version()
        let modem: String = try client.modemName()
        return (version, modem)
    }
}

/// Runs blocking work on a thread of its own (Kotlin `Dispatchers.IO` for the scan, the rig list, the devices and
/// fldigi, which must not run on the main thread, in Swift's cooperative pool or on a shared GCD queue).
enum OwnThread {
    static func run<T: Sendable>(_ name: String, _ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            let thread = Thread {
                continuation.resume(returning: body())
            }
            thread.name = name
            thread.start()
        }
    }
}

/// The rig model a port reaches (set once by `bootstrap`; weak, read on the main actor).
final class RigLink: @unchecked Sendable {
    private let lock = NSLock()
    private weak var target: RigModel?

    func attach(_ model: RigModel) {
        lock.withLock { target = model }
    }

    @MainActor func model() -> RigModel? {
        lock.withLock { target }
    }
}
