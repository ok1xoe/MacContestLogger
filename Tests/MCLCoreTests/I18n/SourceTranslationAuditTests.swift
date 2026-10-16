import Foundation
import Testing
@testable import MCLCore

/// A static audit of the Swift sources against the shipped languages (`docs/translations.md`; the wider report is
/// `scripts/i18n-audit.py`). The UI texts are Czech in the code and translated by `lang_<code>.json`, so a Czech text
/// that skips the translator shows up in Czech in English or German, and a key missing from a language file stays
/// Czech there:
///
/// - every literal key handed to the translator (`tr`, `translate`, `ContestMessage`, `status.show`) is in the shipped
///   English and German, and none is built with string interpolation;
/// - in the app's views no literal with Czech diacritics goes straight to a visible text (`Text`, `Button`, a
///   tooltip, an accessibility label, a menu item, the Settings form parts…) without `tr`;
/// - no literal with Czech diacritics is shown as is (`.verbatim(…)`, `showVerbatim(…)`).
///
/// Comments are skipped. The audit reads the sources next to the test (`#filePath`), so it runs wherever the tests are
/// built from a checkout.
@Suite struct SourceTranslationAuditTests {

    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    static let diacritics: Set<Character> = Set("áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ")

    /// A string literal of a source: its text (escapes resolved, interpolations kept as `\(…)`), the line, and the
    /// code before it on the same statement with comments removed and every literal emptied (`""`).
    struct Literal {
        let line: Int
        let text: String
        let interpolated: Bool
        let before: String
        /// The code after the literal (comments removed), up to 80 characters.
        let after: String
    }

    /// Czech: Czech diacritics, or a key of the shipped English with a different English text ("Smazat", "Celkem") —
    /// so Czech words without diacritics count, while English, numbers and codes do not.
    static func isCzech(_ text: String, en: [String: String]) -> Bool {
        if text.contains(where: diacritics.contains) {
            return true
        }
        guard let english = en[text] else { return false }
        return english != text
    }

    // MARK: - rules

    /// A call that hands its first argument to the translator.
    static let translatorCall = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z_])(tr|translate|ContestMessage|show)\(\s*$"#)

    /// A view part that shows its argument as is (the app's views).
    static let visibleSink = try! NSRegularExpression(pattern: #"(?:"#
        + #"Text\((?:verbatim:\s*)?|Button\(|Label\(|Toggle\(|Picker\(|Menu\(|TextField\(|SecureField\(|Section\("#
        + #"|\.help\(|\.navigationTitle\(|accessibility(?:Label|Hint|Value)\((?:Text\((?:verbatim:\s*)?)?"#
        + #"|messageText\s*=\s*|informativeText\s*=\s*|addButton\(withTitle:\s*|NSMenuItem\(title:\s*"#
        + #"|toolTip\s*=\s*|addItem\(menu,\s*|ToolField\(label:\s*"#
        + #"|Settings(?:Group|Field|Caption|Checkbox|Radio|Button|Text|DeleteButton)\((?:title:|caption:|label:|help:)?\s*"#
        + #")(?:[^()\n]*?[?:]\s*)?$"#)

    /// A text shown as is.
    static let verbatimCall = try! NSRegularExpression(pattern: #"(?:\.verbatim|showVerbatim)\(\s*$"#)

    /// Exceptions: (file suffix, text) → why.
    static let allowed: [String: String] = [
        "MacContestLogger/MacContestLoggerApp.swift|Aplikaci nelze spustit: chybí její zdroje.":
            "the app's resources (with the language files) are missing; no translation can be loaded",
        "MacContestLogger/MacContestLoggerApp.swift|Ukončit": "the same alert",
        "MacContestLogger/AppHost.swift|Ukončit": "the bootstrap failed before the language was loaded",
    ]

    static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The findings of one source file (`path` relative to `Sources/`).
    static func findings(path: String, source: String, en: [String: String], de: Set<String>,
                         used: inout Set<String>) -> [String] {
        var out: [String] = []
        let literals: [Literal] = Self.literals(source)
        var index = 0
        while index < literals.count {
            let literal = literals[index]
            let place = path + ":" + String(literal.line)
            // A key: the literal (or a `+` chain of literals) as the first argument of a translator call.
            if matches(translatorCall, literal.before) {
                var key: String = literal.text
                var interpolated: Bool = literal.interpolated
                var last: Literal = literal
                while index + 1 < literals.count, last.after.hasPrefix("+"),
                      literals[index + 1].before.hasSuffix("+ ") || literals[index + 1].before.hasSuffix("+") {
                    index += 1
                    last = literals[index]
                    key += last.text
                    interpolated = interpolated || last.interpolated
                }
                let next: Character? = last.after.first
                if interpolated {
                    out.append(place + ": a translation key built with interpolation: " + key)
                } else if next == "," || next == ")" {
                    let missing: [String] = [en[key] != nil ? nil : "en", de.contains(key) ? nil : "de"]
                        .compactMap { $0 }
                    if !missing.isEmpty {
                        out.append(place + ": key missing in " + missing.joined(separator: "/") + ": " + key)
                    }
                }
                index += 1
                continue
            }
            if isCzech(literal.text, en: en) {
                let allowKey: String = path + "|" + literal.text
                let isView: Bool = path.hasPrefix("MacContestLogger/")
                if allowed[allowKey] != nil {
                    used.insert(allowKey)
                } else if matches(verbatimCall, literal.before) {
                    out.append(place + ": Czech text shown as is: " + literal.text)
                } else if isView && matches(visibleSink, literal.before) {
                    out.append(place + ": Czech text shown without tr: " + literal.text)
                }
            }
            index += 1
        }
        return out
    }

    // MARK: - the source scanner

    /// The string literals of `source` outside comments (normal, multi-line and raw strings; interpolations may
    /// nest strings and parentheses).
    static func literals(_ source: String) -> [Literal] {
        let chars: [Character] = Array(source)
        var out: [Literal] = []
        var masked: [Character] = []   // the code so far without comments and with emptied literals
        var line = 1
        var i = 0
        var pending: [(line: Int, text: String, interpolated: Bool, before: String, maskedEnd: Int)] = []

        func at(_ k: Int) -> Character? { k < chars.count ? chars[k] : nil }
        func starts(_ s: String, _ k: Int) -> Bool {
            var j = k
            for c in s {
                guard at(j) == c else { return false }
                j += 1
            }
            return true
        }
        func statementTail() -> String {
            // The current statement's code on this line and the lines it continues (up to 200 characters).
            let tail = String(masked.suffix(200))
            if let cut = tail.lastIndex(where: { $0 == "{" || $0 == "}" || $0 == ";" }) {
                return String(tail[tail.index(after: cut)...]).replacingOccurrences(of: "\n", with: " ")
            }
            return tail.replacingOccurrences(of: "\n", with: " ")
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\n" { line += 1 }
            if starts("//", i) {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if starts("/*", i) {
                var depth = 0
                while i < chars.count {
                    if starts("/*", i) { depth += 1; i += 2; continue }
                    if starts("*/", i) { depth -= 1; i += 2; if depth == 0 { break }; continue }
                    if chars[i] == "\n" { line += 1 }
                    i += 1
                }
                continue
            }
            var hashes = 0
            while at(i + hashes) == "#" { hashes += 1 }
            if at(i + hashes) == "\"" {
                let startLine = line
                let multi: Bool = starts("\"\"\"", i + hashes)
                let open: Int = hashes + (multi ? 3 : 1)
                let close: String = (multi ? "\"\"\"" : "\"") + String(repeating: "#", count: hashes)
                let escape: String = "\\" + String(repeating: "#", count: hashes)
                var j = i + open
                var text = ""
                var interpolated = false
                while j < chars.count {
                    if starts(close, j) { break }
                    if starts(escape, j) {
                        let k = j + escape.count
                        if at(k) == "(" {
                            // An interpolation: keep it as written, skipping nested strings and parentheses.
                            interpolated = true
                            var depth = 0
                            var m = k
                            while m < chars.count {
                                if chars[m] == "(" { depth += 1 }
                                if chars[m] == ")" { depth -= 1; if depth == 0 { break } }
                                if chars[m] == "\"" {
                                    m += 1
                                    while m < chars.count, chars[m] != "\"" { if chars[m] == "\\" { m += 1 }; m += 1 }
                                }
                                m += 1
                            }
                            text += "\\(" + String(chars[(k + 1)..<min(m, chars.count)]) + ")"
                            j = m + 1
                            continue
                        }
                        switch at(k) {
                        case "n": text += "\n"
                        case "t": text += "\t"
                        case "r": text += "\r"
                        case "0": text += "\0"
                        case "u":
                            if at(k + 1) == "{", let end = chars[(k + 2)...].firstIndex(of: "}"),
                               let value = UInt32(String(chars[(k + 2)..<end]), radix: 16),
                               let scalar = Unicode.Scalar(value) {
                                text.unicodeScalars.append(scalar)
                                j = end + 1
                                continue
                            }
                        case "\n":
                            line += 1
                            j = k + 1
                            while let s = at(j), s == " " || s == "\t" { j += 1 }
                            continue
                        default:
                            if let s = at(k) { text.append(s) }
                        }
                        j = k + 1
                        continue
                    }
                    if chars[j] == "\n" {
                        if !multi { break }
                        line += 1
                    }
                    text.append(chars[j])
                    j += 1
                }
                if multi {
                    // The opening line break and the closing indentation are not part of the text.
                    if text.hasPrefix("\n") { text.removeFirst() }
                    if let last = text.lastIndex(of: "\n") { text = String(text[..<last]) }
                }
                pending.append((startLine, text, interpolated, statementTail(), 0))
                masked += "\"\""
                let end = j + close.count
                pending[pending.count - 1].maskedEnd = masked.count
                i = end
                continue
            }
            masked.append(c)
            i += 1
        }
        // The code after each literal (from the masked text, which has no comments).
        let maskedText: [Character] = masked
        for item in pending {
            var k = item.maskedEnd
            while k < maskedText.count, maskedText[k] == " " || maskedText[k] == "\n" || maskedText[k] == "\t" {
                k += 1
            }
            let after = String(maskedText[k..<min(k + 80, maskedText.count)])
            out.append(Literal(line: item.line, text: item.text, interpolated: item.interpolated,
                               before: item.before, after: after))
        }
        return out
    }

    // MARK: - inputs

    static func translations(_ code: String) throws -> [String: String] {
        let bytes: [UInt8] = try #require(LanguageCatalog.bundledBytes(code))
        let map = LanguageCatalog.Translations(try #require(LanguageJsonReader.read(bytes)))
        var out: [String: String] = [:]
        for entry in map.sortedEntries {
            out[entry.key] = entry.value
        }
        return out
    }

    /// The audited sources: the core, the app model and the app (not the command-line tools or the modems).
    static func sources() throws -> [(path: String, text: String)] {
        let base: URL = root.appendingPathComponent("Sources")
        var out: [(String, String)] = []
        for dir in ["MCLCore", "MCLAppModel", "MacContestLogger"] {
            let top: URL = base.appendingPathComponent(dir)
            guard let walker = FileManager.default.enumerator(at: top, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let relative: String = dir + "/" + url.path.dropFirst(top.path.count + 1)
                out.append((relative, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    // MARK: - tests

    @Test func theSourcesRouteCzechTextsThroughTheTranslator() throws {
        let en: [String: String] = try Self.translations("en")
        let de: Set<String> = Set(try Self.translations("de").keys)
        let files = try Self.sources()
        #expect(files.count > 500, "the sources were not found next to the tests")
        var used: Set<String> = []
        var findings: [String] = []
        for file in files {
            findings += Self.findings(path: file.path, source: file.text, en: en, de: de, used: &used)
        }
        let report: String = findings.prefix(40).joined(separator: "\n")
        #expect(findings.isEmpty, "\(findings.count) findings:\n\(report)")
        #expect(Set(Self.allowed.keys).subtracting(used).sorted() == [], "unused exceptions")
    }

    /// The audit turns red on the mistakes it is there for (a falsifiable gate).
    @Test func theAuditFindsKnownMistakes() {
        let en: [String: String] = [
            "Smazat": "Delete", "Pásmo %s": "Band %s", "Připojit": "Connect", "Heslo": "Password", "OK": "OK",
            "Sloupce:": "Columns:", "Odebrat spot": "Remove spot", "Odpojit": "Disconnect",
            "Smazat segment": "Delete segment", "Stahuji master.scp…": "Downloading master.scp…",
        ]
        let de: Set<String> = ["Smazat", "Připojit", "Heslo", "OK"]
        var used: Set<String> = []
        let snippet = #"""
            Text(verbatim: "Sloupce:")
            Button("Odebrat spot") { }
            Text(verbatim: on ? "Odpojit" : language.tr("Připojit"))
            SettingsField(caption: "Heslo") { }
            .help("Smazat segment")
            status.showVerbatim("Stahuji master.scp…")
            return .verbatim("Smazání")
            language.tr("Smazat")
            language.tr("Pásmo %s", .string(b))
            language.tr("Nalezeno: \(n) definic")
            language.tr("Dlouhý " + "text")
            // Text(verbatim: "Komentář se nekontroluje")
            Text(verbatim: language.tr("Smazat"))
            let data = "Poznámka v datech"
            Button("Smazat") { }
            Text(verbatim: "OK")
            """#
        let found: [String] = Self.findings(path: "MacContestLogger/X.swift", source: snippet, en: en, de: de,
                                            used: &used)
        let expected: [String] = [
            "MacContestLogger/X.swift:1: Czech text shown without tr: Sloupce:",
            "MacContestLogger/X.swift:2: Czech text shown without tr: Odebrat spot",
            "MacContestLogger/X.swift:3: Czech text shown without tr: Odpojit",
            "MacContestLogger/X.swift:4: Czech text shown without tr: Heslo",
            "MacContestLogger/X.swift:5: Czech text shown without tr: Smazat segment",
            "MacContestLogger/X.swift:6: Czech text shown as is: Stahuji master.scp…",
            "MacContestLogger/X.swift:7: Czech text shown as is: Smazání",
            "MacContestLogger/X.swift:9: key missing in de: Pásmo %s",
            "MacContestLogger/X.swift:10: a translation key built with interpolation: Nalezeno: \\(n) definic",
            "MacContestLogger/X.swift:11: key missing in en/de: Dlouhý text",
            "MacContestLogger/X.swift:15: Czech text shown without tr: Smazat",
        ]
        #expect(found == expected, "\(found)")
        // A core file is not a view: a Czech literal outside `tr` there is data until it is shown as is.
        let core: [String] = Self.findings(path: "MCLCore/X.swift", source: #"Text(verbatim: "Sloupce:")"#, en: en,
                                           de: de, used: &used)
        #expect(core.isEmpty)
    }
}
