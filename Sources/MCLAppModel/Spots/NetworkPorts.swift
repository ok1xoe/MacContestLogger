import Foundation
import MCLCore
#if canImport(AppKit)
import AppKit
#endif

/// One DX cluster telnet connection as the cluster model drives it (`DxClusterSession`; the inert port opens
/// nothing). The mutating calls run only on the connection's `ClusterLane`, never on the main thread or in Swift's
/// cooperative pool; `snapshot` is a short read under the session's lock (the main actor re-reads it after every
/// `onChange`).
public protocol ClusterSessionPort: AnyObject, Sendable {
    var snapshot: DxClusterSession.Snapshot { get }
    /// The station's own call for the „you were spotted" report.
    var myCall: String { get set }
    var onSelfSpot: (@Sendable (SelfSpot) -> Void)? { get set }
    var onSpot: (@Sendable (DxSpot) throws -> Void)? { get set }
    func toggle(_ fav: DxClusterFavorite) throws
    func connect(_ fav: DxClusterFavorite, autoLogin: Bool) throws
    func login(_ fav: DxClusterFavorite)
    func logout() throws
    func send(_ command: String) throws
    func disconnect(_ message: String) throws
    /// Waits until the session's own threads (connect with auto-login, sending) have finished.
    func idle() async
}

extension DxClusterSession: ClusterSessionPort {}

/// What a cluster session is built with (`DxClusterSession` initialiser arguments). The callbacks run on the
/// session's threads; the cluster model hops to the main actor itself.
public struct ClusterHooks: Sendable {
    /// The shared spot buffer (parallel connections write into the main one's).
    public let spots: SpotBuffer
    /// The shared traffic log.
    public let log: DxClusterTrafficLog
    /// `[tag] ` prefix of the log lines; empty for the main connection.
    public let tag: String
    public let translate: @Sendable (String) -> String
    public let onChange: @Sendable (DxClusterSession.Snapshot) -> Void
    public let onUnexpectedError: @Sendable (any Error) -> Void
}

/// Opens a page in the browser (Kotlin `BrowserOpener.open(url)` on `Dispatchers.IO`).
public struct UrlOpener: Sendable {
    public let open: @Sendable (String) -> Void

    public init(open: @escaping @Sendable (String) -> Void) {
        self.open = open
    }

    /// Nothing opens.
    public static let inert = UrlOpener { url in
        appLog.notice("\(NetworkPorts.disabledMessage, privacy: .public): \(url, privacy: .public)")
    }

    /// `NSWorkspace.shared.open` (the caller runs it on a lane of its own).
    public static let workspace = UrlOpener { url in
        #if canImport(AppKit)
        if let target = URL(string: url) {
            NSWorkspace.shared.open(target)
        }
        #endif
    }
}

/// The network the spot models reach: the DX cluster and RBN telnet sessions (main and parallel), the
/// callbook HTTP (HamQTH, QRZ.com) and the browser. `inert` is the default of `AppModel.Environment`: no session
/// connects (its `connect` writes `disabledMessage` into the traffic log and the state stays Kotlin's „Odpojeno"), the
/// callbooks get a failure before any I/O (their lookups end empty) and the browser does not open. Only
/// `Environment.production()` passes `live`, and not even it when `MCL_INERT_NETWORK` is present with any value but
/// `"0"`. Tests pass a session factory over a fake telnet server on `127.0.0.1`, a scripted `HttpGetter` and a
/// recording opener.
public struct NetworkPorts: Sendable {
    /// A cluster telnet session.
    public var makeSession: @Sendable (ClusterHooks) -> any ClusterSessionPort
    /// The callbook HTTP GET (blocks; called on the callbook lane).
    public var http: any HttpGetter
    /// The browser.
    public var urlOpener: UrlOpener
    /// The cluster sync transport (MQTT) for the station's settings and the persistence directory of its session;
    /// blocking to connect — the caller connects on a lane of its own.
    public var makeSyncTransport: @Sendable (_ config: ClusterConfig, _ persistenceDir: URL) throws
        -> any SyncTransport
    /// The UDP receivers and the broadcaster.
    public var udp: UdpPorts
    /// The Club Log and score reporting POSTs.
    public var online: OnlinePorts
    /// The NTP probe of the clock check.
    public var clock: ClockProbe
    /// The plugin runner (inert under `MCL_INERT_HARDWARE` too).
    public var plugins: PluginsPorts
    /// `true` for the inert ports.
    public var isInert: Bool

    /// The network services default to inert, so a test that passes only the spot ports opens nothing else.
    public init(makeSession: @escaping @Sendable (ClusterHooks) -> any ClusterSessionPort, http: any HttpGetter,
                urlOpener: UrlOpener,
                makeSyncTransport: @escaping @Sendable (ClusterConfig, URL) throws -> any SyncTransport
                    = NetworkPorts.inertTransport,
                udp: UdpPorts = .inert, online: OnlinePorts = .inert,
                clock: @escaping ClockProbe = NetworkPorts.inertClock,
                plugins: PluginsPorts = .inert, isInert: Bool = false) {
        self.makeSession = makeSession
        self.http = http
        self.urlOpener = urlOpener
        self.makeSyncTransport = makeSyncTransport
        self.udp = udp
        self.online = online
        self.clock = clock
        self.plugins = plugins
        self.isInert = isInert
    }

    /// The environment variable of.
    public static let inertVariable = "MCL_INERT_NETWORK"
    /// The log line of every inert port (never shown in the status line).
    public static let disabledMessage = "Network disabled (MCL_INERT_NETWORK)"

    /// Nothing reaches the network.
    public static let inert = NetworkPorts(
        makeSession: { hooks in InertClusterSession(log: hooks.log) },
        http: InertHttpGetter(), urlOpener: .inert, makeSyncTransport: inertTransport, udp: .inert,
        online: .inert, clock: inertClock, plugins: .inert, isInert: true)

    /// The transport of the inert ports: opens nothing, `connect` fails with `disabledMessage`.
    @Sendable public static func inertTransport(_ config: ClusterConfig, _ persistenceDir: URL) throws
        -> any SyncTransport {
        InertSyncTransport()
    }

    /// The probe of the inert ports: fails before any I/O.
    @Sendable public static func inertClock(_ host: String) async throws -> Int64 {
        throw SyncTransportError(disabledMessage)
    }

    /// MQTT over `MqttSyncTransport` (client id = station id; user name and password verbatim, like Kotlin).
    @Sendable public static func liveTransport(_ config: ClusterConfig, _ persistenceDir: URL) throws
        -> any SyncTransport {
        return MqttSyncTransport(host: config.brokerHost, port: config.port, clientId: config.stationId,
                                 username: config.username, password: config.password,
                                 persistenceDir: persistenceDir,
                                 tls: config.tls)
    }

    /// The running app: telnet to the configured clusters, HTTPS to the callbooks, the system browser.
    public static let live = NetworkPorts(makeSession: sessions(), http: URLSessionHttpGetter(),
                                          urlOpener: .workspace, makeSyncTransport: liveTransport, udp: .live,
                                          online: .live, clock: LiveClockProbe.probe, plugins: .live)

    /// `live`, unless `MCL_INERT_NETWORK` is set (the reading of `HardwarePorts.isInert`). The plugins stay inert
    /// under `MCL_INERT_HARDWARE` as well (they run local executables).
    /// `live` is a parameter so a test can hand in counting factories and watch which ones the switches select.
    public static func production(environment: [String: String] = ProcessInfo.processInfo.environment,
                                  live: NetworkPorts = .live) -> NetworkPorts {
        guard !HardwarePorts.isInert(environment, variable: inertVariable) else { return .inert }
        var ports: NetworkPorts = live
        if HardwarePorts.isInert(environment, variable: HardwarePorts.inertVariable) {
            ports.plugins = .inert
        }
        return ports
    }

    /// Real `DxClusterSession`s with Kotlin's timing; `sleep` replaces the session's `delay` (the 400 ms before the
    /// password and the 1,500 ms before the auto-login — tests hold and release it), `nil` = a real wait.
    public static func sessions(sleep: (@Sendable (Int) -> Void)? = nil)
        -> @Sendable (ClusterHooks) -> any ClusterSessionPort {
        { hooks in
            let wait: @Sendable (Int) -> Void = sleep ?? { ms in
                Thread.sleep(forTimeInterval: Double(max(ms, 0)) / 1_000)
            }
            return DxClusterSession(spots: hooks.spots, log: hooks.log, tag: hooks.tag,
                                    timing: DxClusterSession.Timing(), clock: { Date() },
                                    translate: hooks.translate, onChange: hooks.onChange,
                                    onUnexpectedError: hooks.onUnexpectedError, sleep: wait)
        }
    }
}

/// The callbook HTTP of `NetworkPorts.inert`: fails before any I/O.
struct InertHttpGetter: HttpGetter {
    func get(_ url: String) throws(HttpGetFailure) -> HttpGetResponse {
        throw HttpGetFailure(NetworkPorts.disabledMessage)
    }
}

/// The cluster session of `NetworkPorts.inert`: never connects, never opens a socket. The state stays the default
/// (Kotlin „Odpojeno", not connected), so `login`, `logout` and `send` have nothing to talk to.
final class InertClusterSession: ClusterSessionPort, @unchecked Sendable {
    private let log: DxClusterTrafficLog
    private let lock = NSLock()
    private var call = ""
    private var selfSpot: (@Sendable (SelfSpot) -> Void)?
    private var spot: (@Sendable (DxSpot) throws -> Void)?

    init(log: DxClusterTrafficLog) {
        self.log = log
    }

    var snapshot: DxClusterSession.Snapshot {
        DxClusterSession.Snapshot()
    }

    var myCall: String {
        get { lock.withLock { call } }
        set { lock.withLock { call = newValue } }
    }

    var onSelfSpot: (@Sendable (SelfSpot) -> Void)? {
        get { lock.withLock { selfSpot } }
        set { lock.withLock { selfSpot = newValue } }
    }

    var onSpot: (@Sendable (DxSpot) throws -> Void)? {
        get { lock.withLock { spot } }
        set { lock.withLock { spot = newValue } }
    }

    func toggle(_ fav: DxClusterFavorite) throws {
        try connect(fav, autoLogin: false)
    }

    func connect(_ fav: DxClusterFavorite, autoLogin: Bool) throws {
        appLog.notice("\(NetworkPorts.disabledMessage, privacy: .public)")
        try log.info(NetworkPorts.disabledMessage)
    }

    func login(_ fav: DxClusterFavorite) {}

    func logout() throws {}

    func send(_ command: String) throws {}

    func disconnect(_ message: String) throws {}

    func idle() async {}
}
