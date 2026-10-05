import Foundation

/// Editable rows of the Settings draft — `ui/configurer/ConfigurerDraft.kt:536-544, 616-673` and `AntennaDraft`
/// (`AntennasTab.kt:81-88`).
///
/// Every row carries an `id` for list identity in the views; equality ignores it (two drafts read from the same
/// configuration are equal).
public enum ConfigurerRows {

    /// `numStr` (`ConfigurerDraft.kt:617`): a whole number without the decimal zero (`7040.0` → `"7040"`, via
    /// Kotlin `Double.toLong()`, which saturates ±Infinity to `Long.MAX/MIN_VALUE`), otherwise Java
    /// `Double.toString` (`7040.5`, `NaN`, `1.0E-4`).
    public static func numStr(_ value: Double) -> String {
        guard value == value.rounded(.down) else { return JavaDouble.toString(value) }
        return String(kotlinToLong(value))
    }

    /// Kotlin `Double.toLong()`: NaN → 0, saturating at the `Long` range.
    static func kotlinToLong(_ value: Double) -> Int64 {
        if value.isNaN { return 0 }
        if value >= 9_223_372_036_854_775_807.0 { return Int64.max }
        if value <= -9_223_372_036_854_775_808.0 { return Int64.min }
        return Int64(value)
    }

    /// Kotlin `String.toLongOrNull()` (no trimming).
    static func toLongOrNull(_ text: String) -> Int64? {
        try? JavaInteger.parseLong(text)
    }

    /// Kotlin `String.toIntOrNull()` (no trimming) widened to `Int`.
    static func toIntOrNull(_ text: String) -> Int? {
        KotlinNumber.toIntOrNull(text).map { Int($0) }
    }
}

/// `BandSegmentDraft`: a band-plan segment (region, mode, range in kHz as text).
public struct BandSegmentDraft: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var region: String
    public var mode: String
    public var fromKhz: String
    public var toKhz: String

    public init(region: String, mode: String, fromKhz: Double, toKhz: Double) {
        self.region = region
        self.mode = mode
        self.fromKhz = ConfigurerRows.numStr(fromKhz)
        self.toKhz = ConfigurerRows.numStr(toKhz)
    }

    public init(_ segment: BandPlanFile.Segment) {
        self.init(region: segment.region, mode: segment.mode, fromKhz: segment.fromKhz, toKhz: segment.toKhz)
    }

    /// `fromKhz.trim().toDoubleOrNull()` (Kotlin).
    public func fromVal() -> Double? {
        KotlinNumber.toDoubleOrNull(KotlinText.trim(fromKhz))
    }

    /// `toKhz.trim().toDoubleOrNull()` (Kotlin).
    public func toVal() -> Double? {
        KotlinNumber.toDoubleOrNull(KotlinText.trim(toKhz))
    }

    /// `toSegment()`: `nil` when either bound is not a number; region and mode as they are.
    public func toSegment() -> BandPlanFile.Segment? {
        guard let from = fromVal(), let to = toVal() else { return nil }
        return BandPlanFile.Segment(region: region, mode: mode, fromKhz: from, toKhz: to)
    }

    public static func == (lhs: BandSegmentDraft, rhs: BandSegmentDraft) -> Bool {
        lhs.region == rhs.region && lhs.mode == rhs.mode && lhs.fromKhz == rhs.fromKhz && lhs.toKhz == rhs.toKhz
    }
}

/// `DigiChannelDraft`: a digi-frequency channel (mode, from–to kHz as text).
public struct DigiChannelDraft: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var mode: String
    public var fromKhz: String
    public var toKhz: String

    public init(mode: String, fromKhz: Double, toKhz: Double) {
        self.mode = mode
        self.fromKhz = ConfigurerRows.numStr(fromKhz)
        self.toKhz = ConfigurerRows.numStr(toKhz)
    }

    public init(_ channel: DigiFreqFile.Channel) {
        self.init(mode: channel.mode, fromKhz: channel.fromKhz, toKhz: channel.toKhz)
    }

    /// `toChannel()`: `nil` when a bound is not a number or the mode is blank; the mode is trimmed.
    public func toChannel() -> DigiFreqFile.Channel? {
        guard let from = KotlinNumber.toDoubleOrNull(KotlinText.trim(fromKhz)),
              let to = KotlinNumber.toDoubleOrNull(KotlinText.trim(toKhz)) else { return nil }
        if KotlinText.isBlank(mode) { return nil }
        return DigiFreqFile.Channel(mode: KotlinText.trim(mode), fromKhz: from, toKhz: to)
    }

    public static func == (lhs: DigiChannelDraft, rhs: DigiChannelDraft) -> Bool {
        lhs.mode == rhs.mode && lhs.fromKhz == rhs.fromKhz && lhs.toKhz == rhs.toKhz
    }
}

/// `FunctionKeyDraft`: an F-key message (label and text).
public struct FunctionKeyDraft: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var label: String
    public var text: String

    public init(label: String, text: String) {
        self.label = label
        self.text = text
    }

    public init(_ message: FunctionKeyMessage) {
        self.init(label: message.label, text: message.text)
    }

    /// `toMessage()`: both fields trimmed (Kotlin).
    public func toMessage() -> FunctionKeyMessage {
        FunctionKeyMessage(label: KotlinText.trim(label), text: KotlinText.trim(text))
    }

    public static func == (lhs: FunctionKeyDraft, rhs: FunctionKeyDraft) -> Bool {
        lhs.label == rhs.label && lhs.text == rhs.text
    }
}

/// `TransverterDraft`: a transverter row (IF range and offset in kHz as text).
public struct TransverterDraft: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var name: String
    public var ifLow: String
    public var ifHigh: String
    public var offset: String
    public var enabled: Bool

    public init(_ entry: TransverterEntry) {
        name = entry.name
        ifLow = String(entry.ifLowKHz)
        ifHigh = String(entry.ifHighKHz)
        offset = String(entry.offsetKHz)
        enabled = entry.enabled
    }

    /// `toEntry()`: Kotlin `toLongOrNull` without trimming; `nil` for a non-number or `ifHigh <= ifLow`; the name
    /// is trimmed.
    public func toEntry() -> TransverterEntry? {
        guard let lo = ConfigurerRows.toLongOrNull(ifLow),
              let hi = ConfigurerRows.toLongOrNull(ifHigh),
              let off = ConfigurerRows.toLongOrNull(offset) else { return nil }
        if hi <= lo { return nil }
        return TransverterEntry(
            name: KotlinText.trim(name), ifLowKHz: Int(lo), ifHighKHz: Int(hi), offsetKHz: Int(off), enabled: enabled)
    }

    public static func == (lhs: TransverterDraft, rhs: TransverterDraft) -> Bool {
        lhs.name == rhs.name && lhs.ifLow == rhs.ifLow && lhs.ifHigh == rhs.ifHigh
            && lhs.offset == rhs.offset && lhs.enabled == rhs.enabled
    }
}

/// `AntennaDraft` (`AntennasTab.kt:81-88`): an antenna row.
public struct AntennaDraft: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var code: String
    public var name: String
    public var bands: String
    public var sector: String

    public init(_ entry: AntennaEntry) {
        code = String(entry.code)
        name = entry.name
        bands = entry.bands
        sector = entry.sector
    }

    /// `toEntry()`: code `toIntOrNull() ?: 0` (no trimming) clamped to 0…15, texts trimmed.
    public func toEntry() -> AntennaEntry {
        let raw: Int = ConfigurerRows.toIntOrNull(code) ?? 0
        let clamped: Int = min(max(raw, 0), 15)
        return AntennaEntry(
            code: clamped, name: KotlinText.trim(name), bands: KotlinText.trim(bands), sector: KotlinText.trim(sector))
    }

    public static func == (lhs: AntennaDraft, rhs: AntennaDraft) -> Bool {
        lhs.code == rhs.code && lhs.name == rhs.name && lhs.bands == rhs.bands && lhs.sector == rhs.sector
    }
}

/// `DxFavoriteDraft` (`ConfigurerDraft.kt:536-544`): a favorite DX cluster row.
public struct DxFavoriteDraft: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var name: String
    public var host: String
    public var port: String
    public var login: String
    public var password: String
    public var isParallel: Bool

    public init(_ favorite: DxClusterFavorite) {
        name = favorite.name
        host = favorite.host
        port = String(favorite.port)
        login = favorite.login
        password = favorite.password
        isParallel = favorite.parallel
    }

    /// The favorite written by `applyTo` (`ConfigurerDraft.kt:451-459`): name and host trimmed, port
    /// `toIntOrNull() ?: DEFAULT_PORT` without trimming, login and password as they are.
    public func toFavorite() -> DxClusterFavorite {
        let portValue: Int = ConfigurerRows.toIntOrNull(port) ?? DxClusterFavorite.defaultPort
        var favorite = DxClusterFavorite(
            name: KotlinText.trim(name), host: KotlinText.trim(host), port: portValue, login: login,
            password: password)
        favorite.parallel = isParallel
        return favorite
    }

    public static func == (lhs: DxFavoriteDraft, rhs: DxFavoriteDraft) -> Bool {
        lhs.name == rhs.name && lhs.host == rhs.host && lhs.port == rhs.port && lhs.login == rhs.login
            && lhs.password == rhs.password && lhs.isParallel == rhs.isParallel
    }
}
