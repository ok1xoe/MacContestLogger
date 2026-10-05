import Darwin
import Foundation

/// Controlling fldigi over XML-RPC (Java `digital/FldigiClient`; default port 7362): mode, sending text,
/// TX/RX switching, abort and reading received text. Similar to N1MM "Fldigi for Sound Card Modes".
///
/// HTTP via our own HTTP/1.1 client over `LineSocket` (`JavaHttp1`, a replacement for Java `HttpClient`); behaviour
/// measured by the maintainer-only probe (rows `fl.*`):
/// - `POST /RPC2`, `Content-Length`, `Host`, `Content-Type: text/xml` in the order and bytes of Java, body =
///   `XmlRpc.call` in UTF-8. Java additionally sends h2c upgrade headers and `User-Agent: Java-http-client/…`
///   (a deliberate divergence from Java v1.1.1).
/// - Address as `URI.create` + `HttpClient`: an illegal character in the host → `JavaIllegalArgumentError` **already
///   in the constructor** (`Illegal character in authority|hostname at index n: …`, `Malformed escape pair…`,
///   `Malformed IPv6 address…`, `Expected closing bracket for IPv6 address…`, `Expected port number…`); a host
///   that is not an RFC 2396 name nor IPv4 nor `[IPv6]` (empty, `my_host`, `-a`, `a..b`, `::1`, non-ASCII), or a
///   negative port → on call `unsupported URI http://…/RPC2`; port above 65535 → `port out of range:n`;
///   port 0 → `ConnectException: Can't assign requested address`.
/// - Timeouts exactly as Java: connect 2 s (`HttpConnectTimeoutException: HTTP connect timed out`), from the start
///   to the response headers 3 s (`HttpTimeoutException: request timed out`), body without a timeout.
/// - Refused connection and unknown host → `JavaIOError(nil, javaClass: "java.net.ConnectException")`
///   (Java `getMessage()` is `null`); connection closed without a response → `HTTP/1.1 header parser received no bytes`;
///   status other than 200 (even a redirect — not followed) → `JavaIOError("fldigi: HTTP <n>")`; response →
///   `XmlRpc.parseResponse` (`XmlRpc.Failure` as Java `IllegalStateException`).
///
/// **Synchronous and blocking** like Java `HttpClient.send` (up to the response headers at most 3 s including connect; name
/// resolution, writing the request and the response body without a limit): call only from your own
/// thread (`Thread`, Kotlin `Dispatchers.IO`/`cwDispatcher`) — never from a `Task`/`async` function, the main thread or
/// a GCD queue shared with other work.
public final class FldigiClient: Sendable {

    /// Java `connectTimeout(Duration.ofSeconds(2))`.
    static let connectTimeoutMs = 2_000
    /// Java `HttpRequest.timeout(Duration.ofSeconds(3))`.
    static let requestTimeoutMs = 3_000

    /// Address in the form of a Java `URI` (`http://host:port/RPC2`).
    let uri: String
    private let host: String
    private let port: Int
    private let hostUsable: Bool
    private let connectTimeoutMs: Int
    private let requestTimeoutMs: Int

    /// Java `new FldigiClient(host, port)`; an address syntax error throws like `URI.create`.
    public convenience init(host: String, port: Int) throws(JavaIllegalArgumentError) {
        try self.init(host: host, port: port, connectTimeoutMs: Self.connectTimeoutMs, requestTimeoutMs: Self.requestTimeoutMs)
    }

    /// For tests: generous timeouts in success scenarios (success must not depend on wall-clock time).
    init(host: String, port: Int, connectTimeoutMs: Int, requestTimeoutMs: Int) throws(JavaIllegalArgumentError) {
        self.connectTimeoutMs = connectTimeoutMs
        self.requestTimeoutMs = requestTimeoutMs
        let uri = "http://" + host + ":" + String(port) + "/RPC2"
        if let error = JavaUri.syntaxError(host: host, port: port, uri: uri) {
            throw error
        }
        self.uri = uri
        self.host = host
        self.port = port
        hostUsable = port >= 0 && JavaUri.isServerHost(host)
    }

    public func version() throws -> String {
        Self.valueOf(try call("fldigi.version"))
    }

    public func modemName() throws -> String {
        Self.valueOf(try call("modem.get_name"))
    }

    public func setModem(_ name: String) throws {
        _ = try call("modem.set_by_name", .string(name))
    }

    /// State "TX" / "RX" / "TUNE".
    public func trxState() throws -> String {
        Self.valueOf(try call("main.get_trx_state"))
    }

    /// Transmits text: puts it into the TX buffer, turns on transmission and `^r` at the end returns fldigi to receive
    /// after transmitting.
    public func transmit(_ text: String) throws {
        _ = try call("text.clear_tx")
        _ = try call("text.add_tx", .string(text + "^r"))
        _ = try call("main.tx")
    }

    /// Immediately interrupts transmission and discards the rest of the TX buffer.
    public func abort() throws {
        _ = try call("main.abort")
        _ = try call("text.clear_tx")
    }

    public func rxLength() throws -> Int32 {
        try Self.intValue(try call("text.get_rx_length"))
    }

    /// Received text from position `start`, at most `length` characters (`base64` → ISO-8859-1 like Java).
    public func rxText(start: Int32, length: Int32) throws -> String {
        let value = try call("text.get_rx", .int(Int64(start)), .int(Int64(length)))
        if case .bytes(let bytes) = value {
            return String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
        }
        return Self.valueOf(value)
    }

    /// Marker frequency in the audio (Hz).
    public func carrier() throws -> Int32 {
        try Self.intValue(try call("modem.get_carrier"))
    }

    // MARK: - Calls

    func call(_ method: String, _ params: XmlRpc.Param...) throws -> XmlRpc.Value? {
        let body: String = try exchange(XmlRpc.call(method, params: params))
        return try XmlRpc.parseResponse(body)
    }

    /// One HTTP request: the response body (UTF-8) on status 200, otherwise a Java exception.
    func exchange(_ xml: String) throws -> String {
        guard hostUsable else {
            throw JavaIllegalArgumentError(message: "unsupported URI " + uri)
        }
        // `[IPv6]` → address without brackets for connecting, in `Host` with brackets (Java `uri.getHost()`).
        var address = host
        if address.hasPrefix("[") && address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        let response = try JavaHttp1.post(
            host: address, port: port, hostHeader: JavaHttp1.hostHeader(host: host, port: port), path: "/RPC2",
            headers: [("Content-Type", "text/xml")], body: Array(xml.utf8),
            connectTimeoutMs: connectTimeoutMs, requestTimeoutMs: requestTimeoutMs)
        if response.status != 200 {
            throw JavaIOError("fldigi: HTTP " + String(response.status))
        }
        return String(decoding: response.body, as: UTF8.self)
    }

    /// Java `String.valueOf(Object)` over the response value. `byte[]` gives `[B@<identity hash>` in Java
    /// (random); Swift returns `[B@0` (a divergence with no impact — fldigi sends `base64` only for `text.get_rx`).
    static func valueOf(_ value: XmlRpc.Value?) -> String {
        switch value {
        case .none: return "null"
        case .string(let text): return text
        case .int(let number): return String(number)
        case .double(let number): return JavaDouble.toString(number)
        case .bool(let flag): return flag ? "true" : "false"
        case .bytes: return "[B@0"
        }
    }

    /// Java `v instanceof Integer i ? i : Integer.parseInt(String.valueOf(v).trim())`.
    static func intValue(_ value: XmlRpc.Value?) throws(JavaNumberFormatError) -> Int32 {
        if case .int(let number) = value {
            return number
        }
        let text = JavaText.trim(valueOf(value))
        guard let number = JavaInteger.parseInt(text) else {
            throw JavaNumberFormatError(message: "For input string: \"" + text + "\"")
        }
        return number
    }
}

/// Parts of Java `java.net.URI` (RFC 2396 parser) that decide the fldigi address
/// (`http://<host>:<port>/RPC2`, the authority starts at index 7).
enum JavaUri {

    static let authorityStart = 7

    /// `URI.create` error for the host (or `nil`): an illegal character / bad `%` (check of the characters of the whole URI),
    /// then square brackets (an authority with `[`/`]` is not "registry-based", so a server authority error is thrown):
    /// `[` at the start → IPv6 in brackets (`Expected closing bracket for IPv6 address`, `Malformed IPv6 address`,
    /// `Expected port number`), elsewhere → `Illegal character in hostname` at the place where the name stops being valid.
    static func syntaxError(host: String, port: Int, uri: String) -> JavaIllegalArgumentError? {
        if let error = illegalCharacter(in: host, uri: uri, offset: authorityStart) {
            return error
        }
        let units = Array(host.utf16)
        guard units.contains(0x5B) || units.contains(0x5D) else { return nil }
        func fail(_ text: String, _ index: Int) -> JavaIllegalArgumentError {
            JavaIllegalArgumentError(message: text + " at index " + String(index) + ": " + uri)
        }
        if units.first == 0x5B {
            var q = 1
            while q < units.count && !(units[q] == 0x5D || units[q] == 0x2F || units[q] == 0x3F || units[q] == 0x23) {
                q += 1
            }
            if q >= units.count {
                // Without `]` the scan reaches the end of the authority (past the port).
                let end = authorityStart + units.count + 1 + String(port).utf16.count
                return fail("Expected closing bracket for IPv6 address", end)
            }
            if units[q] != 0x5D || q == 1 {
                return fail("Expected closing bracket for IPv6 address", authorityStart + q)
            }
            if !isIPv6(String(decoding: units[1..<q], as: UTF16.self)) {
                return fail("Malformed IPv6 address", authorityStart + 1)
            }
            if q + 1 < units.count {
                return fail("Expected port number", authorityStart + q + 1)
            }
            return nil
        }
        return fail("Illegal character in hostname", authorityStart + hostnameEnd(units))
    }

    /// Characters allowed in a URI authority (`L_REG_NAME | L_SERVER`): alphanumerics, `-_.!~*'()`, `;:&=+$,`, `@`,
    /// `[]` and non-ASCII "other" (not a space or control character); `%` only with two hexadecimal digits. Any other character
    /// → `URISyntaxException` like Java `URI.create` (index in the whole URI).
    static func illegalCharacter(in host: String, uri: String, offset: Int) -> JavaIllegalArgumentError? {
        let units = Array(host.utf16)
        var i = 0
        while i < units.count {
            let u = units[i]
            if u == 0x25 { // %
                if i + 2 < units.count, isHex(units[i + 1]), isHex(units[i + 2]) {
                    i += 3
                    continue
                }
                return JavaIllegalArgumentError(message: "Malformed escape pair at index " + String(offset + i) + ": " + uri)
            }
            if !isAuthorityChar(u) {
                return JavaIllegalArgumentError(message: "Illegal character in authority at index " + String(offset + i) + ": " + uri)
            }
            i += 1
        }
        return nil
    }

    /// Host of a server authority: `[IPv6]`, IPv4 or an RFC 2396 name (`domainlabel` of alphanumerics
    /// and inner `-`, the rightmost of several labels starts with a letter, optional trailing dot). Otherwise Java takes the
    /// authority as "registry-based" without a host and `HttpClient` reports `unsupported URI`.
    static func isServerHost(_ host: String) -> Bool {
        let units = Array(host.utf16)
        if units.first == 0x5B { // [ — syntax already verified by the constructor
            return true
        }
        if isIPv4(units) {
            return true
        }
        return hostnameEnd(units) == units.count && hostnameValid(units)
    }

    /// IPv6 literal (Java `parseIPv6Reference`, here `inet_pton`; Java always reports the error index at the start).
    private static func isIPv6(_ text: String) -> Bool {
        var address = in6_addr()
        return inet_pton(AF_INET6, text, &address) == 1
    }

    private static func isIPv4(_ units: [UInt16]) -> Bool {
        let parts = units.split(separator: 0x2E, omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy(isDigit) else { return false }
            let value = part.reduce(0) { $0 * 10 + Int($1 - 0x30) }
            if value > 255 { return false }
        }
        return true
    }

    /// Java `parseHostname`: index where the name ends (the first character that does not belong in it, or `-` at the end of a label).
    private static func hostnameEnd(_ units: [UInt16]) -> Int {
        var p = 0
        let n = units.count
        while p < n {
            guard isAlnum(units[p]) else { break }
            var q = p + 1
            while q < n && (isAlnum(units[q]) || units[q] == 0x2D) { q += 1 }
            if units[q - 1] == 0x2D { return q - 1 }
            p = q
            guard p < n && units[p] == 0x2E else { break }
            p += 1
        }
        return p
    }

    /// Whole name: at least one label and the rightmost of several labels starts with a letter.
    private static func hostnameValid(_ units: [UInt16]) -> Bool {
        guard let first = units.first, isAlnum(first) else { return false }
        var lastLabel = 0
        for (i, u) in units.enumerated() where u == 0x2E && i + 1 < units.count {
            lastLabel = i + 1
        }
        return lastLabel == 0 || isAlpha(units[lastLabel])
    }

    private static let authorityPunctuation: [UInt16] = Array("-_.!~*'();:&=+$,@[]/?#".utf16)

    private static func isAuthorityChar(_ u: UInt16) -> Bool {
        if isAlnum(u) {
            return true
        }
        if u >= 0x80 {
            return isOtherChar(u)
        }
        // `/ ? #` end the authority in Java (the host falls apart into path/query) — here they merely do not lead to a constructor
        // error and a host with them is "unsupported URI" (a divergence for a nonsensical configuration).
        return authorityPunctuation.contains(u)
    }

    /// RFC 2396 "other" in Java: non-ASCII except control characters and spaces (`isISOControl`, `isSpaceChar`).
    private static func isOtherChar(_ u: UInt16) -> Bool {
        switch u {
        case 0x80...0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return false
        default:
            return true
        }
    }

    private static func isDigit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }
    private static func isAlpha(_ u: UInt16) -> Bool { (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) }
    private static func isAlnum(_ u: UInt16) -> Bool { isDigit(u) || isAlpha(u) }
    private static func isHex(_ u: UInt16) -> Bool { isDigit(u) || (u >= 0x41 && u <= 0x46) || (u >= 0x61 && u <= 0x66) }
}
