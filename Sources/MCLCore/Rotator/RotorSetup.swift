import Foundation

/// One named rotor of the N1MM Rotor program's setup: its hamlib `rotctld` (blank host = the N1MM Rotor UDP message
/// only, sent to the configured UDP host with this name), a calibration (degrees added to what the controller reports;
/// subtracted from what it is sent) and the controller's limits (`0…360`, a 450° rotor `0…450`, a south-stop rotor
/// `-180…180`, a limited range `30…300`).
public struct RotorEntry: Equatable, Sendable {
    public var name: String
    public var host: String
    public var port: Int
    public var calibration: Int
    public var minAzimuth: Int
    public var maxAzimuth: Int

    public init(name: String, host: String = "", port: Int = 4533, calibration: Int = 0, minAzimuth: Int = 0,
                maxAzimuth: Int = 360) {
        self.name = name
        self.host = host
        self.port = port
        self.calibration = calibration
        self.minAzimuth = minAzimuth
        self.maxAzimuth = maxAzimuth
    }

    /// The default rotator of the Antennas tab (`rotatorHost`/`rotatorPort`, the UDP name), no calibration or limits.
    public static func defaultRotor(host: String, port: Int, udpName: String) -> RotorEntry {
        RotorEntry(name: udpName, host: host, port: port)
    }

    /// The stored form: the fields joined by tabs (name, host, port, calibration, min, max).
    var stored: String {
        [name, host, String(port), String(calibration), String(minAzimuth), String(maxAzimuth)]
            .joined(separator: "\t")
    }

    /// Parses the stored form; a missing or bad number is its default, limits that do not make a range are `0…360`,
    /// a blank name is no rotor.
    init?(stored: String) {
        let parts: [String] = stored.components(separatedBy: "\t").map { KotlinStrings.trim($0) }
        guard let first = parts.first, !first.isEmpty else { return nil }
        func number(_ index: Int, _ fallback: Int) -> Int {
            index < parts.count ? Int(parts[index]) ?? fallback : fallback
        }
        name = first
        host = parts.count > 1 ? parts[1] : ""
        let parsedPort: Int = number(2, 4533)
        port = (1...65_535).contains(parsedPort) ? parsedPort : 4533
        calibration = max(-359, min(359, number(3, 0)))
        let low: Int = number(4, 0)
        let high: Int = number(5, 360)
        if low < high && low >= -360 && high <= 720 {
            minAzimuth = low
            maxAzimuth = high
        } else {
            minAzimuth = 0
            maxAzimuth = 360
        }
    }

    /// Limits other than the default `0…360`.
    public var hasLimits: Bool {
        minAzimuth != 0 || maxAzimuth != 360
    }
}

/// The N1MM Rotor program setup (Swift-only `AppConfig.rotorSetup`): up to 16 named rotors, the preset bearings of
/// the F1–F10 buttons, the display of rotors broadcast on the network (N1MM Rotor, UDP 13010) and the automatic
/// antenna choice by the bearing to the station. Kept as a string map; a value equal to the default is not stored.
public struct RotorSetup: Equatable, Sendable {

    public static let maxRotors = 16
    public static let presetCount = 10

    /// The stored values (non-default ones).
    public private(set) var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        var kept: [String: String] = [:]
        for (key, value) in values where Self.isKnown(key) && !value.isEmpty {
            switch key {
            case "networkEnabled", "autoAntenna":
                if value == "true" {
                    kept[key] = value
                }
            case "networkPort":
                if let port = Int(value), (1...65_535).contains(port), port != RotorNetwork.defaultPort {
                    kept[key] = String(port)
                }
            default:
                kept[key] = value
            }
        }
        self.values = kept
    }

    private static func isKnown(_ key: String) -> Bool {
        if ["networkEnabled", "networkPort", "autoAntenna"].contains(key) {
            return true
        }
        if key.hasPrefix("preset"), let n = Int(key.dropFirst(6)), (1...presetCount).contains(n) {
            return true
        }
        if key.hasPrefix("rotor"), let n = Int(key.dropFirst(5)), (1...maxRotors).contains(n) {
            return true
        }
        return false
    }

    // MARK: - rotors

    /// The named rotors in table order.
    public var rotors: [RotorEntry] {
        get {
            (1...Self.maxRotors).compactMap { values["rotor\($0)"].flatMap(RotorEntry.init(stored:)) }
        }
        set {
            for index in 1...Self.maxRotors {
                values["rotor\(index)"] = nil
            }
            let kept: [RotorEntry] = newValue.filter { !KotlinStrings.isBlank($0.name) }.prefix(Self.maxRotors).map { $0 }
            for (index, rotor) in kept.enumerated() {
                values["rotor\(index + 1)"] = rotor.stored
            }
        }
    }

    // MARK: - presets

    /// The F1–F10 preset bearings (`nil` = an unset button).
    public var presets: [Int?] {
        get {
            (1...Self.presetCount).map { index in
                values["preset\(index)"].flatMap { Int($0) }.flatMap { (0...360).contains($0) ? $0 : nil }
            }
        }
        set {
            for index in 1...Self.presetCount {
                let value: Int? = index - 1 < newValue.count ? newValue[index - 1] : nil
                values["preset\(index)"] = value.flatMap { (0...360).contains($0) ? String($0) : nil }
            }
        }
    }

    // MARK: - network and antennas

    /// Show the rotors broadcast on the network (off by default: nothing listens unless asked).
    public var networkEnabled: Bool {
        get { values["networkEnabled"] == "true" }
        set { values["networkEnabled"] = newValue ? "true" : nil }
    }

    /// The UDP port the network rotors are received on (N1MM Rotor broadcasts on 13010).
    public var networkPort: Int {
        get { values["networkPort"].flatMap { Int($0) } ?? RotorNetwork.defaultPort }
        set {
            values["networkPort"] = (1...65_535).contains(newValue) && newValue != RotorNetwork.defaultPort
                ? String(newValue) : nil
        }
    }

    /// N1MM „Auto-select antenna based on azimuth": the antenna is chosen again by the bearing whenever the call
    /// field's station changes, not only on a band change (off by default).
    public var autoAntenna: Bool {
        get { values["autoAntenna"] == "true" }
        set { values["autoAntenna"] = newValue ? "true" : nil }
    }
}

/// The Rotator window's Setup sheet as text fields: the rotor rows, the ten presets, the network display.
public struct RotorSetupDraft: Equatable, Sendable {

    public struct Row: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public var name: String
        public var host: String
        public var port: String
        public var calibration: String
        public var minAzimuth: String
        public var maxAzimuth: String

        public init(_ entry: RotorEntry) {
            name = entry.name
            host = entry.host
            port = String(entry.port)
            calibration = entry.calibration == 0 ? "" : String(entry.calibration)
            minAzimuth = String(entry.minAzimuth)
            maxAzimuth = String(entry.maxAzimuth)
        }

        /// The entry (through the stored form, so the same bounds apply); `nil` for a blank name.
        func entry() -> RotorEntry? {
            RotorEntry(stored: [name, host, port, calibration.isEmpty ? "0" : calibration, minAzimuth, maxAzimuth]
                .map { KotlinStrings.trim($0).replacingOccurrences(of: "\t", with: " ") }
                .joined(separator: "\t"))
        }

        public static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.name == rhs.name && lhs.host == rhs.host && lhs.port == rhs.port && lhs.calibration == rhs.calibration
                && lhs.minAzimuth == rhs.minAzimuth && lhs.maxAzimuth == rhs.maxAzimuth
        }
    }

    public var rotors: [Row]
    public var presets: [String]
    public var networkEnabled: Bool
    public var networkPort: String
    private let base: RotorSetup

    public init(_ setup: RotorSetup) {
        base = setup
        rotors = setup.rotors.map(Row.init)
        presets = setup.presets.map { $0.map(String.init) ?? "" }
        networkEnabled = setup.networkEnabled
        networkPort = String(setup.networkPort)
    }

    /// A new empty rotor row (until it has a name it is not saved).
    public mutating func addRotor() {
        rotors.append(Row(RotorEntry(name: "")))
    }

    /// The setup: rows without a name dropped, unique names (the first wins), presets outside 0–360 unset, a bad
    /// port is the default; the other keys (the automatic antenna choice) as they were.
    public func applied() -> RotorSetup {
        var setup: RotorSetup = base
        var seen: Set<String> = []
        setup.rotors = rotors.compactMap { $0.entry() }.filter { seen.insert(KotlinStrings.uppercase($0.name)).inserted }
        setup.presets = presets.map { Int(KotlinStrings.trim($0)) }
        setup.networkEnabled = networkEnabled
        setup.networkPort = Int(KotlinStrings.trim(networkPort)) ?? RotorNetwork.defaultPort
        return setup
    }
}
