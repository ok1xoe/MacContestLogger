import Foundation

/// Strict UTF-8 decoding with explicit BOM handling, independent of the Foundation
/// version (`String(data:encoding:.utf8)` either strips or keeps a leading BOM
/// depending on the system version).
enum Utf8Text {

    /// Decodes bytes as UTF-8 and removes **exactly one** leading BOM (`EF BB BF`)
    /// — like `UnicodeReader` in SnakeYAML. Another BOM stays as a character.
    /// Invalid UTF-8 → `nil`.
    static func decodeStrippingBom(_ data: Data) -> String? {
        let body = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        // `String(data:encoding:)` serves here only for validation (nil = invalid UTF-8);
        // the result is composed via `String(decoding:)`, which never strips a BOM,
        // so the Foundation version does not matter.
        guard String(data: body, encoding: .utf8) != nil else { return nil }
        return String(decoding: body, as: UTF8.self)
    }

    /// Reads a file like `decodeStrippingBom`; invalid UTF-8 → `CocoaError(.fileReadInapplicableStringEncoding)`.
    static func readFile(_ url: URL) throws -> String {
        guard let text = decodeStrippingBom(try Data(contentsOf: url)) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    /// Invalid UTF-8 on reading like `Files.readString` — Java's
    /// `MalformedInputException`; `length` is the `N` of its message `Input length = N`
    /// (`readStringMalformedLength`, measured: the merge status line shows it).
    struct MalformedInput: Error, Equatable, Sendable {
        var length: Int = 1
    }

    /// Decodes bytes **strictly** as UTF-8 and **keeps** the BOM as `U+FEFF` —
    /// like Java's `Files.readString(path)`. Invalid UTF-8
    /// (overlong, surrogate points `ED A0 80`, above `U+10FFFF`, truncated sequence,
    /// lone continuation bytes) → `nil`; `U+0000` and non-characters
    /// (`U+FFFF`) pass. Validated by the standard library's own decoder, not
    /// Foundation, so the system version does not matter.
    static func decodeKeepingBom(_ data: Data) -> String? {
        let invalid = transcode(
            data.makeIterator(), from: UTF8.self, to: UTF8.self, stoppingOnError: true,
            into: { _ in })
        guard !invalid else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Reads a file like `decodeKeepingBom`; invalid UTF-8 → `MalformedInput`,
    /// error of reading (e.g. a nonexistent file) passes through from `Data(contentsOf:)`.
    static func readFileKeepingBom(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = decodeKeepingBom(data) else {
            throw MalformedInput(length: readStringMalformedLength(Array(data)) ?? 1)
        }
        return text
    }

    /// The length Java's `Files.readString` reports for the first malformed sequence (JDK 21
    /// `String.decodeUTF8_UTF16` without replacement, `throwMalformed`) — **not** the `CharsetDecoder` length of
    /// `Files.readAllLines` (`GoalFileIO.malformedLength`). Measured (maintainer-only probe, rows `MAL`):
    /// a complete but bad three-byte sequence (bad continuation, overlong `E0 80`, encoded surrogate) is 3, a
    /// complete bad four-byte one (bad continuation, above U+10FFFF) is 4; a three-byte lead followed by exactly
    /// one byte at the end of the input is 2 when that byte is already bad (not a continuation, or `E0 80`–`E0 9F`;
    /// JDK `isMalformed3_2`), otherwise 1; everything else — a lone continuation byte, `C0`/`C1`/`F8`–`FF`, a bad
    /// second byte of a two-byte sequence, any other sequence truncated by the end of the input — is 1.
    /// Valid UTF-8 → `nil`.
    static func readStringMalformedLength(_ bytes: [UInt8]) -> Int? {
        var index = 0
        let count = bytes.count
        while index < count {
            let lead = bytes[index]
            if lead < 0x80 {
                index += 1
            } else if lead >= 0xC2 && lead <= 0xDF {
                guard index + 1 < count, isContinuation(bytes[index + 1]) else { return 1 }
                index += 2
            } else if lead >= 0xE0 && lead <= 0xEF {
                guard index + 2 < count else {
                    guard index + 1 < count else { return 1 }
                    let b2: UInt8 = bytes[index + 1]
                    let badSecond: Bool = (lead == 0xE0 && b2 & 0xE0 == 0x80) || !isContinuation(b2)
                    return badSecond ? 2 : 1
                }
                if !validThree(lead, bytes[index + 1], bytes[index + 2]) { return 3 }
                index += 3
            } else if lead >= 0xF0 && lead <= 0xF7 {
                guard index + 3 < count else { return 1 }
                if !validFour(lead, bytes[index + 1], bytes[index + 2], bytes[index + 3]) { return 4 }
                index += 4
            } else {
                return 1
            }
        }
        return nil
    }

    private static func isContinuation(_ byte: UInt8) -> Bool {
        byte & 0xC0 == 0x80
    }

    private static func validThree(_ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> Bool {
        guard isContinuation(b2), isContinuation(b3) else { return false }
        if b1 == 0xE0 && b2 < 0xA0 { return false }
        let scalar: UInt32 = (UInt32(b1 & 0x0F) << 12) | (UInt32(b2 & 0x3F) << 6) | UInt32(b3 & 0x3F)
        return !(0xD800...0xDFFF).contains(scalar)
    }

    private static func validFour(_ b1: UInt8, _ b2: UInt8, _ b3: UInt8, _ b4: UInt8) -> Bool {
        guard isContinuation(b2), isContinuation(b3), isContinuation(b4) else { return false }
        let high: UInt32 = (UInt32(b1 & 0x07) << 18) | (UInt32(b2 & 0x3F) << 12)
        let scalar: UInt32 = high | (UInt32(b3 & 0x3F) << 6) | UInt32(b4 & 0x3F)
        return (0x10000...0x10FFFF).contains(scalar)
    }
}
