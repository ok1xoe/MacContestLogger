import Foundation

extension RigScanner {

    /// Scan result — the found combination and the frequency read (Java record `Outcome`).
    public struct Outcome: Equatable, Sendable {
        public let candidate: Candidate
        public let freqHz: Int64

        public init(candidate: Candidate, freqHz: Int64) {
            self.candidate = candidate
            self.freqHz = freqHz
        }
    }

    /// Progress monitoring and the ability to abort (Java interface `Listener`); called on the scan thread.
    public protocol Listener {
        func onProbe(_ candidate: Candidate)
        func isCancelled() -> Bool
    }

    static let connectAttempts = 30
    static let connectRetryMs = 100
    static let connectTimeoutMs = 600
    static let pauseMs = 300
    static let minFreqHz: Int64 = 1_700_000
    static let maxFreqHz: Int64 = 470_000_000

    /// What the scan launches and where it connects — tests substitute a harmless daemon replacement and the ports of fake servers.
    struct Environment: Sendable {
        var makeManager: @Sendable () -> RigctldProcessManager
        /// Candidate index → daemon port.
        var port: @Sendable (Int) -> Int
        var log: CatTrafficLog
        /// Client connect and read timeout (Java's 600 ms; generous in tests).
        var clientTimeoutMs: Int = RigScanner.connectTimeoutMs
        /// Client mode mapping (Java: global `HamlibModes`; does not affect the frequency).
        var modes: HamlibModeProvider = { HamlibModeMapping.default }

        /// Java `SCAN_PORT_BASE + idx % 50`.
        static func livePort(_ index: Int) -> Int {
            4600 + index % 50
        }

        static let live = Environment(makeManager: { RigctldProcessManager() }, port: livePort, log: .shared)

        init(makeManager: @escaping @Sendable () -> RigctldProcessManager, port: @escaping @Sendable (Int) -> Int,
             log: CatTrafficLog, clientTimeoutMs: Int = RigScanner.connectTimeoutMs,
             modes: @escaping HamlibModeProvider = { HamlibModeMapping.default }) {
            self.makeManager = makeManager
            self.port = port
            self.log = log
            self.clientTimeoutMs = clientTimeoutMs
            self.modes = modes
        }
    }

    /// Goes through the candidates and returns the first that responds (Java `scan`): for each it launches `rigctld` on port
    /// `4600 + idx % 50`, tries connecting 30× at 100 ms intervals (while the daemon lives), reads the frequency; a match is
    /// 1.7–470 MHz. 300 ms pause between candidates. `device` must be the full serial port path.
    /// Blocks (seconds per candidate) — call off Swift's shared pool.
    /// `modes` = the app's mode mapping (Java global `HamlibModes`; does not affect the scan result).
    public static func scan(device: String, candidates: [Candidate], listener: any Listener,
                            modes: @escaping HamlibModeProvider = { HamlibModeMapping.default }) -> Outcome? {
        var environment = Environment.live
        environment.modes = modes
        return scan(device: device, candidates: candidates, listener: listener, environment: environment)
    }

    static func scan(device: String, candidates: [Candidate], listener: any Listener, environment: Environment) -> Outcome? {
        var index = 0
        for candidate in candidates {
            if listener.isCancelled() {
                break
            }
            listener.onProbe(candidate)
            let port = environment.port(index)
            index += 1
            if let freq = probe(device: device, candidate: candidate, port: port, environment: environment) {
                return Outcome(candidate: candidate, freqHz: freq)
            }
        }
        return nil
    }

    /// One attempt; any error (Java `catch (RuntimeException)`) = failure.
    private static func probe(device: String, candidate: Candidate, port: Int, environment: Environment) -> Int64? {
        let manager = environment.makeManager()
        var client: RigctldClient?
        defer {
            client?.close()
            manager.close()
            sleep(ms: pauseMs) // release the port/process before the next attempt
        }
        do {
            try environment.log.info("scan: " + candidate.label + " @ " + String(candidate.baud) + " baud (port "
                + String(port) + ")")
            try manager.start(model: candidate.model, device: device, baud: candidate.baud, port: port,
                              serial: SerialParams(dataBits: 8, stopBits: 1, parity: "None", handshake: "None",
                                                   rts: "Unset", dtr: "Unset"))
            client = try connectWithRetry(manager, port: port, environment: environment)
            guard let client else {
                return nil // rigctld did not start / rig_open failed
            }
            let f = try client.read().freqHz
            if f >= minFreqHz && f <= maxFreqHz {
                try environment.log.info("scan: ODPOVĚĎ " + candidate.label + " @ " + String(candidate.baud)
                    + " \u{2192} " + JavaDouble.toString(Double(f) / 1000.0) + " kHz")
                return f
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Repeated connecting while the daemon lives; only `CatException` is retried (Java `catch (CatException)`).
    private static func connectWithRetry(_ manager: RigctldProcessManager, port: Int,
                                         environment: Environment) throws -> RigctldClient? {
        for _ in 0..<connectAttempts {
            if !manager.isAlive {
                return nil // rigctld exited (wrong model/baud)
            }
            do {
                return try RigctldClient(host: "localhost", port: port, timeoutMs: environment.clientTimeoutMs,
                                         modes: environment.modes, log: environment.log)
            } catch is CatException {
                sleep(ms: connectRetryMs)
            }
        }
        return nil
    }

    private static func sleep(ms: Int) {
        Thread.sleep(forTimeInterval: Double(ms) / 1_000)
    }
}
