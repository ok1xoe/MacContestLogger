import Foundation

/// Minimal HTTP/1.1 client over `LineSocket` — a replacement for Java `HttpClient.send` for `FldigiClient`
/// (one `POST`, the response entirely in memory). Blocking, on the caller's thread; needs no GCD, ATS or proxy.
///
/// Copies JDK 21 `jdk.internal.net.http` as far as it is reachable (measured by the maintainer-only probe,
/// rows `fl.*`, and read from the source):
/// - **Request:** `POST <path> HTTP/1.1`, `Content-Length`, `Host` (without the port only for 80), then the caller's headers,
///   an empty line, the body — order as in `Http1Request`. The h2c upgrade headers (`Connection: Upgrade, HTTP2-Settings`,
///   `HTTP2-Settings`, `Upgrade: h2c`) and `User-Agent: Java-http-client/…` are not sent (there is no HTTP/2 here).
/// - **Timeouts:** connect `connectTimeoutMs` (`HttpConnectTimeoutException: HTTP connect timed out`), from the start
///   to the end of the response headers `requestTimeoutMs` (`HttpTimeoutException: request timed out`; the Java timer is
///   cancelled after the headers — the body is read without a timeout, measured `raw.slowBody`/`raw.slowHeaders`).
/// - **Response headers:** the state machine `Http1HeaderParser` (ISO-8859-1, `\r\n` and bare `\n`, continuation lines,
///   `Invalid status line: "…"`, a status message at end of stream, e.g. `HTTP/1.1 header parser received no bytes`).
/// - **Body:** `Content-Length` (a number error → `IllegalArgumentException: For input string: "…"`, premature end →
///   `fixed content-length: n, bytes received: k`), `Transfer-Encoding: chunked`, otherwise to end of stream; 304 and 101
///   without a body; 204 does not read a body (with a declared body → `unexpected content length header with 204 response`).
///   RST in the headers = end of stream; a body read error (even RST) → the body parser's status message (`fixed content-length:
///   …`, `http1_0 content, bytes received: n`, `chunked transfer encoding, state: …`). The `chunked` block length is
///   32-bit with overflow like Java `int`; negative → error (Java loops forever; a deliberate divergence from Java v1.1.1).
/// - Outside the 3 s limit remain name resolution (`getaddrinfo` in `LineSocket.connect`) and writing the request.
/// - **Connection errors:** refused / unknown host → `ConnectException` with message `null`; another connection error →
///   `ConnectException` with the `strerror` text; port out of range → `IllegalArgumentException` from `LineSocket`.
/// - Redirects are not followed (the caller gets a 3xx response). After the exchange the connection is closed (Java keeps it in a pool).
enum JavaHttp1 {

    struct Response {
        let status: Int
        /// Names in lowercase (Java `HttpHeaders`), values in order.
        let headers: [String: [String]]
        let body: [UInt8]
    }

    static let requestTimedOut = JavaIOError("request timed out", javaClass: "java.net.http.HttpTimeoutException")
    static let connectTimedOut = JavaIOError("HTTP connect timed out", javaClass: "java.net.http.HttpConnectTimeoutException")

    /// Request bytes (`Http1Request`: line, `Content-Length`, `Host`, user headers, body).
    static func requestBytes(path: String, hostHeader: String, headers: [(String, String)], body: [UInt8]) -> [UInt8] {
        var head = "POST " + path + " HTTP/1.1\r\n"
        head += "Content-Length: " + String(body.count) + "\r\n"
        head += "Host: " + hostHeader + "\r\n"
        for (name, value) in headers {
            head += name + ": " + value + "\r\n"
        }
        head += "\r\n"
        return Array(head.utf8) + body
    }

    /// Java `Http1Request.hostString()`: the port is omitted only for the default 80 (or −1).
    static func hostHeader(host: String, port: Int) -> String {
        port == 80 || port == -1 ? host : host + ":" + String(port)
    }

    /// `host` is the address for connecting (IPv6 without brackets), `hostHeader` the value of the `Host` header.
    static func post(host: String, port: Int, hostHeader: String, path: String, headers: [(String, String)],
                     body: [UInt8], connectTimeoutMs: Int, requestTimeoutMs: Int) throws -> Response {
        let deadline = Deadline(timeoutMs: requestTimeoutMs)
        let socket: LineSocket
        do {
            socket = try LineSocket.connect(host: host, port: port, connectTimeoutMs: connectTimeoutMs,
                                            readTimeoutMs: requestTimeoutMs)
        } catch let error as JavaSocketError {
            throw connectError(error)
        }
        defer { socket.close() }
        do {
            try socket.write(requestBytes(path: path, hostHeader: hostHeader, headers: headers, body: body))
        } catch {
            throw JavaIOError(error.message)
        }

        var parser = HeaderParser()
        var leftover: [UInt8] = []
        while true {
            let remaining: Int32 = deadline.remainingMs
            if remaining == 0 {
                throw requestTimedOut
            }
            try? socket.setReadTimeout(remaining < 0 ? 0 : Int(remaining))
            guard let chunk = try readOrEOF(socket, timeout: requestTimedOut) else {
                throw JavaIOError(parser.currentStateMessage())
            }
            if let end = try parser.parse(chunk) {
                leftover = Array(chunk[end...])
                break
            }
        }
        // The Java request timer ends after the headers — body without a timeout.
        try? socket.setReadTimeout(0)
        let status: Int = parser.responseCode
        let fields: [String: [String]] = parser.headers
        if status == 204 {
            // `MultiExchange.bodyNotPermitted`: the body is not read; a declared body is an error.
            let declared: Int64 = try headerLength(fields) ?? 0
            if declared != 0 || fields["transfer-encoding"] != nil {
                throw JavaIOError("unexpected content length header with 204 response")
            }
            return Response(status: status, headers: fields, body: [])
        }
        let length: Int64 = try contentLength(status: status, headers: fields)
        let body: [UInt8]
        switch length {
        case -1: body = try readChunked(socket, leftover)
        case -2: body = try readToEnd(socket, leftover)
        default: body = try readFixed(socket, leftover, length: length)
        }
        return Response(status: status, headers: fields, body: body)
    }

    private static func connectError(_ error: JavaSocketError) -> JavaIOError {
        switch error.kind {
        case .refused, .unknownHost:
            return JavaIOError(nil, javaClass: "java.net.ConnectException")
        case .connectTimeout:
            return connectTimedOut
        default:
            return JavaIOError(error.message, javaClass: "java.net.ConnectException")
        }
    }

    /// One read; `nil` = end of stream (even RST). Timeout → `timeout`.
    private static func readOrEOF(_ socket: LineSocket, timeout: JavaIOError?) throws -> [UInt8]? {
        do {
            return try socket.readBytes()
        } catch {
            switch error.kind {
            case .reset:
                return nil
            case .readTimeout:
                throw timeout ?? JavaIOError(error.message)
            default:
                throw JavaIOError(error.message)
            }
        }
    }

    /// Java `firstValueAsLong("Content-Length")`: `nil` without the header, a number error → `IllegalArgumentException`.
    static func headerLength(_ headers: [String: [String]]) throws -> Int64? {
        guard let text = headers["content-length"]?.first else { return nil }
        do {
            return try JavaInteger.parseLong(text)
        } catch {
            throw JavaIllegalArgumentError(message: error.message)
        }
    }

    /// Java `fixupContentLen`: length, −1 = chunked, −2 = to end of stream.
    static func contentLength(status: Int, headers: [String: [String]]) throws -> Int64 {
        let length: Int64 = try headerLength(headers) ?? -1
        if status == 304 {
            return 0
        }
        if length == -1 {
            if let te = headers["transfer-encoding"]?.first, te.lowercased() == "chunked" {
                return -1
            }
            return status == 101 ? 0 : -2
        }
        return length < 0 ? -2 : length
    }

    /// Body read (without a timeout): `nil` = end of stream. A read error (even RST) → `JavaIOError(state())` — Java
    /// `wrapWithExtraDetail` gives the exception the body parser's status message (measured `raw.resetInBody`, `raw.resetNoLength`).
    private static func readBody(_ socket: LineSocket, state: () -> String) throws -> [UInt8]? {
        do {
            return try socket.readBytes()
        } catch {
            throw JavaIOError(state())
        }
    }

    private static func readFixed(_ socket: LineSocket, _ start: [UInt8], length: Int64) throws -> [UInt8] {
        var body: [UInt8] = Array(start.prefix(Int(clamping: length)))
        func state() -> String {
            "fixed content-length: " + String(length) + ", bytes received: " + String(body.count)
        }
        while Int64(body.count) < length {
            guard let chunk = try readBody(socket, state: state) else {
                throw JavaIOError(state())
            }
            body.append(contentsOf: chunk.prefix(Int(clamping: length - Int64(body.count))))
        }
        return body
    }

    private static func readToEnd(_ socket: LineSocket, _ start: [UInt8]) throws -> [UInt8] {
        var body = start
        func state() -> String {
            "http1_0 content, bytes received: " + String(body.count)
        }
        while let chunk = try readBody(socket, state: state) {
            body.append(contentsOf: chunk)
        }
        return body
    }

    /// `ResponseContent.ChunkedBodyParser`: length in hexadecimal (extensions after it are skipped up to CR), `CR LF`, data,
    /// two bytes (not checked), the last block 0 + two bytes.
    private static func readChunked(_ socket: LineSocket, _ start: [UInt8]) throws -> [UInt8] {
        var input = start
        var index = 0
        var state = "READING_LENGTH"
        func next() throws -> UInt8 {
            while index >= input.count {
                guard let chunk = try readBody(socket, state: { "chunked transfer encoding, state: " + state }) else {
                    throw JavaIOError("chunked transfer encoding, state: " + state)
                }
                input = chunk
                index = 0
            }
            let b = input[index]
            index += 1
            return b
        }
        var body: [UInt8] = []
        while true {
            state = "READING_LENGTH"
            // Java `int partialChunklen`: 32-bit with overflow (`100000000` → 0 = the last block).
            var length: Int32 = 0
            var digits = 0
            var extensions = 0
            var cr = false
            while true {
                if extensions + digits >= 2_050 {
                    throw JavaIOError("Chunk header size too long: " + String(extensions + digits))
                }
                let c: UInt8 = try next()
                if cr {
                    if c == 0x0A { break }
                    throw JavaIOError("invalid chunk header")
                }
                if c == 0x0D {
                    cr = true
                } else if extensions > 0 {
                    extensions += 1
                } else if let digit = hexDigit(c) {
                    digits += 1
                    length = length &* 16 &+ Int32(digit)
                } else if digits > 0 {
                    extensions += 1
                } else {
                    throw JavaIOError("Illegal character in chunk size: " + String(Int8(bitPattern: c)))
                }
            }
            if length == 0 {
                _ = try next()
                _ = try next()
                return body
            }
            if length < 0 {
                // Java loops here (`READMORE` without consuming input) — Swift throws an error instead (a deliberate divergence from Java v1.1.1).
                throw JavaIOError("chunked transfer encoding, negative chunk size: " + String(length))
            }
            state = "READING_DATA"
            for _ in 0..<length {
                body.append(try next())
            }
            _ = try next()
            _ = try next()
        }
    }

    private static func hexDigit(_ b: UInt8) -> Int? {
        switch b {
        case 0x30...0x39: return Int(b - 0x30)
        case 0x41...0x46: return Int(b - 0x41 + 10)
        case 0x61...0x66: return Int(b - 0x61 + 10)
        default: return nil
        }
    }

    /// Port of Java `Http1HeaderParser` (JDK 21) including status messages.
    struct HeaderParser {
        enum State: String {
            case initial = "INITIAL"
            case statusLine = "STATUS_LINE"
            case statusLineFoundCR = "STATUS_LINE_FOUND_CR"
            case statusLineFoundLF = "STATUS_LINE_FOUND_LF"
            case statusLineEnd = "STATUS_LINE_END"
            case statusLineEndCR = "STATUS_LINE_END_CR"
            case statusLineEndLF = "STATUS_LINE_END_LF"
            case header = "HEADER"
            case headerFoundCR = "HEADER_FOUND_CR"
            case headerFoundLF = "HEADER_FOUND_LF"
            case headerFoundCRLF = "HEADER_FOUND_CR_LF"
            case headerFoundCRLFCR = "HEADER_FOUND_CR_LF_CR"
            case finished = "FINISHED"
        }

        private(set) var state: State = .initial
        private var sb: [UInt16] = []
        private(set) var statusLine = ""
        private(set) var responseCode = 0
        private(set) var headers: [String: [String]] = [:]

        private static let cr: UInt16 = 0x0D
        private static let lf: UInt16 = 0x0A
        private static let ht: UInt16 = 0x09
        private static let sp: UInt16 = 0x20

        private var text: String { String(decoding: sb, as: UTF16.self) }

        /// Java `currentStateMessage()`.
        func currentStateMessage() -> String {
            let name = state.rawValue
            let message: String
            if name.contains("INITIAL") {
                return "HTTP/1.1 header parser received no bytes"
            } else if name.contains("STATUS") {
                message = "parsing HTTP/1.1 status line, receiving [" + text + "]"
            } else if name.contains("HEADER") {
                var headerName = text
                if let colon = headerName.firstIndex(of: ":") {
                    headerName = String(headerName[...colon]) + "..."
                }
                message = "parsing HTTP/1.1 header, receiving [" + headerName + "]"
            } else {
                message = "HTTP/1.1 parser receiving [" + text + "]"
            }
            return message + ", parser state [" + name + "]"
        }

        /// Processes bytes; returns the index of the first byte after the headers, or `nil` (more data needed).
        mutating func parse(_ input: [UInt8]) throws(JavaIOError) -> Int? {
            var i = 0
            func get() -> UInt16 {
                let c = UInt16(input[i])
                i += 1
                return c
            }
            while true {
                switch state {
                case .finished:
                    return i
                case .statusLineFoundLF, .statusLineEndLF, .headerFoundLF:
                    break
                default:
                    if i >= input.count { return nil }
                }
                switch state {
                case .initial:
                    state = .statusLine
                case .statusLine:
                    var c: UInt16 = 0
                    while i < input.count {
                        c = get()
                        if c == Self.cr || c == Self.lf { break }
                        sb.append(c)
                    }
                    if c == Self.cr {
                        state = .statusLineFoundCR
                    } else if c == Self.lf {
                        state = .statusLineFoundLF
                    }
                case .statusLineFoundCR, .statusLineFoundLF:
                    let c: UInt16 = state == .statusLineFoundLF ? Self.lf : get()
                    if c != Self.lf {
                        throw Self.protocolError("Bad trailing char, \"" + String(decoding: [c], as: UTF16.self)
                            + "\", when parsing status line, \"" + text + "\"")
                    }
                    statusLine = text
                    sb = []
                    try checkStatusLine()
                    state = .statusLineEnd
                case .statusLineEnd:
                    let c = get()
                    if c == Self.cr {
                        state = .statusLineEndCR
                    } else if c == Self.lf {
                        state = .statusLineEndLF
                    } else {
                        sb.append(c)
                        state = .header
                    }
                case .statusLineEndCR, .statusLineEndLF:
                    let c: UInt16 = state == .statusLineEndLF ? Self.lf : get()
                    if c == Self.lf {
                        state = .finished
                    } else {
                        throw Self.protocolError("Unexpected \"" + String(decoding: [c], as: UTF16.self)
                            + "\", after status line CR")
                    }
                case .header:
                    while i < input.count {
                        var c = get()
                        if c == Self.cr {
                            state = .headerFoundCR
                            break
                        } else if c == Self.lf {
                            state = .headerFoundLF
                            break
                        }
                        if c == Self.ht { c = Self.sp }
                        sb.append(c)
                    }
                case .headerFoundCR, .headerFoundLF:
                    let c: UInt16 = state == .headerFoundLF ? Self.lf : get()
                    if c == Self.lf {
                        state = .headerFoundCRLF
                    } else if c == Self.sp || c == Self.ht {
                        sb.append(Self.sp)
                        state = .header
                    } else {
                        sb = [c]
                        state = .header
                    }
                case .headerFoundCRLF:
                    let c = get()
                    if c == Self.cr || c == Self.lf {
                        try flushHeader()
                        state = c == Self.cr ? .headerFoundCRLFCR : .finished
                    } else if c == Self.sp || c == Self.ht {
                        sb.append(Self.sp)
                        state = .header
                    } else {
                        try flushHeader()
                        sb.append(c)
                        state = .header
                    }
                case .headerFoundCRLFCR:
                    let c = get()
                    if c == Self.lf {
                        state = .finished
                    } else {
                        throw Self.protocolError("Unexpected \"" + String(decoding: [c], as: UTF16.self)
                            + "\", after CR LF CR")
                    }
                case .finished:
                    return i
                }
            }
        }

        private mutating func checkStatusLine() throws(JavaIOError) {
            let invalid = Self.protocolError("Invalid status line: \"" + statusLine + "\"")
            let units = Array(statusLine.utf16)
            guard units.starts(with: "HTTP/1.".utf16), units.count >= 12 else { throw invalid }
            guard let code = JavaInteger.parseInt(String(decoding: units[9..<12], as: UTF16.self)), code >= 100 else {
                throw invalid
            }
            responseCode = Int(code)
        }

        private mutating func flushHeader() throws(JavaIOError) {
            guard !sb.isEmpty else { return }
            let line = text
            sb = []
            guard let colon = line.firstIndex(of: ":") else { return }
            let name = String(line[..<colon])
            if name.isEmpty { return }
            let value = JavaText.trim(String(line[line.index(after: colon)...]))
            headers[name.lowercased(), default: []].append(value)
        }

        private static func protocolError(_ message: String) -> JavaIOError {
            JavaIOError(message, javaClass: "java.net.ProtocolException")
        }
    }
}
