import Foundation

/// A minimal HTTP/1.1 server on `127.0.0.1:0` (a fldigi XML-RPC stand-in, Java `HttpServer` in
/// `FldigiClientTest`): reads the headers and the body per `Content-Length`, records the **exact bytes**
/// of the request and answers with a scripted status and body (`Connection: close`). Each connection on its own thread.
final class FakeHttpServer: @unchecked Sendable {

    struct Response: Sendable {
        var status: Int
        var contentType: String
        var body: [UInt8]
        /// A pause before the response (client timeout tests).
        var delayMs: Int
        /// Further header lines (without `\r\n`), e.g. `Location: /RPC2`.
        var headers: [String]
        /// Close the connection without a response.
        var closeWithoutReply: Bool

        init(status: Int = 200, contentType: String = "text/xml", body: String = "", delayMs: Int = 0,
             headers: [String] = [], closeWithoutReply: Bool = false) {
            self.status = status
            self.contentType = contentType
            self.body = Array(body.utf8)
            self.delayMs = delayMs
            self.headers = headers
            self.closeWithoutReply = closeWithoutReply
        }
    }

    private let lock = NSLock()
    private var response: Response
    /// A response based on the request body (Java `HttpServer` handler in `FldigiClientTest`); takes precedence over `response`.
    private var responder: (@Sendable ([UInt8]) -> Response)?
    /// A response based on the headers (request line) and body — redirection by path; takes precedence over `responder`.
    private var headResponder: (@Sendable (String, [UInt8]) -> Response)?
    private var recorded: [[UInt8]] = []
    private var listener: LoopbackListener!

    init(response: Response = Response()) throws {
        self.response = response
        listener = try LoopbackListener(name: "fake-http-server") { [weak self] connection in
            self?.serve(connection)
        }
    }

    deinit {
        listener?.stop()
    }

    var port: Int { listener.port }

    func respond(_ response: Response) {
        lock.lock()
        self.response = response
        lock.unlock()
    }

    /// Respond based on the request body.
    func respond(with responder: @escaping @Sendable (_ body: [UInt8]) -> Response) {
        lock.lock()
        self.responder = responder
        lock.unlock()
    }

    /// Respond based on the headers (including the request line) and body.
    func respond(withHead responder: @escaping @Sendable (_ head: String, _ body: [UInt8]) -> Response) {
        lock.lock()
        self.headResponder = responder
        lock.unlock()
    }

    /// The exact bytes of received requests (headers + body) in order of arrival.
    var requests: [[UInt8]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// The body of request `index` (after the empty line of the headers).
    func body(_ index: Int) -> [UInt8] {
        let all = requests
        guard all.indices.contains(index) else { return [] }
        let bytes = all[index]
        guard let end = Self.headerEnd(bytes) else { return [] }
        return Array(bytes[end...])
    }

    /// The headers of request `index` as text (including the request line).
    func head(_ index: Int) -> String {
        let all = requests
        guard all.indices.contains(index) else { return "" }
        let bytes = all[index]
        let end = Self.headerEnd(bytes) ?? bytes.count
        return String(decoding: bytes[..<end], as: UTF8.self)
    }

    func stop() {
        listener.stop()
    }

    /// Java `URLDecoder.decode(new String(bytes, UTF_8), UTF_8)` for form bodies (`+` → space, `%XX`).
    static func formDecoded(_ bytes: [UInt8]) -> String {
        let text = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "+", with: " ")
        return text.removingPercentEncoding ?? text
    }

    private func serve(_ connection: LoopbackListener.Connection) {
        var bytes: [UInt8] = []
        var expected: Int?
        while expected == nil || bytes.count < expected! {
            guard let chunk = connection.receive() else { break }
            bytes.append(contentsOf: chunk)
            if expected == nil, let end = Self.headerEnd(bytes) {
                expected = end + Self.contentLength(String(decoding: bytes[..<end], as: UTF8.self))
            }
        }
        lock.lock()
        recorded.append(bytes)
        let responder = self.responder
        let headResponder = self.headResponder
        let fixed = response
        lock.unlock()
        guard expected != nil, let end = Self.headerEnd(bytes) else { return }
        let body = Array(bytes[end...])
        let head = String(decoding: bytes[..<end], as: UTF8.self)
        let reply: Response = headResponder?(head, body) ?? responder?(body) ?? fixed
        if reply.closeWithoutReply {
            return
        }
        if reply.delayMs > 0 {
            Thread.sleep(forTimeInterval: Double(reply.delayMs) / 1_000)
        }
        let reasonText: String = Self.reason(reply.status)
        var out = "HTTP/1.1 \(reply.status) \(reasonText)\r\n"
        out += "Content-Type: " + reply.contentType + "\r\n"
        out += "Content-Length: " + String(reply.body.count) + "\r\n"
        for line in reply.headers {
            out += line + "\r\n"
        }
        out += "Connection: close\r\n\r\n"
        connection.send(Array(out.utf8) + reply.body)
    }

    /// The index of the first byte after `\r\n\r\n`.
    static func headerEnd(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for i in 0...(bytes.count - 4) where bytes[i] == 0x0D && bytes[i + 1] == 0x0A && bytes[i + 2] == 0x0D && bytes[i + 3] == 0x0A {
            return i + 4
        }
        return nil
    }

    private static func contentLength(_ head: String) -> Int {
        for line in head.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 && parts[0].lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 302: return "Found"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }
}
