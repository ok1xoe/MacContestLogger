import Foundation

/// Duration of transmitting a CW message according to the real Morse alphabet (PARIS: dit = 1200/WPM ms, dah 3,
/// gap within a character 1, between characters 3, between words 7 dits). The UI uses it to know when a message finishes — the CAT keyer
/// does not report transmission state. Mirrors Java `keyer.CwTiming`.
public enum CwTiming {

    private static let morse: [UInt16: String] = [
        0x41: ".-", 0x42: "-...", 0x43: "-.-.", 0x44: "-..", 0x45: ".", 0x46: "..-.", 0x47: "--.",
        0x48: "....", 0x49: "..", 0x4A: ".---", 0x4B: "-.-", 0x4C: ".-..", 0x4D: "--", 0x4E: "-.",
        0x4F: "---", 0x50: ".--.", 0x51: "--.-", 0x52: ".-.", 0x53: "...", 0x54: "-", 0x55: "..-",
        0x56: "...-", 0x57: ".--", 0x58: "-..-", 0x59: "-.--", 0x5A: "--..",
        0x30: "-----", 0x31: ".----", 0x32: "..---", 0x33: "...--", 0x34: "....-",
        0x35: ".....", 0x36: "-....", 0x37: "--...", 0x38: "---..", 0x39: "----.",
        0x2F: "-..-.", 0x3F: "..--..", 0x2E: ".-.-.-", 0x2C: "--..--", 0x2D: "-....-",
    ]

    /// Character length in dits including gaps inside the character (without the gap after it); Java
    /// `Character.toUpperCase(char)` — `ı` (U+0131) and `ſ` (U+017F) have the length of `I` and `S`.
    static func dits(_ unit: UInt16) -> Int {
        guard let code = morse[JavaChar.toUpperCase(unit)] else {
            return 0
        }
        var d = 0
        for element in code.utf8 {
            d += element == UInt8(ascii: ".") ? 1 : 3
        }
        return d + code.utf8.count - 1
    }

    /// Estimate of the message length in ms; speed changes inside the message are counted. The speed is a Java `int`
    /// (addition with overflow), dit `1200.0 / max(5, speed)`, the total `Math.round`.
    public static func estimateMillis(_ message: CwMessage, wpm: Int) -> Int64 {
        var total = 0.0
        var speed = Int32(truncatingIfNeeded: wpm)
        var first = true
        for part in message.parts {
            let text: String
            var prosign = false
            switch part {
            case .speed(let delta):
                speed = speed &+ Int32(truncatingIfNeeded: delta)
                continue
            case .text(let t):
                text = t
            case .prosign(let letters):
                text = letters
                prosign = true
            }
            let dit = 1200.0 / Double(max(5, speed))
            for (i, c) in text.utf16.enumerated() {
                if c == 0x20 {
                    total += 4 * dit // 3 already went to the previous character → 7 in total
                    continue
                }
                if !first {
                    // prosign = characters without a gap between them (only the gap inside a character)
                    total += Double(prosign && i > 0 ? 1 : 3) * dit
                }
                total += Double(dits(c)) * dit
                first = false
            }
        }
        return JavaMath.round(total)
    }
}
