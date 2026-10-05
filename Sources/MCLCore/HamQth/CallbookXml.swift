/// Shared "parsing" of HamQTH and QRZ XML responses — the Java clients **do not use** an XML parser, only the
/// regex `<tag>(.*?)</tag>` with `Pattern.DOTALL` (`find()`, first occurrence):
/// - tags are case-sensitive (`<Key>` ≠ `<key>`), attributes (`<grid a="1">`) prevent a match;
/// - entities (`&amp;`) and `CDATA` are not decoded — the value is the raw text between the tags;
/// - value `trim()` (characters ≤ U+0020); empty = missing (`nil`), **even if** a non-empty occurrence of the same tag
///   were further in the document (only the first `find()` is taken);
/// - nesting (`<grid><grid>x</grid></grid>`) lazily gives the shortest match from the first opening tag.
enum CallbookXml {

    /// Java `Pattern.compile("<tag>(.*?)</tag>", Pattern.DOTALL)`.
    static func tag(_ name: String) -> JavaRegex {
        var pattern = "(?s)<" + name + ">(.*?)"
        pattern += "</" + name + ">"
        return compile(pattern)
    }

    /// Java `Pattern.compile` over a literal from the source — an error is a program defect.
    static func compile(_ pattern: String) -> JavaRegex {
        do {
            return try JavaRegex(pattern)
        } catch {
            preconditionFailure("pevný vzor callbooku musí jít zkompilovat: \(error)")
        }
    }

    /// Java `firstGroup(p, xml)`: `null` → empty, first match, `group(1).trim()`, empty → empty.
    static func firstGroup(_ regex: JavaRegex, _ xml: String?) -> String? {
        guard let xml, let match = regex.firstMatch(in: xml) else { return nil }
        let value = JavaText.trim(match.group(1) ?? "")
        return value.isEmpty ? nil : value
    }

    /// Java `text.replaceAll(regex, "$1***")` — replaces each match with group 1 and `***`
    /// (password masks in the log; the patterns have no empty matches).
    static func maskGroup1(_ regex: JavaRegex, _ text: String) -> String {
        let matches = regex.allMatches(in: text)
        guard !matches.isEmpty else { return text }
        let units: [UInt16] = Array(text.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        var index = 0
        for match in matches {
            out.append(contentsOf: units[index..<match.range.lowerBound])
            out.append(contentsOf: (match.group(1) ?? "").utf16)
            out.append(contentsOf: "***".utf16)
            index = match.range.upperBound
        }
        out.append(contentsOf: units[index...])
        return String(decoding: out, as: UTF16.self)
    }
}
