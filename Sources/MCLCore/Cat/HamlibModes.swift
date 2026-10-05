import Foundation

/// Conversion between hamlib modes (USB, LSB, CW, PKTUSB…) and our `Mode` — Java `cat/HamlibModes`.
///
/// Java keeps the Digital Modes / Mode Control settings in a **global `static volatile`** state
/// (`HamlibModes.configure`) and reads it on every `read()`/`setMode`. Swift carries it as a value:
/// the client receives a `HamlibModeProvider` that is called on every conversion —
/// a change in Settings thus applies immediately even to a running connection, as in Java, but without a global
/// variable.
public struct HamlibModeMapping: Equatable, Sendable {

    /// How the rig's data mode is written (PKTUSB/PKTLSB) — always a data mode.
    public let dataMode: Mode
    /// RTTY via AFSK (rig data mode, audio from the computer) instead of FSK (rig RTTY mode).
    public let rttyAfsk: Bool

    /// Java default state: `DIGITAL`, FSK.
    public static let `default` = HamlibModeMapping(dataMode: .digital, rttyAfsk: false)

    /// Java `configure(dataModeForPacket, rttyViaAfsk)`: `nil` or a non-data mode → `DIGITAL`.
    public init(dataMode: Mode?, rttyAfsk: Bool) {
        if let dataMode, dataMode.isDigital {
            self.dataMode = dataMode
        } else {
            self.dataMode = .digital
        }
        self.rttyAfsk = rttyAfsk
    }

    /// Hamlib mode → our `Mode` (or `nil` if it cannot be mapped).
    ///
    /// `trim()` is Java's (only characters ≤ U+0020, NBSP stays). `toUpperCase()` of the default locale (en_US/cs_CZ;
    /// in `tr_TR` unchanged, no mode has an `i`) — Swift `uppercased()` gives the same for all inputs whose
    /// result is one of the ASCII modes below (`ſ` → `S`, `ı` → `I`; measured `HM.extra`).
    public func toMode(_ hamlib: String?) -> Mode? {
        guard let hamlib else { return nil }
        switch JavaText.trim(hamlib).uppercased() {
        case "USB", "LSB", "DSB": return .ssb
        case "CW", "CWR": return .cw
        case "RTTY", "RTTYR": return .rtty
        case "AM", "AMS", "SAM", "SAL", "SAH": return .am
        case "FM", "WFM", "PKTFM": return .fm
        case "PKTUSB", "PKTLSB": return dataMode
        default: return nil
        }
    }

    /// Our `Mode` → hamlib mode for the `M` command. For SSB it picks the sideband by frequency (LSB below
    /// 10 MHz — so also 0 and negative —, otherwise USB); `nil` → `USB`.
    public func toHamlib(_ mode: Mode?, freqHz: Int64) -> String {
        guard let mode else { return "USB" }
        switch mode {
        case .cw: return "CW"
        case .ssb: return freqHz < 10_000_000 ? "LSB" : "USB"
        case .fm: return "FM"
        case .am: return "AM"
        // AFSK: RTTY as audio in data mode (LSB side like FSK), otherwise the rig's FSK mode.
        case .rtty: return rttyAfsk ? "PKTLSB" : "RTTY"
        case .psk, .ft8, .ft4, .jt65, .digital: return "PKTUSB"
        }
    }
}

/// Source of the current mode-mapping settings — read on every conversion (replacement for Java's global
/// `static volatile` state).
public typealias HamlibModeProvider = @Sendable () -> HamlibModeMapping

/// Mode Control (N1MM Configurer → Mode Control): which mode is written to the log — by the rig, by the
/// bandplan, or always a fixed one. Java `cat/ModeControl`.
public enum ModeControl {

    /// Mode rule written to the log (`config.json` `modeRule`).
    public enum Rule: String, CaseIterable, Sendable {
        case radio = "RADIO"
        case bandplan = "BANDPLAN"
        case always = "ALWAYS"
    }

    /// - Parameters:
    ///   - rule: the rule (`nil` = `RADIO`)
    ///   - radio: mode from the rig (`nil` = unknown)
    ///   - bandplan: bandplan category at the frequency (`nil` = outside the bandplan)
    ///   - always: fixed mode for `ALWAYS` (`nil` = by the rig)
    public static func loggedMode(_ rule: Rule?, radio: Mode?, bandplan: BandPlan.ModeCategory?, always: Mode?) -> Mode? {
        switch rule ?? .radio {
        case .always:
            return always ?? radio
        case .bandplan:
            guard let bandplan else { return radio }
            switch bandplan {
            case .cw: return .cw
            case .phone: return .ssb
            // In the digi segment keep the specific digi mode from the rig (FT8…), otherwise generic DIGITAL.
            case .digi:
                if let radio, radio.isDigital { return radio }
                return .digital
            }
        case .radio:
            return radio
        }
    }
}
