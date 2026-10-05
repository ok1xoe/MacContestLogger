import Foundation

/// How the CAT connection is established.
public enum ConnectionMode: String, Codable, Equatable, Sendable {
    /// The app itself starts a local `rigctld` with the given model and port.
    case launchDaemon = "LAUNCH_DAEMON"
    /// The app connects to an already running `rigctld` (host:port).
    case connectRunning = "CONNECT_RUNNING"
}

/// Serial line flow control. `hamlib` corresponds to the value for
/// `--set-conf=serial_handshake=...`.
public enum FlowControl: String, Codable, Equatable, Sendable {
    /// Do not force — keep the rig backend's default (do not pass `serial_handshake`).
    case auto = "AUTO"
    case none = "NONE"
    case xonxoff = "XONXOFF"
    case hardware = "HARDWARE"

    /// Value for `serial_handshake`; empty = do not pass.
    public var hamlib: String {
        switch self {
        case .auto: ""
        case .none: "None"
        case .xonxoff: "XONXOFF"
        case .hardware: "Hardware"
        }
    }

    /// Readable description for the UI.
    public var label: String {
        switch self {
        case .auto: "Výchozí (rig)"
        case .none: "None"
        case .xonxoff: "XON/XOFF"
        case .hardware: "Hardware"
        }
    }
}

/// Serial line parity. `hamlib` corresponds to the value hamlib expects
/// in `--set-conf=serial_parity=...`.
public enum SerialParity: String, Codable, Equatable, Sendable {
    case none = "NONE"
    case even = "EVEN"
    case odd = "ODD"
    case mark = "MARK"
    case space = "SPACE"

    public var hamlib: String {
        switch self {
        case .none: "None"
        case .even: "Even"
        case .odd: "Odd"
        case .mark: "Mark"
        case .space: "Space"
        }
    }
}

/// State of the DTR/RTS signal pins. `.unset` = keep the default (do not pass to
/// rigctld); otherwise forced via `--set-conf=dtr_state/rts_state=ON|OFF`.
public enum PinState: String, Codable, Equatable, Sendable {
    case unset = "UNSET"
    case on = "ON"
    case off = "OFF"

    public var hamlib: String {
        switch self {
        case .unset: "Unset"
        case .on: "ON"
        case .off: "OFF"
        }
    }

    /// Readable description for the UI (N1MM style).
    public var label: String {
        switch self {
        case .unset: "Výchozí"
        case .on: "Always On"
        case .off: "Always Off"
        }
    }
}

/// State of a menu item: visible+active / visible+greyed out / hidden.
///
/// Unlike the other enums in this file, the Java original has its own
/// Jackson serialization (`@JsonValue`/`@JsonCreator`): it is written to JSON in lower
/// case and reading is case-insensitive with a fallback to `ENABLE` for `null`
/// and for an unknown value. `rawValue` is therefore not the literal name of the Java constant
/// (unlike the other four enums in this file).
public enum MenuState: String, Equatable, Sendable, CaseIterable {
    case enable
    case disable
    case hidden

    public init() {
        self = .enable
    }
}

extension MenuState: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let raw = try? container.decode(String.self) else {
            self = .enable
            return
        }
        // Java `MenuState.fromString`: `valueOf(s.trim().toUpperCase(Locale.ROOT))`, else ENABLE — Java `trim`
        // (code units up to U+0020, so NBSP and U+3000 stay) and the Java upper case (`ı` → `I`, `ſ` → `S`).
        let upper: String = JavaText.toUpperCase(JavaText.trim(raw))
        self = MenuState.allCases.first { $0.rawValue.uppercased() == upper } ?? .enable
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
