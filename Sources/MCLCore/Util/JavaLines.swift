/// Java splitting of text into lines: `BufferedReader.readLine` (and `Files.readAllLines`,
/// `Files.lines`, `BufferedReader.lines` built on it) and `String.lines()` —
/// measured to give the same result (`HelpersTests.splitMatchesJavaReadLine`).
///
/// - The terminator is `\n`, `\r` or `\r\n` (a bare `\r` splits too — `ScpDatabase`, call history);
/// - after the last terminator **no empty line is added** (`"a\n"` → `["a"]`,
///   `"a\n\n"` → `["a", ""]`), empty input gives `[]`;
/// - U+2028, U+0085, VT and FF do not split, a BOM remains part of the first line.
///
/// Swift's `split(separator: "\n")` cannot handle `\r`, and `\r\n` is a single `Character` in it,
/// so splitting is done by scalars here.
enum JavaLines {

    static func split(_ text: String) -> [String] {
        let scalars = text.unicodeScalars
        var lines: [String] = []
        var start = scalars.startIndex
        var index = start
        while index < scalars.endIndex {
            let scalar: Unicode.Scalar = scalars[index]
            guard scalar == "\n" || scalar == "\r" else {
                index = scalars.index(after: index)
                continue
            }
            lines.append(String(scalars[start..<index]))
            var next = scalars.index(after: index)
            if scalar == "\r", next < scalars.endIndex, scalars[next] == "\n" {
                next = scalars.index(after: next)
            }
            start = next
            index = next
        }
        if start < scalars.endIndex {
            lines.append(String(scalars[start..<scalars.endIndex]))
        }
        return lines
    }
}
