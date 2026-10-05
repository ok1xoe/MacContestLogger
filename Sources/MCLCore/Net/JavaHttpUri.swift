import Foundation

/// Request address of the HTTP clients (callbooks, Club Log, scoreboard) validated like Java
/// `URI.create(url)` + `HttpRequest.newBuilder(uri)`.
///
/// `URL(string:)` is more lenient (it silently encodes a space or `|` in the query), hence a custom port of the parser
/// `java.net.URI.Parser` (RFC 2396 with Java deviations, JDK 21) and `HttpRequestBuilderImpl.checkURI`:
/// - syntax error → `IllegalArgumentException` with the text of `URISyntaxException.getMessage()`
///   (`<reason> at index <i>: <input>`, index in UTF-16 units), e.g. `Illegal character in query at index 37: …`;
/// - no scheme → `URI with undefined scheme`; other than `http`/`https` (case-insensitive) →
///   `invalid URI scheme <scheme lowercased>`; without a server host (registry authority, opaque URI) →
///   `unsupported URI <input>`.
///
/// Measured by the maintainer-only probe (`URI.` rows).
public struct JavaHttpUri: Equatable, Sendable {
    /// Scheme literally (`HTTP` stays `HTTP`, like `URI.getScheme`).
    public let scheme: String
    /// Host (`URI.getHost`; IPv6 with the square brackets).
    public let host: String
    /// Port, `-1` = neuveden.
    public let port: Int
    /// `URI.getRawPath` (may be empty).
    public let rawPath: String
    /// `URI.getRawQuery`, `nil` = no `?`.
    public let rawQuery: String?

    /// Address for `URLSession`: scheme lowercased, host and port, request target like Java
    /// `Utils.encode(rawPath + "?" + rawQuery)` (NFC, non-ASCII as UTF-8 `%XX` uppercase, empty path → `/`).
    /// Java puts userinfo and fragment into the request, we do not either. An IPv6 zone (`[fe80::1%en0]`) goes as `%25`
    /// (RFC 6874). `nil` if `URL(string:)` nevertheless rejected an address Java let through.
    public var requestURL: URL? {
        var target = rawPath.isEmpty ? "/" : rawPath
        if let rawQuery, !rawQuery.isEmpty {
            target += "?" + rawQuery
        }
        let hostPart = host.hasPrefix("[") ? host.replacingOccurrences(of: "%", with: "%25") : host
        var text = scheme.lowercased() + "://" + hostPart
        if port >= 0 {
            text += ":" + String(port)
        }
        text += Self.encodeNonAscii(target)
        // Characters Java lets through are ASCII without spaces and control characters, or `%XX`; `URL(string:)`
        // accepts them (it encodes `[`/`]` in the query — a divergence).
        return URL(string: text)
    }

    /// Java `URI.create(url)` + `checkURI` (see the type).
    public static func parse(_ url: String) throws(JavaIllegalArgumentError) -> JavaHttpUri {
        var parser = JavaUriParser(url)
        try parser.parse()
        guard let scheme = parser.scheme else {
            throw JavaIllegalArgumentError(message: "URI with undefined scheme")
        }
        let lower = scheme.lowercased()
        guard lower == "http" || lower == "https" else {
            throw JavaIllegalArgumentError(message: "invalid URI scheme " + lower)
        }
        guard let host = parser.host else {
            throw JavaIllegalArgumentError(message: "unsupported URI " + url)
        }
        return JavaHttpUri(scheme: scheme, host: host, port: parser.port, rawPath: parser.path ?? "",
                           rawQuery: parser.query)
    }

    /// Java `URI.create(text)` without `checkURI` — a redirect target (`Location`, may be relative).
    static func checkReference(_ text: String) throws(JavaIllegalArgumentError) {
        var parser = JavaUriParser(text)
        try parser.parse()
    }

    /// Java `Utils.encode`: pure ASCII unchanged, otherwise NFC and non-ASCII bytes of UTF-8 as `%XX`.
    private static func encodeNonAscii(_ text: String) -> String {
        guard text.utf16.contains(where: { $0 >= 0x80 }) else { return text }
        let hex: [Character] = Array("0123456789ABCDEF")
        var out = ""
        for byte in text.precomposedStringWithCanonicalMapping.utf8 {
            if byte < 0x80 {
                out.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                out.append("%")
                out.append(hex[Int(byte >> 4)])
                out.append(hex[Int(byte & 0x0F)])
            }
        }
        return out
    }
}

/// Port of `java.net.URI.Parser.parse(false)` (JDK 21) over UTF-16 units. Method names and the order of checks
/// match Java so they can be compared line by line.
struct JavaUriParser {

    private let input: String
    private let units: [UInt16]
    private(set) var scheme: String?
    private(set) var host: String?
    private(set) var port = -1
    private(set) var path: String?
    private(set) var query: String?
    private var ipv6ByteCount = 0

    init(_ input: String) {
        self.input = input
        self.units = Array(input.utf16)
    }

    // MARK: Character masks (`java.net.URI`, literally)

    private static let lDigit: UInt64 = 0x3FF000000000000
    private static let hAlpha: UInt64 = 0x7FFFFFE | 0x7FFFFFE00000000
    private static let lAlphanum: UInt64 = lDigit
    private static let hAlphanum: UInt64 = hAlpha
    private static let lHex: UInt64 = lDigit
    private static let hHex: UInt64 = 0x7E0000007E
    private static let lMark: UInt64 = 0x678200000000
    private static let hMark: UInt64 = 0x4000000080000000
    private static let lUnreserved: UInt64 = lAlphanum | lMark
    private static let hUnreserved: UInt64 = hAlphanum | hMark
    private static let lReserved: UInt64 = 0xAC00985000000000
    private static let hReserved: UInt64 = 0x28000001
    private static let lEscaped: UInt64 = 1
    private static let lUric: UInt64 = lReserved | lUnreserved | lEscaped
    private static let hUric: UInt64 = hReserved | hUnreserved
    private static let lPchar: UInt64 = lUnreserved | lEscaped | 0x2400185000000000
    private static let hPchar: UInt64 = hUnreserved | 0x1
    private static let lPath: UInt64 = lPchar | 0x800800000000000
    private static let hPath: UInt64 = hPchar
    private static let lDash: UInt64 = 0x200000000000
    private static let lDot: UInt64 = 0x400000000000
    private static let lUserinfo: UInt64 = lUnreserved | lEscaped | 0x2C00185000000000
    private static let hUserinfo: UInt64 = hUnreserved
    private static let lRegName: UInt64 = lUnreserved | lEscaped | 0x2C00185000000000
    private static let hRegName: UInt64 = hUnreserved | 0x1
    private static let lServer: UInt64 = lUserinfo | lAlphanum | lDash | 0x400400000000000
    private static let hServer: UInt64 = hUserinfo | hAlphanum | 0x28000001
    private static let lServerPercent: UInt64 = lServer | 0x2000000000
    private static let hServerPercent: UInt64 = hServer
    private static let lScheme: UInt64 = lDigit | 0x680000000000
    private static let hScheme: UInt64 = hAlpha
    private static let lScopeId: UInt64 = lAlphanum | 0x400000000000
    private static let hScopeId: UInt64 = hAlphanum | 0x80000000

    private static func match(_ c: UInt16, _ low: UInt64, _ high: UInt64) -> Bool {
        if c == 0 { return false }
        if c < 64 { return (UInt64(1) << UInt64(c)) & low != 0 }
        if c < 128 { return (UInt64(1) << UInt64(c - 64)) & high != 0 }
        return false
    }

    // MARK: Chyby

    private func error(_ reason: String, _ index: Int) -> JavaIllegalArgumentError {
        JavaIllegalArgumentError(message: "\(reason) at index \(index): \(input)")
    }

    private func fail(_ reason: String, _ index: Int) throws(JavaIllegalArgumentError) -> Never {
        throw error(reason, index)
    }

    // MARK: Scanning

    private func substring(_ start: Int, _ end: Int) -> String {
        String(decoding: units[start..<end], as: UTF16.self)
    }

    private func at(_ start: Int, _ end: Int, _ c: Character) -> Bool {
        start < end && units[start] == Self.unit(c)
    }

    private func at(_ start: Int, _ end: Int, _ text: String) -> Bool {
        let s = Array(text.utf16)
        guard s.count <= end - start else { return false }
        for (i, u) in s.enumerated() where units[start + i] != u {
            return false
        }
        return true
    }

    private static func unit(_ c: Character) -> UInt16 {
        c.utf16.first!
    }

    private func scan(_ start: Int, _ end: Int, char c: Character) -> Int {
        at(start, end, c) ? start + 1 : start
    }

    /// `scan(start, end, err, stop)`: `-1` if it hits a character from `err` first.
    private func scan(_ start: Int, _ end: Int, err: String, stop: String) -> Int {
        let errUnits = Array(err.utf16)
        let stopUnits = Array(stop.utf16)
        var p = start
        while p < end {
            let c = units[p]
            if errUnits.contains(c) { return -1 }
            if stopUnits.contains(c) { break }
            p += 1
        }
        return p
    }

    private func scan(_ start: Int, _ end: Int, stop: String) -> Int {
        let stopUnits = Array(stop.utf16)
        var p = start
        while p < end && !stopUnits.contains(units[p]) {
            p += 1
        }
        return p
    }

    private func scanEscape(_ start: Int, _ n: Int, _ c: UInt16) throws(JavaIllegalArgumentError) -> Int {
        if c == Self.unit("%") {
            if start + 3 <= n, Self.match(units[start + 1], Self.lHex, Self.hHex),
               Self.match(units[start + 2], Self.lHex, Self.hHex) {
                return start + 3
            }
            try fail("Malformed escape pair", start)
        } else if c > 128 && !Self.isSpaceChar(c) && !Self.isISOControl(c) {
            return start + 1
        }
        return start
    }

    private func scan(_ start: Int, _ n: Int, _ low: UInt64, _ high: UInt64) throws(JavaIllegalArgumentError) -> Int {
        var p = start
        while p < n {
            let c = units[p]
            if Self.match(c, low, high) {
                p += 1
                continue
            }
            if low & Self.lEscaped != 0 {
                let q = try scanEscape(p, n, c)
                if q > p {
                    p = q
                    continue
                }
            }
            break
        }
        return p
    }

    private func checkChars(_ start: Int, _ end: Int, _ low: UInt64, _ high: UInt64,
                            _ what: String) throws(JavaIllegalArgumentError) {
        let p = try scan(start, end, low, high)
        if p < end {
            try fail("Illegal character in " + what, p)
        }
    }

    // MARK: Gramatika

    mutating func parse() throws(JavaIllegalArgumentError) {
        let n = units.count
        var p = scan(0, n, err: "/?#", stop: ":")
        if p >= 0 && at(p, n, ":") {
            if p == 0 {
                try fail("Expected scheme name", 0)
            }
            try checkChars(0, 1, 0, Self.hAlpha, "scheme name")
            try checkChars(1, p, Self.lScheme, Self.hScheme, "scheme name")
            scheme = substring(0, p)
            p += 1
            if at(p, n, "/") {
                p = try parseHierarchical(p, n)
            } else {
                let q = scan(p, n, stop: "#")
                if q <= p {
                    try fail("Expected scheme-specific part", p)
                }
                try checkChars(p, q, Self.lUric, Self.hUric, "opaque part")
                p = q
            }
        } else {
            p = try parseHierarchical(0, n)
        }
        if at(p, n, "#") {
            try checkChars(p + 1, n, Self.lUric, Self.hUric, "fragment")
            p = n
        }
        if p < n {
            try fail("end of URI", p)
        }
    }

    private mutating func parseHierarchical(_ start: Int, _ n: Int) throws(JavaIllegalArgumentError) -> Int {
        var p = start
        if at(p, n, "/") && at(p + 1, n, "/") {
            p += 2
            let q = scan(p, n, stop: "/?#")
            if q > p {
                p = try parseAuthority(p, q)
            } else if q >= n {
                try fail("Expected authority", p)
            }
        }
        var q = scan(p, n, stop: "?#")
        try checkChars(p, q, Self.lPath, Self.hPath, "path")
        path = substring(p, q)
        p = q
        if at(p, n, "?") {
            p += 1
            q = scan(p, n, stop: "#")
            try checkChars(p, q, Self.lUric, Self.hUric, "query")
            query = substring(p, q)
            p = q
        }
        return p
    }

    private mutating func parseAuthority(_ start: Int, _ n: Int) throws(JavaIllegalArgumentError) -> Int {
        let p = start
        var q = p
        var stored: JavaIllegalArgumentError?
        let serverChars: Bool
        if scan(p, n, stop: "]") > p {
            serverChars = try scan(p, n, Self.lServerPercent, Self.hServerPercent) == n
        } else {
            serverChars = try scan(p, n, Self.lServer, Self.hServer) == n
        }
        let qreg = try scan(p, n, Self.lRegName, Self.hRegName)
        let regChars = qreg == n
        if regChars && !serverChars {
            return n
        }
        let skipParseException = regChars
        if serverChars {
            do {
                q = try parseServer(p, n, skipParseException)
                if q < n {
                    if skipParseException {
                        host = nil
                        port = -1
                        q = p
                    } else {
                        try fail("Expected end of authority", q)
                    }
                }
            } catch {
                host = nil
                port = -1
                stored = error
                q = p
            }
        }
        if q < n {
            if regChars {
                // registry authority: no host
            } else if let stored {
                throw stored
            } else {
                try fail("Illegal character in authority", serverChars ? q : qreg)
            }
        }
        return n
    }

    private mutating func parseServer(_ start: Int, _ n: Int, _ skipParseException: Bool) throws(JavaIllegalArgumentError) -> Int {
        var p = start
        var q = scan(p, n, err: "/?#", stop: "@")
        if q >= p && at(q, n, "@") {
            try checkChars(p, q, Self.lUserinfo, Self.hUserinfo, "user info")
            p = q + 1
        }
        if at(p, n, "[") {
            p += 1
            q = scan(p, n, err: "/?#", stop: "]")
            if q > p && at(q, n, "]") {
                let r = scan(p, q, stop: "%")
                if r > p {
                    _ = try parseIPv6Reference(p, r)
                    if r + 1 == q {
                        throw JavaIllegalArgumentError(message: "scope id expected: " + input)
                    }
                    try checkChars(r + 1, q, Self.lScopeId, Self.hScopeId, "scope id")
                } else {
                    _ = try parseIPv6Reference(p, q)
                }
                host = substring(p - 1, q + 1)
                p = q + 1
            } else {
                try fail("Expected closing bracket for IPv6 address", q)
            }
        } else {
            q = parseIPv4Address(p, n)
            if q <= p {
                q = try parseHostname(p, n, skipParseException)
            }
            p = q
        }
        if at(p, n, ":") {
            p += 1
            q = scan(p, n, stop: "/")
            if q > p {
                try checkChars(p, q, Self.lDigit, 0, "port number")
                guard let value = Self.parseInt(units[p..<q]) else {
                    try fail("Malformed port number", p)
                }
                port = value
                p = q
            }
        } else if p < n && skipParseException {
            return p
        }
        if p < n {
            try fail("Expected port number", p)
        }
        return p
    }

    /// Java `Integer.parseInt` over ASCII digits; `nil` = `int` overflow.
    private static func parseInt(_ digits: ArraySlice<UInt16>) -> Int? {
        var value = 0
        for u in digits {
            value = value * 10 + Int(u - 0x30)
            if value > Int(Int32.max) { return nil }
        }
        return value
    }

    // MARK: IPv4

    /// `scanByte`: `nil` instead of Java `NumberFormatException` (`int` overflow).
    private func scanByte(_ start: Int, _ n: Int) throws(JavaIllegalArgumentError) -> Int? {
        let q = try scan(start, n, Self.lDigit, 0)
        if q <= start { return q }
        guard let value = Self.parseInt(units[start..<q]) else { return nil }
        return value > 255 ? start : q
    }

    /// `scanIPv4Address`; `nil` = Java `NumberFormatException` (only on byte overflow).
    private func scanIPv4Address(_ start: Int, _ n: Int, strict: Bool) throws(JavaIllegalArgumentError) -> Int? {
        var p = start
        let m = try scan(p, n, Self.lDigit | Self.lDot, 0)
        if m <= p || (strict && m != n) {
            return -1
        }
        var q = p
        for index in 0..<7 {
            if index % 2 == 0 {
                guard let byteEnd = try scanByte(p, m) else { return nil }
                q = byteEnd
            } else {
                q = scan(p, m, char: ".")
            }
            if q <= p {
                try fail("Malformed IPv4 address", q)
            }
            p = q
        }
        if q < m {
            try fail("Malformed IPv4 address", q)
        }
        return q
    }

    private func takeIPv4Address(_ start: Int, _ n: Int, _ expected: String) throws(JavaIllegalArgumentError) -> Int {
        // Java `NumberFormatException` (overflow) would escape here from `URI.create` outside
        // `IllegalArgumentException`; here as "Malformed IPv4 address" (a divergence only for a nonsensical address).
        guard let p = try scanIPv4Address(start, n, strict: true) else {
            try fail("Malformed IPv4 address", start)
        }
        if p <= start {
            try fail("Expected " + expected, start)
        }
        return p
    }

    private mutating func parseIPv4Address(_ start: Int, _ n: Int) -> Int {
        var p: Int
        do {
            guard let end = try scanIPv4Address(start, n, strict: false) else { return -1 }
            p = end
        } catch {
            return -1
        }
        if p > start && p < n && units[p] != Self.unit(":") {
            p = -1
        }
        if p > start {
            host = substring(start, p)
        }
        return p
    }

    private mutating func parseHostname(_ start: Int, _ n: Int, _ skipParseException: Bool) throws(JavaIllegalArgumentError) -> Int {
        var p = start
        var l = -1
        repeat {
            var q = try scan(p, n, Self.lAlphanum, Self.hAlphanum)
            if q <= p { break }
            l = p
            p = q
            q = try scan(p, n, Self.lAlphanum | Self.lDash, Self.hAlphanum)
            if q > p {
                if units[q - 1] == Self.unit("-") {
                    try fail("Illegal character in hostname", q - 1)
                }
                p = q
            }
            q = scan(p, n, char: ".")
            if q <= p { break }
            p = q
        } while p < n
        if p < n && !at(p, n, ":") {
            if skipParseException {
                return p
            }
            try fail("Illegal character in hostname", p)
        }
        if l < 0 {
            try fail("Expected hostname", start)
        }
        if l > start && !Self.match(units[l], 0, Self.hAlpha) {
            try fail("Illegal character in hostname", l)
        }
        host = substring(start, p)
        return p
    }

    // MARK: IPv6

    private mutating func parseIPv6Reference(_ start: Int, _ n: Int) throws(JavaIllegalArgumentError) -> Int {
        var p = start
        var compressedZeros = false
        let q = try scanHexSeq(p, n)
        if q > p {
            p = q
            if at(p, n, "::") {
                compressedZeros = true
                p = try scanHexPost(p + 2, n)
            } else if at(p, n, ":") {
                p = try takeIPv4Address(p + 1, n, "IPv4 address")
                ipv6ByteCount += 4
            }
        } else if at(p, n, "::") {
            compressedZeros = true
            p = try scanHexPost(p + 2, n)
        }
        if p < n {
            try fail("Malformed IPv6 address", start)
        }
        if ipv6ByteCount > 16 {
            try fail("IPv6 address too long", start)
        }
        if !compressedZeros && ipv6ByteCount < 16 {
            try fail("IPv6 address too short", start)
        }
        if compressedZeros && ipv6ByteCount == 16 {
            try fail("Malformed IPv6 address", start)
        }
        return p
    }

    private mutating func scanHexPost(_ start: Int, _ n: Int) throws(JavaIllegalArgumentError) -> Int {
        var p = start
        if p == n {
            return p
        }
        let q = try scanHexSeq(p, n)
        if q > p {
            p = q
            if at(p, n, ":") {
                p += 1
                p = try takeIPv4Address(p, n, "hex digits or IPv4 address")
                ipv6ByteCount += 4
            }
        } else {
            p = try takeIPv4Address(p, n, "hex digits or IPv4 address")
            ipv6ByteCount += 4
        }
        return p
    }

    private mutating func scanHexSeq(_ start: Int, _ n: Int) throws(JavaIllegalArgumentError) -> Int {
        var p = start
        var q = try scan(p, n, Self.lHex, Self.hHex)
        if q <= p { return -1 }
        if at(q, n, ".") { return -1 }
        if q > p + 4 {
            try fail("IPv6 hexadecimal digit sequence too long", p)
        }
        ipv6ByteCount += 2
        p = q
        while p < n {
            if !at(p, n, ":") { break }
            if at(p + 1, n, ":") { break }
            p += 1
            q = try scan(p, n, Self.lHex, Self.hHex)
            if q <= p {
                try fail("Expected digits for an IPv6 address", p)
            }
            if at(q, n, ".") {
                p -= 1
                break
            }
            if q > p + 4 {
                try fail("IPv6 hexadecimal digit sequence too long", p)
            }
            ipv6ByteCount += 2
            p = q
        }
        return p
    }

    // MARK: Znaky

    /// Java `Character.isSpaceChar(char)`: categories Zs, Zl, Zp (a surrogate is not a space).
    private static func isSpaceChar(_ c: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(c) else { return false }
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }

    /// Java `Character.isISOControl(char)`.
    private static func isISOControl(_ c: UInt16) -> Bool {
        c <= 0x1F || (0x7F...0x9F).contains(c)
    }
}
