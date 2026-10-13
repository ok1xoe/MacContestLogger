/// Where RTTY is transmitted (N1MM „Default RTTY Interface"; PSK and the other sound-card modes always go through
/// fldigi): fldigi (AFSK or its own FSK), an external TU/TNC on a serial port, K0SM's TinyFSK (an Arduino FSK keyer) or a
/// WinKeyer 3.1 (its FSK RTTY mode). The RX text comes from fldigi except with a TNC, which also decodes.
public enum RttyInterface: String, CaseIterable, Sendable {
    case fldigi = "FLDIGI"
    case tnc = "TNC"
    case tinyFsk = "TINYFSK"
    case winkeyer = "WINKEYER"

    public static func from(_ raw: String) -> RttyInterface {
        RttyInterface(rawValue: raw) ?? .fldigi
    }

    /// The TNC decodes too: the Digital Interface reads its serial port instead of fldigi.
    public var decodes: Bool {
        self == .tnc
    }
}

/// The external TU/TNC types with N1MM's sample control macros (the user can change them; N1MM: the commands are
/// not hard-coded because every TNC differs). The HAL DXP-38 has no preset here — enter its commands from its manual.
public enum TncType: String, CaseIterable, Sendable {
    case pk232 = "PK232"
    case kam = "KAM"
    case dxp38 = "DXP38"
    case other = "OTHER"

    public static func from(_ raw: String) -> TncType {
        TncType(rawValue: raw) ?? .other
    }

    /// The default TX, RX and abort commands (N1MM's examples for the PK-232 and the KAM).
    public var defaultCommands: (tx: String, rx: String, esc: String) {
        switch self {
        case .pk232: ("X{ENTER}", "{CTRL-D}", "{CTRL-C}R{ENTER}TC{ENTER}")
        case .kam: ("{CTRL-C}T", "{CTRL-C}E", "{CTRL-C}R RTTY {ENTER}")
        case .dxp38, .other: ("", "", "")
        }
    }
}

/// The control macros of TNC commands: `{CTRL-A}`…`{CTRL-Z}`, `{ENTER}` (CR), `{ENTERLF}` (CR LF), `{ESC}`; the rest
/// is sent as ASCII (non-ASCII as `?`).
public enum TncCommands {

    public static func bytes(_ template: String) -> [UInt8] {
        var out: [UInt8] = []
        let units: [UInt16] = Array(template.utf16)
        var index = 0
        while index < units.count {
            if units[index] == 0x7B, let end = units[index...].firstIndex(of: 0x7D) {
                let macro: String = String(decoding: units[(index + 1)..<end], as: UTF16.self).uppercased()
                if let code = control(macro) {
                    out += code
                    index = end + 1
                    continue
                }
            }
            let unit: UInt16 = units[index]
            out.append(unit < 0x80 ? UInt8(unit) : 0x3F)
            index += 1
        }
        return out
    }

    private static func control(_ macro: String) -> [UInt8]? {
        switch macro {
        case "ENTER": return [0x0D]
        case "ENTERLF": return [0x0D, 0x0A]
        case "ESC": return [0x1B]
        default:
            guard macro.hasPrefix("CTRL-"), macro.count == 6, let letter = macro.last?.asciiValue,
                  letter >= 0x41, letter <= 0x5A else { return nil }
            return [letter - 0x40]
        }
    }
}

/// The FSK keyers' text: upper case, the characters Baudot can send (letters, figures, `- ? : ( ) . , ' / = + "`,
/// space), line breaks kept as `\n`; the keyers' control characters `[ ] \ ~ { }` never get through.
public enum BaudotText {

    private static let figures: Set<Character> = ["-", "?", ":", "(", ")", ".", ",", "'", "/", "=", "+", "\"", "!",
                                                  "&", "#", "$", ";"]

    public static func filter(_ text: String) -> String {
        String(text.uppercased().compactMap { character -> Character? in
            if character == "\n" || character == " " { return character }
            if character.isASCII && (character.isLetter || character.isNumber) { return character }
            return figures.contains(character) ? character : nil
        })
    }

    /// The approximate time to send `text` at `baud` (7.5 bits a character with 1.5 stop bits, 8 with 2) plus a margin
    /// for the PTT tail — the FSK keyers do not tell when they finish (N1MM: neither does a TNC).
    public static func durationMs(_ text: String, baud: Double = 45.45) -> Int {
        let characters: Int = text.count + 2
        return Int((Double(characters) * 7.5 * 1000.0 / baud).rounded()) + 300
    }
}

/// K0SM's TinyFSK (Arduino, 9600 8N1): text in `[ … ]` is sent as FSK RTTY — `[` keys the transmitter, `]` returns
/// to receive when the buffer is empty, `\` stops at once and clears the buffer.
public enum TinyFsk {
    public static let txOn: UInt8 = 0x5B
    public static let txEnd: UInt8 = 0x5D
    public static let abort: UInt8 = 0x5C

    public static func frame(_ text: String, returnToRx: Bool = true) -> [UInt8] {
        let body: [UInt8] = Array(BaudotText.filter(text).replacingOccurrences(of: "\n", with: "\r\n").utf8)
        return [txOn] + body + (returnToRx ? [txEnd] : [])
    }
}

/// WinKeyer 3.1's FSK RTTY host mode (K1EL WKUSB API extension, admin command 0x13): the mode bytes, then text in
/// `[ … ]`; `}` is a CR LF, `\` aborts. Mark = key up.
public enum WinkeyerRtty {

    /// The settings of the mode command.
    public struct Settings: Equatable, Sendable {
        /// 45.45, 50, 75 or 100 baud.
        public var baud: Double = 45.45
        /// Mark and space swapped.
        public var reverse: Bool = false
        /// FSKMAP: FSK on the KEY output (PTT keys the transmitter); default FSK on PTT, KEY keys.
        public var fskOnKey: Bool = false
        /// Diddle between characters.
        public var diddle: Bool = false
        /// USOS: an extra FIGS after a space.
        public var usos: Bool = false

        public init(baud: Double = 45.45, reverse: Bool = false, fskOnKey: Bool = false, diddle: Bool = false,
                    usos: Bool = false) {
            self.baud = baud
            self.reverse = reverse
            self.fskOnKey = fskOnKey
            self.diddle = diddle
            self.usos = usos
        }
    }

    /// `00 13 P1 P2` with RTTY on (`nil` = off: `00 13 00 00`).
    public static func mode(_ settings: Settings?) -> [UInt8] {
        guard let settings else { return [0x00, 0x13, 0x00, 0x00] }
        var p1: UInt8 = 0x80
        if settings.diddle { p1 |= 0x40 }
        if settings.fskOnKey { p1 |= 0x20 }
        if settings.reverse { p1 |= 0x04 }
        switch settings.baud {
        case 100...: p1 |= 0x03
        case 75..<100: p1 |= 0x02
        case 50..<75: p1 |= 0x01
        default: break
        }
        let p2: UInt8 = settings.usos ? 0x01 : 0x00
        return [0x00, 0x13, p1, p2]
    }

    public static func frame(_ text: String) -> [UInt8] {
        let body: [UInt8] = Array(BaudotText.filter(text).replacingOccurrences(of: "\n", with: "}").utf8)
        return [0x5B] + body + [0x5D]
    }

    public static let abort: [UInt8] = [0x5C]
}

/// A CW keyer that can also send WinKeyer 3.1 FSK RTTY over the same port.
public protocol RttyKeyer: CwKeyer {
    /// Sends `text` as RTTY (the mode command first).
    func sendRtty(_ text: String, settings: WinkeyerRtty.Settings) throws
    /// Stops the RTTY transmission at once.
    func abortRtty() throws
    /// Raw bytes of the RTTY mode (the mode command, `[`, typed text, `]`, `\`) for a held transmission.
    func sendRawRtty(_ bytes: [UInt8]) throws
}
