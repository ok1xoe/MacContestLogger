import Foundation
import MCLCore

/// One rig's CAT connection as the rig model drives it (`CatSession`; the inert port touches nothing). Every call
/// may block (`disconnect` up to ~2 s, `tune`/`setPtt`/`setMode` on rig I/O): the rig model calls them only on the
/// rig's `RigLane`, never on the main thread or in Swift's cooperative pool.
public protocol CatPort: AnyObject, Sendable {
    var snapshot: CatSession.Snapshot { get }
    func toggle(_ rc: RigConfig)
    func connect(_ rc: RigConfig)
    func disconnect(_ message: String?)
    /// A connect is still running.
    var isConnecting: Bool { get }
    /// `disconnect` that cancels a connect in flight and blocks until it has finished (its daemon and rig closed).
    func disconnectCancellingConnect(_ message: String?)
    func tune(_ freqHz: Int64) throws
    func setPtt(_ on: Bool) throws
    func setMode(_ mode: Mode?, freqHz: Int64) throws
    func rigOrNull() -> (any RigController)?
    /// A hook run with every freshly connected rig before anything else is sent to it (on the connect thread).
    func setOnConnected(_ hook: @escaping @Sendable (any RigController) -> Void)
}

extension CatPort {
    public func setOnConnected(_ hook: @escaping @Sendable (any RigController) -> Void) {}
}

extension CatSession: CatPort {}

/// What a CAT session is built with (`CatSession` initialiser arguments). The callbacks run on the session's
/// threads; the rig model hops to the main actor itself.
public struct CatHooks: Sendable {
    /// 0 = rig 1 (`cat1`), 1 = rig 2 (`cat2`).
    public let index: Int
    /// Rig 1: the live transverter table; rig 2: none (Kotlin `CatConnection(scope)`).
    public let transverters: @Sendable () -> [TransverterEntry]
    /// The shared live mode mapping.
    public let modes: HamlibModeProvider
    public let log: CatTrafficLog
    public let translate: @Sendable (String) -> String
    public let onChange: @Sendable (CatSession.Snapshot) -> Void
    public let onUnexpectedError: @Sendable (any Error) -> Void
}

/// The error of every inert hardware port: nothing is opened (`MCL_INERT_HARDWARE`, the default environment).
public struct InertHardwareError: Error, CustomStringConvertible, Sendable {
    public static let message = "Hardware disabled (MCL_INERT_HARDWARE)"

    public init() {}

    public var description: String { Self.message }
}

/// The hardware the radio and keying models open (CAT, OTRSP, the footswitch, the rotator, the CW keyer, the
/// voice keyer's audio and message recording, speech synthesis, fldigi, the receiver audio and the recording playback).
/// `inert` is the default of `AppModel.Environment`: no port opens anything, no daemon starts, no socket connects.
/// Only `Environment.production()` passes `live`, and not even it when `MCL_INERT_HARDWARE=1`. Tests
/// pass fakes (a fake `rigctld` on a loopback port, `Otrsp(sink:)`, a scripted footswitch).
public struct HardwarePorts: Sendable {
    /// A rig's CAT session.
    public var makeCat: @Sendable (CatHooks) -> any CatPort
    /// `Otrsp.open(portPath)` (blocks; called on the peripherals lane).
    public var openOtrsp: @Sendable (String) throws -> Otrsp
    /// `Footswitch.open(portPath, pin, onChange)` (blocks; called on the peripherals lane).
    public var openFootswitch: @Sendable (String, Footswitch.Pin, @escaping @Sendable (Bool) -> Void) throws
        -> Footswitch
    /// `RotctldClient(host, port)` (blocks; called on the rotator lane).
    public var makeRotctld: @Sendable (String, Int) throws -> RotctldClient
    /// `N1mmRotorUdp.send(host, port, message)` (blocks; called on the rotator lane).
    public var rotorUdp: @Sendable (String, Int, String) throws -> Void
    /// `SoundCard.playPcm` — the recording playback of a QSO (blocks; called on its own thread).
    public var playPcm: @Sendable ([UInt8], WavFile.PcmFormat, String?, () -> Bool) throws(AudioIOError) -> Void
    /// `true` for the inert ports (tests and `MCL_INERT_HARDWARE` check it).
    public var isInert: Bool

    // The keying ports. Not initialiser arguments: they start inert, only `live` replaces them.

    /// `WinkeyerKeyer.open(port, wpm)` (blocks; called on the keyer lane).
    public var openWinkeyer: @Sendable (String, Int) throws -> any CwKeyer = { _, _ in throw InertHardwareError() }
    /// `SoundCard.player { outputDevice }` — the voice keyer's audio output (plays on the voice keyer's queue).
    public var voicePlayer: @Sendable (@escaping @Sendable () -> String?) -> VoiceKeyer.AudioOut = { _ in
        { _, _ in throw InertHardwareError() }
    }
    /// The voice keyer's wait between PTT on and the audio (`nil` = the real wait of `VoiceKeyer`; tests hold it).
    public var voicePttDelay: VoiceKeyer.Delay?
    /// `SoundCard.record(target, inputDevice)` — recording a voice message (blocks; called on the voice lane).
    public var recordMessage: @Sendable (JavaPath, String?) throws -> any MessageRecording = { _, _ in
        throw InertHardwareError()
    }
    /// Whether the app may record from the microphone (asks the user the first time; `false` = denied). Inert and
    /// tests: allowed, the recording port decides what happens next.
    public var microphoneAccess: @Sendable () async -> Bool = { true }
    /// `MacSpeech(cacheDir, voice).synthesize(text)` (`say`; blocks; called on the voice lane); `nil` = failed.
    public var synthesize: @Sendable (_ cacheDir: JavaPath, _ voice: String, _ text: String) -> JavaPath? = { _, _, _ in
        nil
    }
    /// `FldigiClient(host, port)` (called on the keyer lane).
    public var makeFldigi: @Sendable (String, Int) throws -> any FldigiPort = { _, _ in throw InertHardwareError() }
    /// `capture.start(deviceName)` — the receiver audio input (blocks; called on the audio lane).
    public var startAudio: @Sendable (AudioCapture, String?) throws(AudioIOError) -> Void = { _, _ throws(AudioIOError) in
        throw AudioIOError(InertHardwareError.message)
    }
    /// The pileup simulator's sound output with the noise level (blocks while the output opens: the
    /// simulator model calls it on its own lane). Inert: a silent sink, so the simulator runs without any audio device.
    public var makeSimAudio: @Sendable (_ noise: Double) throws -> any SimAudioSink = { _ in SilentSimAudio() }

    public init(makeCat: @escaping @Sendable (CatHooks) -> any CatPort,
                openOtrsp: @escaping @Sendable (String) throws -> Otrsp,
                openFootswitch: @escaping @Sendable (String, Footswitch.Pin, @escaping @Sendable (Bool) -> Void) throws
                    -> Footswitch,
                makeRotctld: @escaping @Sendable (String, Int) throws -> RotctldClient,
                rotorUdp: @escaping @Sendable (String, Int, String) throws -> Void,
                playPcm: @escaping @Sendable ([UInt8], WavFile.PcmFormat, String?, () -> Bool) throws(AudioIOError)
                    -> Void,
                isInert: Bool = false) {
        self.makeCat = makeCat
        self.openOtrsp = openOtrsp
        self.openFootswitch = openFootswitch
        self.makeRotctld = makeRotctld
        self.rotorUdp = rotorUdp
        self.playPcm = playPcm
        self.isInert = isInert
    }

    /// Nothing opens: CAT `connect` writes „Hardware disabled (MCL_INERT_HARDWARE)" into the CAT log and stays
    /// disconnected (the status line keeps Kotlin's „TRX odpojen"); OTRSP, the footswitch, the rotator, the UDP
    /// message, the playback, the Winkeyer, the voice audio and recording, fldigi and the receiver audio fail with
    /// `InertHardwareError` before any I/O; speech synthesis returns nothing.
    public static let inert = HardwarePorts(
        makeCat: { hooks in InertCat(log: hooks.log) },
        openOtrsp: { _ in throw InertHardwareError() },
        openFootswitch: { _, _, _ in throw InertHardwareError() },
        makeRotctld: { _, _ in throw InertHardwareError() },
        rotorUdp: { _, _, _ in throw InertHardwareError() },
        playPcm: { _, _, _, _ throws(AudioIOError) in throw AudioIOError(InertHardwareError.message) },
        isInert: true)

    /// The running app: hamlib `rigctld`, serial ports, sockets, the sound input and output, the keyers and fldigi.
    public static let live: HardwarePorts = {
        var ports: HardwarePorts = liveRadio
        ports.openWinkeyer = { port, wpm in try WinkeyerKeyer.open(portPath: port, wpm: wpm) }
        ports.voicePlayer = { device in SoundCard.player(deviceName: device) }
        ports.recordMessage = { target, device in try SoundCard.record(target: target, deviceName: device) }
        ports.microphoneAccess = { await MicrophoneAccess.request() }
        ports.synthesize = { cacheDir, voice, text in MacSpeech(cacheDir: cacheDir, voice: voice).synthesize(text) }
        ports.makeFldigi = { host, port in try FldigiClient(host: host, port: port) }
        ports.startAudio = { capture, device throws(AudioIOError) in try capture.start(deviceName: device) }
        ports.makeSimAudio = { noise in try SimAudioPlayer(noiseLevel: noise) }
        return ports
    }()

    /// The rig half of `live`.
    private static let liveRadio = HardwarePorts(
        makeCat: { hooks in
            CatSession(transverters: hooks.transverters, modes: hooks.modes, log: hooks.log,
                       translate: hooks.translate, onChange: hooks.onChange,
                       onUnexpectedError: hooks.onUnexpectedError)
        },
        openOtrsp: { path in try Otrsp.open(portPath: path) },
        openFootswitch: { path, pin, onChange in try Footswitch.open(portPath: path, pin: pin, onChange: onChange) },
        makeRotctld: { host, port in try RotctldClient(host: host, port: port) },
        rotorUdp: { host, port, message in try N1mmRotorUdp.send(host: host, port: port, message: message) },
        playPcm: { bytes, format, device, cancelled throws(AudioIOError) in
            try SoundCard.playPcm(bytes, format: format, deviceName: device, cancelled: cancelled)
        })

    /// The environment variable of.
    public static let inertVariable = "MCL_INERT_HARDWARE"

    /// `live`, unless `MCL_INERT_HARDWARE` is set (scripted runs set it at every launch of the app).
    public static func production(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> HardwarePorts {
        isInert(environment, variable: inertVariable) ? .inert : .live
    }

    /// The reading of an inert switch (`MCL_INERT_HARDWARE`, `MCL_INERT_NETWORK`): a safeguard, so any value the
    /// variable is present with — `1`, `true`, `yes`, `no`, even an empty one — means inert; only an absent variable
    /// or exactly `"0"` keeps the live ports.
    public static func isInert(_ environment: [String: String], variable: String) -> Bool {
        guard let value = environment[variable] else { return false }
        return value != "0"
    }
}

/// The CAT port of `HardwarePorts.inert`: never connects, never opens anything, never starts a daemon.
final class InertCat: CatPort, @unchecked Sendable {
    private let log: CatTrafficLog

    init(log: CatTrafficLog) {
        self.log = log
    }

    var snapshot: CatSession.Snapshot {
        CatSession.Snapshot()
    }

    func toggle(_ rc: RigConfig) {
        connect(rc)
    }

    func connect(_ rc: RigConfig) {
        appLog.notice("\(InertHardwareError.message, privacy: .public)")
        try? log.info(InertHardwareError.message)
    }

    func disconnect(_ message: String?) {}

    var isConnecting: Bool {
        false
    }

    func disconnectCancellingConnect(_ message: String?) {}

    func tune(_ freqHz: Int64) throws {}

    func setPtt(_ on: Bool) throws {}

    func setMode(_ mode: Mode?, freqHz: Int64) throws {}

    func rigOrNull() -> (any RigController)? {
        nil
    }
}
