import Foundation

/// Shared reading of the CSV `znacka;lokator;pocet` (`<contestDataDir>/multipliers/ww_digi_grid.csv`) for
/// `GridDatabase` and `GridFieldMap` — both Java classes read it with the same loop:
/// - `InputStreamReader(UTF_8)`: bad bytes → U+FFFD per the Java decoder (`JavaUtf8`);
/// - `BufferedReader.readLine`: terminators `\n`, `\r`, `\r\n`; the last line without a terminator is
///   returned, no empty line arises after a trailing terminator;
/// - **first line only**: all U+FEFF are removed from it (`replace`), and if after Java
///   `toLowerCase()` it then starts with `znacka`, it is a header and is skipped (`ZNACKA;…` and `znacka123` too);
///   a BOM on further lines stays part of the text;
/// - `split(";", -1)` (trailing empty parts stay), fewer than two parts → the line is skipped;
/// - callsign and locator `trim()` (characters ≤ U+0020).
///
/// The bundled `ww_digi_grid.csv` is an aggregate (callsign; locator; number of occurrences)
/// compiled by the author from CQ WW Digi contest logs (`THIRD_PARTY_NOTICES.md`).
enum CallsignGridCsv {

    /// Java `Path.resolve("multipliers").resolve("ww_digi_grid.csv")`.
    static func file(in contestDataDir: URL) -> URL {
        contestDataDir.appendingPathComponent("multipliers").appendingPathComponent("ww_digi_grid.csv")
    }

    /// Lines with at least two parts as `(trim(callsign), trim(locator))` in file order.
    static func rows(_ data: Data) -> [(call: String, grid: String)] {
        let units: [UInt16] = Array(JavaUtf8.decode(data).utf16)
        var out: [(call: String, grid: String)] = []
        var first = true
        for var line in readLines(units) {
            if first {
                line.removeAll { $0 == 0xFEFF }
                first = false
                let lower: [UInt16] = Array(JavaText.toLowerCase(String(decoding: line, as: UTF16.self)).utf16)
                if lower.starts(with: Array("znacka".utf16)) {
                    continue
                }
            }
            let parts: [ArraySlice<UInt16>] = line.split(separator: 0x3B, omittingEmptySubsequences: false)
            if parts.count < 2 {
                continue
            }
            let call = JavaText.trim(String(decoding: parts[0], as: UTF16.self))
            let grid = JavaText.trim(String(decoding: parts[1], as: UTF16.self))
            out.append((call, grid))
        }
        return out
    }

    /// Java `BufferedReader.readLine` over the whole text.
    static func readLines(_ units: [UInt16]) -> [[UInt16]] {
        var lines: [[UInt16]] = []
        var current: [UInt16] = []
        var index = 0
        while index < units.count {
            let unit = units[index]
            index += 1
            if unit == 0x0A || unit == 0x0D {
                lines.append(current)
                current = []
                if unit == 0x0D && index < units.count && units[index] == 0x0A {
                    index += 1
                }
            } else {
                current.append(unit)
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }
}
