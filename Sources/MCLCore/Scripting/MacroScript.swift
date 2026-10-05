import Darwin

/// Macro script: a text file `scripts/<name>.txt`, each line one text command of the call field (`CW`,
/// `14025`, `SPLIT`, `RIT 0`…); `#` comment. Started by the command `SCRIPT name` (DXLog Scripts). Java
/// `scripting.MacroScript` v1.1.1.
public enum MacroScript {

    /// Script lines without blank ones and comments; `nil` (Java `Optional.empty()`) when the name is not
    /// `[a-z0-9_-]+` (after Java `trim()` and `toLowerCase(Locale.ROOT)` — `K` U+212A passes as `k`, `İ` does not),
    /// the file cannot be read (`Files.isReadable`), it is a directory, or it is not valid UTF-8 (`readAllLines` reports
    /// a bad sequence). Lines are split by `\n`, `\r`, `\r\n`, trimmed by Java `strip()` (NBSP stays), the BOM stays
    /// part of the first line. Measured by the maintainer-only probe.
    public static func load(_ scriptsDir: String, _ name: String?) -> [String]? {
        let n: String = JavaText.toLowerCase(JavaText.trim(name ?? ""))
        guard isValidName(n) else {
            return nil
        }
        let file: String = RawFileSystem.resolve(scriptsDir, n + ".txt")
        guard access(file, R_OK) == 0, case .data(let data) = RawFileSystem.readFile(RawPath(file)) else {
            return nil
        }
        guard let text = JavaUtf8.strict([UInt8](data)) else {
            return nil
        }
        return JavaLines.split(text).map(JavaText.strip).filter { !$0.isEmpty && $0.utf16.first != 0x23 }
    }

    /// Java `matches("[a-z0-9_-]+")`.
    static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty else {
            return false
        }
        return name.utf16.allSatisfy { unit in
            (unit >= 0x61 && unit <= 0x7A) || (unit >= 0x30 && unit <= 0x39) || unit == 0x5F || unit == 0x2D
        }
    }
}
