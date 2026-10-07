import Foundation
import MCLCore

/// A bound UDP receiver as the integration models drive it (`WsjtxListener`, `N1mmListener`, `AdifUdpListener`; the
/// inert ports hand out none).
public protocol UdpListening: AnyObject, Sendable {
    /// The bound port (`-1` after closing).
    var boundPort: Int { get }
    /// Starts the reader thread.
    func start()
    func close()
    /// Waits (without blocking a thread) until the reader thread has ended after `close`.
    func waitUntilStopped() async
}

/// The WSJT-X receiver: the reply to the WSJT-X address goes through the same socket.
public protocol WsjtxListening: UdpListening {
    func send(_ data: [UInt8], to target: UdpEndpoint) throws(JavaSocketError)
}

extension WsjtxListener: WsjtxListening {}
extension N1mmListener: UdpListening {}
extension AdifUdpListener: UdpListening {}

/// The UDP services of the integrations: the three receivers and the broadcaster. The factories block
/// (DNS, bind) — the caller runs them on a lane of its own, never on the main thread or in the cooperative pool. The
/// receivers throw what the core throws (`JavaSocketError`: address in use, unresolved address, port out of range);
/// the inert ones return `nil` and nothing is bound.
public struct UdpPorts: Sendable {
    public var makeWsjtxListener: @Sendable (_ host: String, _ port: Int, _ handler: WsjtxListener.Handler) throws
        -> (any WsjtxListening)?
    public var makeN1mmListener: @Sendable (_ host: String, _ port: Int, _ handler: @escaping @Sendable (String) -> Void)
        throws -> (any UdpListening)?
    public var makeAdifListener: @Sendable (_ host: String, _ port: Int, _ handler: @escaping @Sendable (String) -> Void)
        throws -> (any UdpListening)?
    public var makeBroadcaster: @Sendable () throws -> any Broadcaster

    public init(
        makeWsjtxListener: @escaping @Sendable (String, Int, WsjtxListener.Handler) throws -> (any WsjtxListening)?,
        makeN1mmListener: @escaping @Sendable (String, Int, @escaping @Sendable (String) -> Void) throws
            -> (any UdpListening)?,
        makeAdifListener: @escaping @Sendable (String, Int, @escaping @Sendable (String) -> Void) throws
            -> (any UdpListening)?,
        makeBroadcaster: @escaping @Sendable () throws -> any Broadcaster) {
        self.makeWsjtxListener = makeWsjtxListener
        self.makeN1mmListener = makeN1mmListener
        self.makeAdifListener = makeAdifListener
        self.makeBroadcaster = makeBroadcaster
    }

    /// Nothing binds, the broadcaster sends nowhere.
    public static let inert = UdpPorts(
        makeWsjtxListener: { _, _, _ in nil },
        makeN1mmListener: { _, _, _ in nil },
        makeAdifListener: { _, _, _ in nil },
        makeBroadcaster: { InertBroadcaster() })

    /// The real sockets.
    public static let live = UdpPorts(
        makeWsjtxListener: { host, port, handler in
            try WsjtxListener(bindHost: host, bindPort: port, handler: handler)
        },
        makeN1mmListener: { host, port, handler in
            try N1mmListener(bindHost: host, bindPort: port, handler: handler)
        },
        makeAdifListener: { host, port, handler in
            try AdifUdpListener(bindHost: host, bindPort: port, handler: handler)
        },
        makeBroadcaster: { try UdpBroadcaster() })
}

/// The broadcaster of `UdpPorts.inert`: sends nothing.
final class InertBroadcaster: Broadcaster, @unchecked Sendable {
    func send(_ xml: String, _ targets: [Target]) {}
    func send(_ data: [UInt8], _ targets: [Target]) {}
    func close() {}
}

/// The cluster sync transport of `NetworkPorts.inert`: never opens a socket; `connect` fails with
/// `NetworkPorts.disabledMessage`, everything else is the core's no-op default.
final class InertSyncTransport: SyncTransport, @unchecked Sendable {
    var isConnected: Bool { false }
    func connect() throws {
        throw SyncTransportError(NetworkPorts.disabledMessage)
    }
    func publishInsert(_ command: QsoCommand) throws {}
    func publishUpdate(_ command: QsoCommand) throws {}
    func publishDelete(_ command: DeleteCommand) throws {}
    func subscribeState(_ listener: @escaping SyncListener<QsoState>) throws {}
    func close() {}
}

/// The HTTP POSTs of the online services (Club Log live stream, the score reporting). Both block — the caller runs
/// them on a lane of its own. The inert ports fail before any I/O with `NetworkPorts.disabledMessage`.
public struct OnlinePorts: Sendable {
    /// `ClubLogClient.upload(email, password, callsign, apiKey, adif)`.
    public var uploadClubLog: @Sendable (_ email: String, _ password: String, _ callsign: String, _ apiKey: String,
                                         _ adif: String) throws -> ClubLogClient.Outcome
    /// `ScorePoster.post(url, xml)` → the HTTP status (and the reason a server gives for a rejection).
    public var postScore: @Sendable (_ url: String, _ xml: String) throws -> ScoreResponse

    public init(
        uploadClubLog: @escaping @Sendable (String, String, String, String, String) throws -> ClubLogClient.Outcome,
        postScore: @escaping @Sendable (String, String) throws -> ScoreResponse) {
        self.uploadClubLog = uploadClubLog
        self.postScore = postScore
    }

    public static let inert = OnlinePorts(
        uploadClubLog: { _, _, _, _, _ in throw SyncTransportError(NetworkPorts.disabledMessage) },
        postScore: { _, _ in throw SyncTransportError(NetworkPorts.disabledMessage) })

    /// The real clients (`clublog.org`, the configured scoreboard URL).
    public static let live = OnlinePorts(
        uploadClubLog: { email, password, callsign, apiKey, adif in
            try ClubLogClient().upload(email: email, password: password, callsign: callsign, apiKey: apiKey,
                                       adifRecord: adif)
        },
        postScore: { url, xml in
            try ScorePoster().postDetailed(url, xml: xml)
        })
}

/// The clock probe: the offset of the computer clock from the server in ms (positive = the computer is behind),
/// blocking-free (`async`); the inert one throws before any I/O.
public typealias ClockProbe = @Sendable (_ host: String) async throws -> Int64

/// Plugins as the integration model fires them (`PluginRunner`); blocking — called on a lane of its own.
public protocol PluginRunning: Sendable {
    func fire(_ event: PluginRunner.Event, json: String) -> [PluginRunner.Result]
    /// `fire` under an overall deadline (the quit's).
    func fire(_ event: PluginRunner.Event, json: String, deadline: @Sendable () -> Date?) -> [PluginRunner.Result]
    /// The executables of the event (a directory listing).
    func plugins(_ event: PluginRunner.Event) -> [String]
}

extension PluginRunner: PluginRunning {}

/// A running window plugin as the app talks to it (`PluginProcess`).
public protocol PluginConnection: AnyObject, Sendable {
    func start() throws(ProcessRunnerError)
    /// Queues one line (never blocks).
    func send(_ line: String) -> PluginSendResult
    /// Closes the plugin's input after the queued lines.
    func closeInput()
    func terminate(graceMs: Int)
    func kill()
    func waitForExit() async
    var isRunning: Bool { get }
}

extension PluginProcess: PluginConnection {}

/// Starts nothing yet: makes the connection of a window plugin with the environment variables added for it.
public typealias PluginLauncher = @Sendable (_ package: PluginPackage, _ environment: [String: String],
                                              _ handlers: PluginProcess.Handlers) -> any PluginConnection

/// The plugin runner factory and the window-plugin launcher. Plugins run local executables, so they are inert under
/// either switch (`MCL_INERT_NETWORK` and `MCL_INERT_HARDWARE`): `makeRunner` returns `nil` and there is no
/// launcher.
public struct PluginsPorts: Sendable {
    public var makeRunner: @Sendable (_ root: String, _ timeoutMs: Int64) -> (any PluginRunning)?
    /// `nil` = window plugins are never started.
    public var launchWindowPlugin: PluginLauncher?

    public init(makeRunner: @escaping @Sendable (String, Int64) -> (any PluginRunning)?,
                launchWindowPlugin: PluginLauncher? = nil) {
        self.makeRunner = makeRunner
        self.launchWindowPlugin = launchWindowPlugin
    }

    public static let inert = PluginsPorts { _, _ in nil }

    public static let live = PluginsPorts(
        makeRunner: { root, timeoutMs in PluginRunner(root: root, timeoutMs: timeoutMs) },
        launchWindowPlugin: liveLauncher)

    /// The real process of a window plugin.
    public static let liveLauncher: PluginLauncher = { package, environment, handlers in
        PluginProcess(executable: package.executable, directory: package.directory, environment: environment,
                      handlers: handlers)
    }
}

/// Kotlin `SntpClient.query(server, 123, 3000)`.
enum LiveClockProbe {
    static let port: UInt16 = 123
    static let timeoutMs = 3_000

    static let probe: ClockProbe = { host in
        try await SNTPClient.query(host: host, port: port, timeoutMs: timeoutMs).offsetMs
    }
}
