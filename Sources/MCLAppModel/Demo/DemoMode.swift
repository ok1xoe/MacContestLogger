import Foundation
import MCLCore

/// The screenshot demo of the maintainers (`docs/screenshots.md`): a scripted app run that looks like a busy contest
/// without any hardware or outside network. Never part of a normal start: it is honoured only when `MCL_DEMO_DIR`
/// names a directory with `demo.json` AND both inert switches (`MCL_INERT_HARDWARE`, `MCL_INERT_NETWORK`) are set, as
/// `scripts/smoke-run.py` always does. It replaces the inert ports with:
///
/// - demo rigs: an in-memory CAT session per radio, connected at the frequency and mode of `demo.json`, tuning and
///   mode changes are kept in memory (no `rigctld`, no serial port, no socket);
/// - demo receiver audio: the stereo 16-bit 12 kHz WAV `audio` of `demo.json` (left = receiver 1, right = receiver 2),
///   played in a loop in real time into the receiver input (no audio device);
/// - the DX cluster and the cluster sync redirected to loopback: every telnet connection goes to
///   `127.0.0.1:<clusterPort>`, every MQTT connection to `127.0.0.1:<brokerPort>` without TLS (the maintainer's fake
///   cluster and a throwaway broker). Without a port the connection stays inert. Nothing else reaches the network.
public struct DemoMode: Sendable {

    /// The environment variable naming the demo directory.
    public static let variable = "MCL_DEMO_DIR"

    /// `demo.json`.
    public struct Script: Codable, Sendable {
        public struct Rig: Codable, Sendable {
            public var freqHz: Int64
            public var mode: String
            public var passband: Int64?
        }

        /// Radio 1 and radio 2 (a missing radio stays inert).
        public var rigs: [Rig]?
        /// The WAV file of the receiver audio (absolute, or relative to the demo directory).
        public var audio: String?
        /// The loopback port of the fake telnet cluster.
        public var clusterPort: Int?
        /// The loopback port of the throwaway MQTT broker.
        public var brokerPort: Int?
        /// Text put into the focused entry window's fields once the contest is open (field id → text; `call` is the
        /// call field).
        public var entry: [String: String]?
        /// The same for the second entry window (SO2R / SO2V).
        public var entry2: [String: String]?
        /// The demo rigs are connected at start (as the operator's TRX button would).
        public var connectRigs: Bool?
        /// The DX cluster favourite (by name) connected at start (as `{CONN} name` would).
        public var connectCluster: String?
        /// The built-in RTTY receivers open with the XY scope and the multi-channel receiver on.
        public var builtinScope: Bool?
        /// Steps run in order after the entry text: what the operator would do through the menus.
        public var actions: [Action]?
    }

    /// One scripted step (one field set).
    public struct Action: Codable, Sendable {
        /// Seconds to wait first.
        public var wait: Double?
        /// A menu item by its id (`menu.json`), as if chosen; file panels it would ask for are not shown.
        public var menu: String?
        /// Opens Settings on the tab with this key.
        public var settingsTab: String?
        /// Merges a log file (path) into the open contest, as File → Merge does after the file was chosen.
        public var merge: String?
        /// Text for the fields of an entry window (`vfo`: 0 = main, 1 = the second one).
        public var entry: [String: String]?
        public var vfo: Int?
        /// Run (`RUN`) or S&P (`SEARCH_AND_POUNCE`) for the entry window `vfo`, as the Run / S&P buttons set it.
        public var runMode: String?
        /// Brings the app to the front with the window of this title as the key window (an active title bar in the
        /// screenshot), as a click on the window does.
        public var key: String?
        /// Makes this entry window (0 / 1) the active one, as a click into it does.
        public var activate: Int?
        /// A sked added as in the Skeds window: call, kHz, mode, time (`HHmm`), note.
        public var sked: [String]?
        /// Text the next CW keyboard window opens with (sent only on Enter, which the demo never presses).
        public var cwKeyboardText: String?
        /// A contest definition (id) opened in the definition editor, as a click in its list does.
        public var definition: String?
        /// A QTC series being received, as typed into the QTC window: partner call, series (`3/10`), the lines.
        public var qtcReceive: [String]?
        /// The runner (station id) the next partner window opens with, as a click on its chip does.
        public var partnerRunner: String?
    }

    /// `Script.builtinScope` of the running demo (read by every built-in receiver pane as it opens).
    @MainActor public static var builtinScope = false

    /// The text of `Action.cwKeyboardText`, taken by the next CW keyboard window.
    @MainActor public static var pendingCwKeyboardText: String?
    /// The runner of `Action.partnerRunner`, taken by the next partner window.
    @MainActor public static var pendingPartnerRunner: String?

    public let directory: URL
    public let script: Script

    /// The demo of `environment`, `nil` unless `MCL_DEMO_DIR` is set, readable and both inert switches are on.
    public static func from(_ environment: [String: String]) -> DemoMode? {
        guard let path = environment[variable], !path.isEmpty,
              HardwarePorts.isInert(environment, variable: HardwarePorts.inertVariable),
              HardwarePorts.isInert(environment, variable: NetworkPorts.inertVariable) else { return nil }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("demo.json")),
              let script = try? JSONDecoder().decode(Script.self, from: data) else {
            appLog.error("MCL_DEMO_DIR: no readable demo.json in \(path, privacy: .public)")
            return nil
        }
        return DemoMode(directory: directory, script: script)
    }

    /// The inert hardware with the demo rigs and the demo receiver audio.
    public func hardware() -> HardwarePorts {
        var ports: HardwarePorts = .inert
        let rigs: [Script.Rig] = script.rigs ?? []
        ports.makeCat = { hooks in
            guard rigs.indices.contains(hooks.index) else { return InertCat(log: hooks.log) }
            return DemoCat(hooks: hooks, start: rigs[hooks.index])
        }
        if let audio = script.audio, let pcm = DemoAudio.stereoPcm(audio.hasPrefix("/")
            ? URL(fileURLWithPath: audio) : directory.appendingPathComponent(audio)) {
            ports.startAudio = { capture, _ throws(AudioIOError) in
                capture.startFeed(stereoPcm: pcm)
            }
        }
        return ports
    }

    /// The inert network with the cluster telnet and the cluster sync redirected to loopback. With a broker port the
    /// ports no longer say „inert" (the cluster sync would not start otherwise); every other service keeps its inert
    /// port (no HTTP, no UDP, no browser, no NTP, no plugins, no downloads).
    public func network() -> NetworkPorts {
        var ports: NetworkPorts = .inert
        if let clusterPort = script.clusterPort {
            let real = NetworkPorts.sessions()
            ports.makeSession = { hooks in
                LoopbackClusterSession(real(hooks), port: clusterPort)
            }
        }
        if let brokerPort = script.brokerPort {
            ports.makeSyncTransport = { config, persistence in
                var local: ClusterConfig = config
                local.brokerHost = "127.0.0.1"
                local.port = brokerPort
                local.tls = false
                return try NetworkPorts.liveTransport(local, persistence)
            }
            ports.isInert = false
        }
        return ports
    }
}

/// The receiver audio of the demo.
enum DemoAudio {

    /// The interleaved 16-bit stereo PCM of a WAV at `AudioCapture.sampleRate` (a mono file is doubled); `nil` = not
    /// such a file.
    static func stereoPcm(_ url: URL) -> [UInt8]? {
        guard let data = try? Data(contentsOf: url), data.count > 44,
              String(decoding: data[0..<4], as: UTF8.self) == "RIFF" else { return nil }
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        var offset = 12
        var channels = 0
        var rate = 0
        var bits = 0
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
            let size: Int = u32(offset + 4)
            let body: Int = offset + 8
            if id == "fmt " {
                channels = u16(body + 2)
                rate = u32(body + 4)
                bits = u16(body + 14)
            } else if id == "data" {
                guard rate == AudioCapture.sampleRate, bits == 16, channels == 1 || channels == 2 else { return nil }
                let end: Int = min(bytes.count, body + size)
                let pcm = Array(bytes[body..<end])
                if channels == 2 {
                    return pcm
                }
                var stereo: [UInt8] = []
                stereo.reserveCapacity(pcm.count * 2)
                var index = 0
                while index + 1 < pcm.count {
                    stereo.append(contentsOf: [pcm[index], pcm[index + 1], pcm[index], pcm[index + 1]])
                    index += 2
                }
                return stereo
            }
            offset = body + size + (size & 1)
        }
        return nil
    }
}

/// A demo radio: an in-memory rig at a fixed place that follows the app's tuning.
final class DemoRig: RigController, @unchecked Sendable {
    private let lock = NSLock()
    private var state: RigState

    init(_ state: RigState) {
        self.state = state
    }

    func read() throws -> RigState {
        lock.withLock { state }
    }

    func setFrequencyHz(_ freqHz: Int64) throws {
        lock.withLock {
            state = RigState(freqHz: freqHz, mode: state.mode, rawMode: state.rawMode, passband: state.passband,
                             split: state.split, txFreqHz: state.txFreqHz)
        }
    }

    func setMode(_ mode: Mode?, freqHz: Int64) throws {
        lock.withLock {
            let raw: String = mode.map(DemoCat.rawMode) ?? state.rawMode
            state = RigState(freqHz: state.freqHz, mode: mode ?? state.mode, rawMode: raw,
                             passband: state.passband, split: state.split, txFreqHz: state.txFreqHz)
        }
    }

    func setPtt(_ on: Bool) throws {}

    func keyPtt(unless cancelled: () -> Bool) throws -> Bool {
        false
    }

    func releasePtt() throws {}

    func sendMorse(_ text: String) throws {}

    func stopMorse() throws {}

    func setCwSpeed(_ wpm: Int) throws {}

    func setSplit(_ on: Bool, txFreqHz: Int64) throws {}

    func setOtherVfoFrequencyHz(_ freqHz: Int64) throws {}

    func setRit(_ offsetHz: Int) throws {}

    func setAntenna(_ antenna: Int) throws {}

    func selectVfo(_ vfoB: Bool) throws {}

    func swapVfo() throws {}

    func sendRaw(_ command: String) throws -> RigRawReply {
        RigRawReply(lines: [], code: -1)
    }

    func isConnected() -> Bool {
        true
    }

    func close() {}
}

/// The CAT session of a demo radio: connects at once (nothing is opened) and reports the demo rig's state.
final class DemoCat: CatPort, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let hooks: CatHooks
    private let start: DemoMode.Script.Rig
    private var current = CatSession.Snapshot()
    private var rig: DemoRig?

    init(hooks: CatHooks, start: DemoMode.Script.Rig) {
        self.hooks = hooks
        self.start = start
    }

    /// The status line of a connected rig (`CatSession`'s „TRX: … kHz  mode").
    static func status(_ state: RigState) -> String {
        String(format: "TRX: %.1f kHz  %@", state.freqKHz, state.mode?.rawValue ?? state.rawMode)
    }

    static func rawMode(_ mode: Mode) -> String {
        switch mode {
        case .ssb: return "USB"
        case .rtty: return "RTTY"
        default: return mode.rawValue
        }
    }

    var snapshot: CatSession.Snapshot {
        lock.withLock { current }
    }

    var isConnecting: Bool {
        false
    }

    func toggle(_ rc: RigConfig) {
        if snapshot.connected {
            disconnect(nil)
        } else {
            connect(rc)
        }
    }

    func connect(_ rc: RigConfig) {
        lock.withLock {
            let mode: Mode? = Mode(rawValue: start.mode.uppercased())
            let state = RigState(freqHz: start.freqHz, mode: mode, rawMode: mode.map(Self.rawMode) ?? start.mode,
                                 passband: start.passband ?? 0)
            let demo = DemoRig(state)
            rig = demo
            current = CatSession.Snapshot(state: state, statusMessage: Self.status(state), connected: true)
        }
        try? hooks.log.info("Demo rig " + String(hooks.index + 1))
        publish()
    }

    func disconnect(_ message: String?) {
        lock.withLock {
            rig = nil
            current = CatSession.Snapshot(statusMessage: message)
        }
        publish()
    }

    func disconnectCancellingConnect(_ message: String?) {
        disconnect(message)
    }

    func tune(_ freqHz: Int64) throws {
        try rig?.setFrequencyHz(freqHz)
        refresh()
    }

    func setPtt(_ on: Bool) throws {}

    func setMode(_ mode: Mode?, freqHz: Int64) throws {
        try rig?.setMode(mode, freqHz: freqHz)
        if freqHz > 0 {
            try rig?.setFrequencyHz(freqHz)
        }
        refresh()
    }

    func rigOrNull() -> (any RigController)? {
        lock.withLock { rig }
    }

    private func refresh() {
        lock.withLock {
            guard let rig, let state = try? rig.read() else { return }
            current.state = state
            current.statusMessage = Self.status(state)
        }
        publish()
    }

    private func publish() {
        hooks.onChange(snapshot)
    }
}

/// A real telnet cluster session whose every connection goes to the demo's loopback cluster.
final class LoopbackClusterSession: ClusterSessionPort, @unchecked Sendable {
    private let inner: any ClusterSessionPort
    private let port: Int

    init(_ inner: any ClusterSessionPort, port: Int) {
        self.inner = inner
        self.port = port
    }

    private func local(_ fav: DxClusterFavorite) -> DxClusterFavorite {
        var redirected: DxClusterFavorite = fav
        redirected.host = "127.0.0.1"
        redirected.port = port
        return redirected
    }

    var snapshot: DxClusterSession.Snapshot {
        inner.snapshot
    }

    var myCall: String {
        get { inner.myCall }
        set { inner.myCall = newValue }
    }

    var onSelfSpot: (@Sendable (SelfSpot) -> Void)? {
        get { inner.onSelfSpot }
        set { inner.onSelfSpot = newValue }
    }

    var onSpot: (@Sendable (DxSpot) throws -> Void)? {
        get { inner.onSpot }
        set { inner.onSpot = newValue }
    }

    func toggle(_ fav: DxClusterFavorite) throws {
        try inner.toggle(local(fav))
    }

    func connect(_ fav: DxClusterFavorite, autoLogin: Bool) throws {
        try inner.connect(local(fav), autoLogin: autoLogin)
    }

    func login(_ fav: DxClusterFavorite) {
        inner.login(local(fav))
    }

    func logout() throws {
        try inner.logout()
    }

    func send(_ command: String) throws {
        try inner.send(command)
    }

    func disconnect(_ message: String) throws {
        try inner.disconnect(message)
    }

    func idle() async {
        await inner.idle()
    }
}
