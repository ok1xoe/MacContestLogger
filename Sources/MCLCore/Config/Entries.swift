import Foundation

/// Saved window geometry (in dp) for restoring position and size between runs.
/// `width`/`height` values <= 0 mean "size not specified". The position (`x`,`y`)
/// is valid whenever the object exists in the map of saved window geometries.
public struct WindowGeometry: Codable, Equatable, Sendable {
    public var x: Int = 0
    public var y: Int = 0
    public var width: Int = 0
    public var height: Int = 0

    enum CodingKeys: String, CodingKey { case x, y, width, height }

    public init() {}

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WindowGeometry()
        x = c.value(.x, default: d.x)
        y = c.value(.y, default: d.y)
        width = c.value(.width, default: d.width)
        height = c.value(.height, default: d.height)
    }

    /// Does the window have a valid saved size?
    public func hasSize() -> Bool {
        width > 0 && height > 0
    }
}

/// One antenna in the antenna table (N1MM Configurer → Antennas): code for the switch /
/// band decoder (0–15), name, bands it can be used on, and the sector it points to
/// (for automatic selection by azimuth to the other station).
public struct AntennaEntry: Codable, Equatable, Sendable {
    public var code: Int = 0
    public var name: String = ""
    /// Bands separated by commas in ADIF notation (`20m,15m`) or in MHz (`14, 21`).
    public var bands: String = ""
    /// Sector in degrees `120-240`; empty = omnidirectional.
    public var sector: String = ""

    enum CodingKeys: String, CodingKey { case code, name, bands, sector }

    public init() {}

    public init(code: Int, name: String, bands: String, sector: String) {
        self.code = code
        self.name = name
        self.bands = bands
        self.sector = sector
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AntennaEntry()
        code = c.value(.code, default: d.code)
        name = c.value(.name, default: d.name)
        bands = c.value(.bands, default: d.bands)
        sector = c.value(.sector, default: d.sector)
    }
}

/// Transverter (N1MM Configurer → transverter offset): the rig works on an intermediate frequency
/// `ifLowKHz…ifHighKHz`, real frequency = IF + `offsetKHz`
/// (2 m via 28 MHz: IF 28000–30000, offset 116000).
public struct TransverterEntry: Codable, Equatable, Sendable {
    public var name: String = ""
    public var ifLowKHz: Int = 0
    public var ifHighKHz: Int = 0
    public var offsetKHz: Int = 0
    public var enabled: Bool = true

    enum CodingKeys: String, CodingKey { case name, ifLowKHz, ifHighKHz, offsetKHz, enabled }

    public init() {}

    public init(name: String, ifLowKHz: Int, ifHighKHz: Int, offsetKHz: Int, enabled: Bool) {
        self.name = name
        self.ifLowKHz = ifLowKHz
        self.ifHighKHz = ifHighKHz
        self.offsetKHz = offsetKHz
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TransverterEntry()
        name = c.value(.name, default: d.name)
        ifLowKHz = c.value(.ifLowKHz, default: d.ifLowKHz)
        ifHighKHz = c.value(.ifHighKHz, default: d.ifHighKHz)
        offsetKHz = c.value(.offsetKHz, default: d.offsetKHz)
        enabled = c.value(.enabled, default: d.enabled)
    }
}

/// Band note (DXLog Band notes): a note for a frequency (`freqKHz > 0`,
/// a marker in the bandmap) or for a whole band (`band`, without a frequency).
public struct BandNote: Codable, Equatable, Sendable {
    public var band: String = ""
    public var freqKHz: Double = 0
    public var text: String = ""

    enum CodingKeys: String, CodingKey { case band, freqKHz, text }

    public init() {}

    public init(band: String, freqKHz: Double, text: String) {
        self.band = band
        self.freqKHz = freqKHz
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BandNote()
        band = c.value(.band, default: d.band)
        freqKHz = c.value(.freqKHz, default: d.freqKHz)
        text = c.value(.text, default: d.text)
    }
}

/// One DX cluster blacklist entry (callsign or spotter) in `config.json`.
///
/// The time added is stored as an ISO-8601 string (`Instant.now().toString()`),
/// not as a date type — `ConfigStore` in the Java version uses a bare Jackson mapper
/// without JavaTimeModule. An empty time means unknown (a migrated old entry).
public struct BlacklistEntry: Codable, Equatable, Sendable {
    public var value: String = ""
    public var addedAtUtc: String = ""
    public var note: String = ""

    enum CodingKeys: String, CodingKey { case value, addedAtUtc, note }

    public init() {}

    public init(value: String, addedAtUtc: String, note: String) {
        self.value = value
        self.addedAtUtc = addedAtUtc
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BlacklistEntry()
        value = c.value(.value, default: d.value)
        addedAtUtc = c.value(.addedAtUtc, default: d.addedAtUtc)
        note = c.value(.note, default: d.note)
    }
}

/// Sked — an arranged contact (N1MM Sked system): who, where, when. Stored with the contest.
///
/// In Java `id` is generated randomly (`UUID.randomUUID()`) if missing or
/// empty — the same behaviour is kept here, so two different entries never
/// share an identity, even if they arise from empty/missing JSON.
public struct SkedEntry: Codable, Equatable, Sendable {
    public var id: String = UUID().uuidString
    /// Always trimmed and uppercase.
    ///
    /// Note: `didSet` does not fire on the first assignment inside the type's own
    /// init (Swift does not call observers during a type's own initialization) —
    /// so both of our initializers normalize `call` explicitly via
    /// `SkedEntry.normalizeCall`, rather than relying on `didSet`. `didSet` remains
    /// for normalization on later mutation after the instance is created.
    public var call: String = "" {
        didSet {
            let normalized = SkedEntry.normalizeCall(call)
            if normalized != call { call = normalized }
        }
    }
    public var freqHz: Int = 0
    public var mode: String = ""
    /// Sked time in UTC, ISO-8601.
    public var atUtc: String = ""
    public var note: String = ""

    enum CodingKeys: String, CodingKey { case id, call, freqHz, mode, atUtc, note }

    public init() {}

    public init(call: String, freqHz: Int, mode: String, atUtc: String, note: String) {
        self.call = SkedEntry.normalizeCall(call)
        self.freqHz = freqHz
        self.mode = mode
        self.atUtc = atUtc
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SkedEntry()
        let rawId = c.value(.id, default: "")
        // Java `setId`: `id == null || id.isBlank()` → new UUID. `isBlank()`
        // goes by `Character.isWhitespace`, where U+00A0 (nor U+2007, U+202F)
        // is **not** white — Java keeps such an `id`. Swift's
        // `.whitespacesAndNewlines` would discard it and generate a new UUID,
        // so the entry in `config.json` would be renamed on every load.
        id = JavaText.isBlank(rawId) ? UUID().uuidString : rawId
        call = SkedEntry.normalizeCall(c.value(.call, default: d.call))
        freqHz = c.value(.freqHz, default: d.freqHz)
        mode = c.value(.mode, default: d.mode)
        atUtc = c.value(.atUtc, default: d.atUtc)
        note = c.value(.note, default: d.note)
    }

    /// Java `setCall`: `call.trim().toUpperCase()` — trims characters ≤ U+0020
    /// (`JavaText.trim`), not Swift's `.whitespacesAndNewlines`. The non-breaking
    /// space U+00A0, U+2007, U+202F and DEL (U+007F) in a callsign stay.
    private static func normalizeCall(_ call: String) -> String {
        JavaText.trim(call).uppercased()
    }
}

/// One F-key message: the button label and content in N1MM format
/// (for SSB comma-separated wav files and macros, e.g. `{OPERATOR}/CQ.wav`).
public struct FunctionKeyMessage: Codable, Equatable, Sendable {
    public var label: String = ""
    public var text: String = ""

    enum CodingKeys: String, CodingKey { case label, text }

    public init() {}

    public init(label: String, text: String) {
        self.label = label
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FunctionKeyMessage()
        label = c.value(.label, default: d.label)
        text = c.value(.text, default: d.text)
    }
}

/// One favorite DX cluster (telnet spotting network) in `config.json`. The password is
/// stored in plain text (consistent with Java `ClusterConfig.getPassword()`).
public struct DxClusterFavorite: Codable, Equatable, Sendable {
    public static let defaultPort = 7300

    public var name: String = ""
    public var host: String = ""
    public var port: Int = DxClusterFavorite.defaultPort
    public var login: String = ""
    public var password: String = ""
    /// Concurrent connection (DXLog.net DXC: several nodes and skimmers at once): kept
    /// connected alongside the main cluster and its spots go into the same bandmap.
    public var parallel: Bool = false

    enum CodingKeys: String, CodingKey { case name, host, port, login, password, parallel }

    public init() {}

    public init(name: String, host: String, port: Int, login: String, password: String) {
        self.name = name
        self.host = host
        self.port = port
        self.login = login
        self.password = password
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DxClusterFavorite()
        name = c.value(.name, default: d.name)
        host = c.value(.host, default: d.host)
        port = c.value(.port, default: d.port)
        login = c.value(.login, default: d.login)
        password = c.value(.password, default: d.password)
        parallel = c.value(.parallel, default: d.parallel)
    }
}

/// One preset command button in the DX Cluster window: the displayed label
/// (`label`) and the command text (`command`) sent to the cluster on click.
public struct DxClusterCommand: Codable, Equatable, Sendable {
    public var label: String = ""
    public var command: String = ""

    enum CodingKeys: String, CodingKey { case label, command }

    public init() {}

    public init(label: String, command: String) {
        self.label = label
        self.command = command
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DxClusterCommand()
        label = c.value(.label, default: d.label)
        command = c.value(.command, default: d.command)
    }
}
