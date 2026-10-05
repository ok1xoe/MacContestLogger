import Foundation
import os

/// Footswitch (Java `footswitch/Footswitch`, N1MM Footswitch) on a serial port control line
/// (USB-RS232 adapter): the switch connects e.g. RTS→CTS or DTR→DSR. The state is polled periodically and changes
/// (debounced, 2 identical reads) go to the listener.
///
/// Edge detector and polling loop over `() -> Bool` (the Java package-private constructor); `open` opens the serial
/// port (default 9600 8N1 like jSerialComm), turns on both RTS and DTR as switch power and reads the chosen input
/// (`TIOCMGET`; a read error = `false` like jSerialComm `getCTS`) every 20 ms.
///
/// The loop runs on its own `footswitch` thread as in Java: reads the input, reports a change, waits `periodMs`.
/// `close()` drops the flag and interrupts the wait (Java `interrupt`), then calls `onClose` (errors are
/// ignored); the listener is called from the switch thread.
public final class Footswitch: Sendable {

    /// Input line the switch is on (`config.json` `footswitchPin`).
    public enum Pin: String, Sendable, CaseIterable {
        case cts = "CTS"
        case dsr = "DSR"
        case dcd = "DCD"
    }

    /// What the switch does (N1MM: PTT, ESM Enter, CQ; `config.json` `footswitchAction`).
    public enum Action: String, Sendable, CaseIterable {
        case ptt = "PTT"
        case enter = "ENTER"
        case f1 = "F1"
    }

    /// Edge detection with debouncing: a new state applies once `stableSamples` reads confirm it (fewer than 1 = 1).
    public final class EdgeDetector {
        private let stableSamples: Int32
        private var state = false
        private var candidate = false
        private var count: Int32 = 0

        public init(stableSamples: Int32) {
            self.stableSamples = Swift.max(1, stableSamples)
        }

        /// The new state if a different one has just settled than the current one, otherwise `nil`.
        public func sample(_ raw: Bool) -> Bool? {
            if raw == state {
                count = 0
                return nil
            }
            if raw != candidate {
                candidate = raw
                count = 0
            }
            count &+= 1
            if count >= stableSamples {
                state = raw
                count = 0
                return raw
            }
            return nil
        }
    }

    private let running = OSAllocatedUnfairLock(initialState: true)
    private let wake = DispatchSemaphore(value: 0)
    private let onClose: @Sendable () throws -> Void

    /// Java package-private constructor: watches `input` every `periodMs` ms.
    init(input: @escaping @Sendable () -> Bool, onChange: @escaping @Sendable (Bool) -> Void,
         onClose: @escaping @Sendable () throws -> Void, periodMs: Int64) {
        self.onClose = onClose
        let running = self.running
        let wake = self.wake
        let thread = Thread {
            let edge = EdgeDetector(stableSamples: 2)
            // Java: a negative period kills the thread (`Thread.sleep`); but the constructor only gets a fixed one (20 ms).
            let period = DispatchTimeInterval.milliseconds(Int(Swift.max(0, Swift.min(periodMs, Int64(Int32.max)))))
            while running.withLock({ $0 }) {
                if let changed = edge.sample(input()) {
                    onChange(changed)
                }
                if wake.wait(timeout: .now() + period) == .success {
                    return // interrupted (`close`)
                }
            }
        }
        thread.name = "footswitch"
        thread.start()
    }

    /// Opens the port (RTS and DTR are both turned on as switch power) and starts watching `pin` (Java
    /// `open(portPath, pin, onChange)`). `onChange` is called from the switch thread.
    ///
    /// - Throws: `SerialPortInvalidPortError` (path does not exist — Java `getCommPort`),
    ///   `JavaIOError("Footswitch: nelze otevřít port <portPath>")` (opening failed).
    public static func open(portPath: String, pin: Pin, onChange: @escaping @Sendable (Bool) -> Void) throws -> Footswitch {
        try open(portPath: portPath, pin: pin, onChange: onChange, modem: SerialPort.PosixModemControl(),
                 periodMs: pollPeriodMs)
    }

    /// Java `new Footswitch(…, 20)` in `open`: reads the input every 20 ms.
    static let pollPeriodMs: Int64 = 20

    /// For tests: replacement for the modem lines (a pseudoterminal does not support them) and the period.
    static func open(portPath: String, pin: Pin, onChange: @escaping @Sendable (Bool) -> Void,
                     modem: any SerialPort.ModemControl, periodMs: Int64) throws -> Footswitch {
        guard let port = try SerialPort.openLikeJSerialComm(portPath: portPath, settings: SerialPort.Settings(),
                                                            modem: modem) else {
            throw JavaIOError("Footswitch: nelze otevřít port " + portPath)
        }
        try? port.setRTS(true)
        try? port.setDTR(true)
        let input: @Sendable () -> Bool
        switch pin {
        case .cts: input = { (try? port.modemStatus())?.cts ?? false }
        case .dsr: input = { (try? port.modemStatus())?.dsr ?? false }
        case .dcd: input = { (try? port.modemStatus())?.dcd ?? false }
        }
        return Footswitch(input: input, onChange: onChange, onClose: { try port.close() }, periodMs: periodMs)
    }

    public func close() {
        running.withLock { $0 = false }
        wake.signal()
        try? onClose()
    }
}
