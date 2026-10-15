import Foundation

/// Winkeyer paddle keying mode (mode register bits 5–4, N1MM Winkey tab "Keying Mode").
public enum WinkeyerKeyMode: String, Codable, CaseIterable, Equatable, Sendable {
    case iambicB = "IAMBIC_B"
    case iambicA = "IAMBIC_A"
    case ultimatic = "ULTIMATIC"
    /// Semi-automatic (bug) mode.
    case bug = "BUG"

    /// The two mode register bits (5–4).
    var modeBits: UInt8 {
        switch self {
        case .iambicB: return 0x00
        case .iambicA: return 0x10
        case .ultimatic: return 0x20
        case .bug: return 0x30
        }
    }

    public var label: String {
        switch self {
        case .iambicB: return "Iambic B"
        case .iambicA: return "Iambic A"
        case .ultimatic: return "Ultimatic"
        case .bug: return "Semi-auto (bug)"
        }
    }
}

/// What the Winkeyer speed pot does (N1MM "Winkey Speed Pot Control").
public enum WinkeyerPotMode: String, Codable, CaseIterable, Equatable, Sendable {
    /// The pot is ignored while the logger runs (the keyer sends at the logger's speed).
    case ignore = "IGNORE"
    /// Turning the pot changes the logger's CW speed.
    case follow = "FOLLOW"
}

/// CW keying options beyond the keying method: weight and word spacing (all keyers that form the elements
/// themselves), and the K1EL Winkeyer setup sent after host open. Stored flat inside `CwKeyerConfig` (the JSON keys
/// are the property names), every value normalised to its valid range. Swift-only keys.
public struct CwKeyingOptions: Codable, Equatable, Sendable {

    /// A modem line of the DTR/RTS keying port.
    public enum SerialLine: String, Codable, CaseIterable, Equatable, Sendable {
        case none = "NONE"
        case dtr = "DTR"
        case rts = "RTS"
    }

    public static let serialPttRange: ClosedRange<Int> = 0...2_000
    public static let monitorPitchRange: ClosedRange<Int> = 300...1_200
    public static let monitorVolumeRange: ClosedRange<Int> = 0...100

    public static let weightRange: ClosedRange<Int> = 30...70
    /// Winkeyer PTT lead and tail time: 10 ms units, at most 255 of them.
    public static let pttTimeRange: ClosedRange<Int> = 0...2_550
    /// First character extension and keying compensation in ms (one byte).
    public static let msByteRange: ClosedRange<Int> = 0...250
    public static let hangTimeRange: ClosedRange<Int> = 0...3
    public static let potMinRange: ClosedRange<Int> = 5...60
    public static let potSpanRange: ClosedRange<Int> = 1...31
    /// Winkeyer 2 sidetone frequencies (4000 / n Hz, n = 1…10), lowest first.
    public static let winkeyerSidetones: [Int] = (1...10).reversed().map { (4_000 + $0 / 2) / $0 }

    /// CW weight in percent (50 = standard 1:1 dit/space ratio).
    public var weight: Int = 50
    /// Contest word spacing: 6 dit spaces between words instead of 7.
    public var contestSpacing: Bool = false

    /// The Winkeyer setup below is sent when the keyer opens; off = the keyer keeps its own (power-on) settings.
    public var wkSendSettings: Bool = false
    public var wkKeyMode: WinkeyerKeyMode = .iambicB
    public var wkAutospace: Bool = false
    public var wkSwapPaddles: Bool = false
    public var wkSidetone: Bool = true
    public var wkSidetonePaddleOnly: Bool = false
    /// One of `winkeyerSidetones`.
    public var wkSidetoneHz: Int = 571
    public var wkPotMode: WinkeyerPotMode = .ignore
    /// The pot's lowest speed (WPM) and its span above it.
    public var wkPotMinWpm: Int = 10
    public var wkPotRangeWpm: Int = 25
    /// Winkeyer PTT enable (pin config bit 0) with its lead and tail time in ms (10 ms steps).
    public var wkPtt: Bool = true
    public var wkLeadMs: Int = 0
    /// 0 = the hang time decides when PTT drops.
    public var wkTailMs: Int = 0
    /// Hang time: 0 = 1, 1 = 1.33, 2 = 1.67, 3 = 2 word spaces (pin config bits 5–4).
    public var wkHangTime: Int = 0
    public var wkFirstExtensionMs: Int = 0
    public var wkKeyCompensationMs: Int = 0

    /// CW keyed on a serial port's DTR or RTS line (N1MM CW/Other port); overrides `CwKeyerConfig.method`.
    public var serialKeying: Bool = false
    public var serialPort: String = ""
    public var serialKeyLine: SerialLine = .dtr
    /// The PTT line (`.none` = no PTT line; never the key line).
    public var serialPttLine: SerialLine = .none
    /// N1MM "PTT Delay": PTT on → first element.
    public var serialPttDelayMs: Int = 50
    /// Last element → PTT off.
    public var serialPttTailMs: Int = 30
    /// N1MM "PTT via Radio Command" for CW: the rig's CAT PTT around DTR/RTS keying.
    public var cwPttViaCat: Bool = false
    /// The sound-card CW monitor (sidetone of the sent CW): off by default.
    public var monitorEnabled: Bool = false
    /// Output device name; empty = system default.
    public var monitorDevice: String = ""
    public var monitorPitchHz: Int = 600
    public var monitorVolume: Int = 30

    enum CodingKeys: String, CodingKey, CaseIterable {
        case weight, contestSpacing
        case wkSendSettings, wkKeyMode, wkAutospace, wkSwapPaddles, wkSidetone, wkSidetonePaddleOnly, wkSidetoneHz
        case wkPotMode, wkPotMinWpm, wkPotRangeWpm, wkPtt, wkLeadMs, wkTailMs, wkHangTime, wkFirstExtensionMs
        case wkKeyCompensationMs
        case serialKeying, serialPort, serialKeyLine, serialPttLine, serialPttDelayMs, serialPttTailMs, cwPttViaCat
        case monitorEnabled, monitorDevice, monitorPitchHz, monitorVolume
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CwKeyingOptions()
        weight = c.value(.weight, default: d.weight)
        contestSpacing = c.value(.contestSpacing, default: d.contestSpacing)
        wkSendSettings = c.value(.wkSendSettings, default: d.wkSendSettings)
        wkKeyMode = c.value(.wkKeyMode, default: d.wkKeyMode)
        wkAutospace = c.value(.wkAutospace, default: d.wkAutospace)
        wkSwapPaddles = c.value(.wkSwapPaddles, default: d.wkSwapPaddles)
        wkSidetone = c.value(.wkSidetone, default: d.wkSidetone)
        wkSidetonePaddleOnly = c.value(.wkSidetonePaddleOnly, default: d.wkSidetonePaddleOnly)
        wkSidetoneHz = c.value(.wkSidetoneHz, default: d.wkSidetoneHz)
        wkPotMode = c.value(.wkPotMode, default: d.wkPotMode)
        wkPotMinWpm = c.value(.wkPotMinWpm, default: d.wkPotMinWpm)
        wkPotRangeWpm = c.value(.wkPotRangeWpm, default: d.wkPotRangeWpm)
        wkPtt = c.value(.wkPtt, default: d.wkPtt)
        wkLeadMs = c.value(.wkLeadMs, default: d.wkLeadMs)
        wkTailMs = c.value(.wkTailMs, default: d.wkTailMs)
        wkHangTime = c.value(.wkHangTime, default: d.wkHangTime)
        wkFirstExtensionMs = c.value(.wkFirstExtensionMs, default: d.wkFirstExtensionMs)
        wkKeyCompensationMs = c.value(.wkKeyCompensationMs, default: d.wkKeyCompensationMs)
        serialKeying = c.value(.serialKeying, default: d.serialKeying)
        serialPort = c.value(.serialPort, default: d.serialPort)
        serialKeyLine = c.value(.serialKeyLine, default: d.serialKeyLine)
        serialPttLine = c.value(.serialPttLine, default: d.serialPttLine)
        serialPttDelayMs = c.value(.serialPttDelayMs, default: d.serialPttDelayMs)
        serialPttTailMs = c.value(.serialPttTailMs, default: d.serialPttTailMs)
        cwPttViaCat = c.value(.cwPttViaCat, default: d.cwPttViaCat)
        monitorEnabled = c.value(.monitorEnabled, default: d.monitorEnabled)
        monitorDevice = c.value(.monitorDevice, default: d.monitorDevice)
        monitorPitchHz = c.value(.monitorPitchHz, default: d.monitorPitchHz)
        monitorVolume = c.value(.monitorVolume, default: d.monitorVolume)
        self = normalized()
    }

    /// Every value inside its range; the sidetone snapped to the nearest Winkeyer frequency, the PTT times to 10 ms.
    public func normalized() -> CwKeyingOptions {
        var o = self
        o.weight = Self.clamp(weight, Self.weightRange)
        o.wkSidetoneHz = Self.nearestSidetone(wkSidetoneHz)
        o.wkPotMinWpm = Self.clamp(wkPotMinWpm, Self.potMinRange)
        o.wkPotRangeWpm = Self.clamp(wkPotRangeWpm, Self.potSpanRange)
        o.wkLeadMs = Self.clamp(wkLeadMs, Self.pttTimeRange) / 10 * 10
        o.wkTailMs = Self.clamp(wkTailMs, Self.pttTimeRange) / 10 * 10
        o.wkHangTime = Self.clamp(wkHangTime, Self.hangTimeRange)
        o.wkFirstExtensionMs = Self.clamp(wkFirstExtensionMs, Self.msByteRange)
        o.wkKeyCompensationMs = Self.clamp(wkKeyCompensationMs, Self.msByteRange)
        if o.serialKeyLine == .none {
            o.serialKeyLine = .dtr
        }
        if o.serialPttLine == o.serialKeyLine {
            o.serialPttLine = .none
        }
        o.serialPttDelayMs = Self.clamp(serialPttDelayMs, Self.serialPttRange)
        o.serialPttTailMs = Self.clamp(serialPttTailMs, Self.serialPttRange)
        o.monitorPitchHz = Self.clamp(monitorPitchHz, Self.monitorPitchRange)
        o.monitorVolume = Self.clamp(monitorVolume, Self.monitorVolumeRange)
        return o
    }

    static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// The Winkeyer 2 sidetone frequency closest to `hz`.
    public static func nearestSidetone(_ hz: Int) -> Int {
        winkeyerSidetones.min { abs($0 - hz) < abs($1 - hz) } ?? 571
    }
}

extension CwKeyingOptions {

    // K1EL WK2 host commands (the keyer stays in WK2 mode, which WK3 also accepts).
    static let sidetoneCommand: UInt8 = 0x01
    static let weightCommand: UInt8 = 0x03
    static let pttLeadTailCommand: UInt8 = 0x04
    static let potSetupCommand: UInt8 = 0x05
    static let getPotCommand: UInt8 = 0x07
    static let pinConfigCommand: UInt8 = 0x09
    static let modeCommand: UInt8 = 0x0E
    static let firstExtensionCommand: UInt8 = 0x10
    static let keyCompensationCommand: UInt8 = 0x11

    /// Mode register: paddle watchdog on, paddle and serial echo off, key mode, paddle swap, autospace, contest
    /// spacing.
    public var winkeyerModeRegister: UInt8 {
        var mode: UInt8 = wkKeyMode.modeBits
        if wkSwapPaddles { mode |= 0x08 }
        if wkAutospace { mode |= 0x02 }
        if contestSpacing { mode |= 0x01 }
        return mode
    }

    /// Pin config: hang time, KEY OUT 1 on, sidetone and PTT as chosen.
    public var winkeyerPinConfig: UInt8 {
        var pins: UInt8 = UInt8(Self.clamp(wkHangTime, Self.hangTimeRange)) << 4 | 0x04
        if wkSidetone { pins |= 0x02 }
        if wkPtt { pins |= 0x01 }
        return pins
    }

    /// Sidetone byte: bit 7 = paddle-only sidetone, bits 3–0 = 4000 / frequency.
    public var winkeyerSidetone: UInt8 {
        let hz: Int = Self.nearestSidetone(wkSidetoneHz)
        let divider: Int = Self.clamp(Int((4_000.0 / Double(hz)).rounded()), 1...10)
        return UInt8(divider) | (wkSidetonePaddleOnly ? 0x80 : 0)
    }

    /// The setup bytes sent after host open and after every change (empty when `wkSendSettings` is off).
    public func winkeyerCommands() -> [UInt8] {
        guard wkSendSettings else { return [] }
        let o: CwKeyingOptions = normalized()
        var bytes: [UInt8] = [Self.modeCommand, o.winkeyerModeRegister]
        bytes += [Self.pinConfigCommand, o.winkeyerPinConfig]
        bytes += [Self.sidetoneCommand, o.winkeyerSidetone]
        bytes += [Self.weightCommand, UInt8(o.weight)]
        bytes += [Self.pttLeadTailCommand, UInt8(o.wkLeadMs / 10), UInt8(o.wkTailMs / 10)]
        bytes += [Self.potSetupCommand, UInt8(o.wkPotMinWpm), UInt8(o.wkPotRangeWpm), 0]
        bytes += [Self.firstExtensionCommand, UInt8(o.wkFirstExtensionMs)]
        bytes += [Self.keyCompensationCommand, UInt8(o.wkKeyCompensationMs)]
        if o.wkPotMode == .follow {
            bytes.append(Self.getPotCommand)
        }
        return bytes
    }
}

extension CwKeyingOptions {

    /// DTR/RTS keying keys a PTT (a PTT line or the rig's CAT PTT), so the PTT delay goes before the first element.
    public var serialHasPtt: Bool {
        serialPttLine != .none || cwPttViaCat
    }

    /// The identity of the open DTR/RTS keyer: another port, line or PTT source reopens it.
    public var serialSignature: String {
        let o: CwKeyingOptions = normalized()
        return ["SERIAL", o.serialPort, o.serialKeyLine.rawValue, o.serialPttLine.rawValue,
                o.cwPttViaCat ? "CAT" : "-"].joined(separator: "|")
    }
}
