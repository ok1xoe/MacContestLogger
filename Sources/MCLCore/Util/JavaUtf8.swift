/// Java `new String(bytes, StandardCharsets.UTF_8)` (JDK 21, `String.decodeUTF8_UTF16` with replacement):
/// invalid sequences → `U+FFFD`.
///
/// Swift's `String(decoding:as: UTF8.self)` replaces by **maximal subparts** (Unicode 3.9), Java almost
/// the same — they differ on encoded surrogates: `ED A0 80` is **one** `U+FFFD` in Java (the structure of the three-byte
/// sequence is fine, only the code point is rejected), Swift gives three; `ED A0 41` → Java `U+FFFD A` (two bytes
/// as one malformed sequence), Swift `U+FFFD U+FFFD A`; `ED A0` at the end → Java one `U+FFFD`. Hence
/// a 1:1 port of the Java decoder (measured, gate `wsjtx.DEC`).
enum JavaUtf8 {

    /// Strict UTF-8 (Java's decoder `Files.readAllLines` reports every malformed sequence — overlong
    /// encodings, encoded surrogates, above U+10FFFF, truncated end); BOM stays. `nil` = malformed.
    /// Called by `CallHistory.load` (then again as Latin-1) and `MacroScript.load`.
    static func strict(_ bytes: [UInt8]) -> String? {
        var iterator = bytes.makeIterator()
        var parser = Unicode.UTF8.ForwardParser()
        while true {
            switch parser.parseScalar(from: &iterator) {
            case .valid:
                continue
            case .emptyInput:
                return String(decoding: bytes, as: UTF8.self)
            case .error:
                return nil
            }
        }
    }

    static func decode<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
        let src: [Int] = bytes.map { Int(Int8(bitPattern: $0)) }
        let repl: UInt16 = 0xFFFD
        var out: [UInt16] = []
        out.reserveCapacity(src.count)
        let sl: Int = src.count
        var sp = 0
        while sp < sl {
            let b1: Int = src[sp]
            sp += 1
            if b1 >= 0 {
                out.append(UInt16(b1))
            } else if (b1 >> 5) == -2 && (b1 & 0x1E) != 0 {
                if sp < sl {
                    let b2: Int = src[sp]
                    sp += 1
                    if isNotContinuation(b2) {
                        out.append(repl)
                        sp -= 1
                    } else {
                        out.append(UInt16(truncatingIfNeeded: (b1 << 6) ^ b2 ^ ((-64 << 6) ^ -128)))
                    }
                    continue
                }
                out.append(repl)
                break
            } else if (b1 >> 4) == -2 {
                if sp + 1 < sl {
                    let b2: Int = src[sp]
                    let b3: Int = src[sp + 1]
                    sp += 2
                    if isMalformed3(b1, b2, b3) {
                        out.append(repl)
                        sp -= 3
                        sp += malformed3(b1, b2)
                    } else {
                        let c = UInt16(truncatingIfNeeded: decode3(b1, b2, b3))
                        out.append(c >= 0xD800 && c <= 0xDFFF ? repl : c)
                    }
                    continue
                }
                if sp < sl && isMalformed3and2(b1, src[sp]) {
                    out.append(repl)
                    continue
                }
                out.append(repl)
                break
            } else if (b1 >> 3) == -2 {
                if sp + 2 < sl {
                    let b2: Int = src[sp]
                    let b3: Int = src[sp + 1]
                    let b4: Int = src[sp + 2]
                    sp += 3
                    let uc: Int = decode4(b1, b2, b3, b4)
                    if isMalformed4(b2, b3, b4) || !(0x10000...0x10FFFF).contains(uc) {
                        out.append(repl)
                        sp -= 4
                        sp += malformed4(b1 & 0xFF, b2 & 0xFF, src[sp + 2])
                    } else {
                        let v: Int = uc - 0x10000
                        out.append(UInt16(0xD800 + (v >> 10)))
                        out.append(UInt16(0xDC00 + (v & 0x3FF)))
                    }
                    continue
                }
                let lead: Int = b1 & 0xFF
                if lead > 0xF4 || (sp < sl && isMalformed4and2(lead, src[sp] & 0xFF)) {
                    out.append(repl)
                    continue
                }
                sp += 1
                out.append(repl)
                if sp < sl && isNotContinuation(src[sp]) {
                    continue
                }
                break
            } else {
                out.append(repl)
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    private static func isNotContinuation(_ b: Int) -> Bool {
        (b & 0xC0) != 0x80
    }

    /// `b1` is a Java (signed) byte: `(byte) 0xE0` = −32.
    private static func isMalformed3(_ b1: Int, _ b2: Int, _ b3: Int) -> Bool {
        (b1 == -32 && (b2 & 0xE0) == 0x80) || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80
    }

    private static func isMalformed3and2(_ b1: Int, _ b2: Int) -> Bool {
        (b1 == -32 && (b2 & 0xE0) == 0x80) || (b2 & 0xC0) != 0x80
    }

    private static func isMalformed4(_ b2: Int, _ b3: Int, _ b4: Int) -> Bool {
        (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 || (b4 & 0xC0) != 0x80
    }

    /// Unsigned bytes (`& 0xff`).
    private static func isMalformed4and2(_ b1: Int, _ b2: Int) -> Bool {
        if isNotContinuation(b2) { return true }
        let overlong: Bool = b1 == 0xF0 && (b2 < 0x90 || b2 > 0xBF)
        let tooHigh: Bool = b1 == 0xF4 && (b2 & 0xF0) != 0x80
        return overlong || tooHigh
    }

    private static func malformed3(_ b1: Int, _ b2: Int) -> Int {
        (b1 == -32 && (b2 & 0xE0) == 0x80) || isNotContinuation(b2) ? 1 : 2
    }

    /// `b1`, `b2` unsigned, `b3` signed (Java `malformed4`).
    private static func malformed4(_ b1: Int, _ b2: Int, _ b3: Int) -> Int {
        if b1 > 0xF4 || isMalformed4and2(b1, b2) {
            return 1
        }
        return isNotContinuation(b3) ? 2 : 3
    }

    /// `((byte) 0xE0 << 12) ^ ((byte) 0x80 << 6) ^ (byte) 0x80` as `Int`.
    private static let mask3: Int = -123_008

    private static func decode3(_ b1: Int, _ b2: Int, _ b3: Int) -> Int {
        return (b1 << 12) ^ (b2 << 6) ^ (b3 ^ mask3)
    }

    /// `((byte) 0xF0 << 18) ^ ((byte) 0x80 << 12) ^ ((byte) 0x80 << 6) ^ (byte) 0x80` as `Int`
    /// (sign-extended; after truncation to `Int32` = Java `int`).
    private static let mask4: Int = 3_678_080

    private static func decode4(_ b1: Int, _ b2: Int, _ b3: Int, _ b4: Int) -> Int {
        let high: Int = (b1 << 18) ^ (b2 << 12)
        let raw: Int = high ^ (b3 << 6) ^ (b4 ^ mask4)
        return Int(Int32(truncatingIfNeeded: raw))
    }
}
