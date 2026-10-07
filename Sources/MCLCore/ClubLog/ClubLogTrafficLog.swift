import Darwin
import Foundation
import os

/// Traffic log of everything the app sends to Club Log (`clublog.log` in the data folder), in the style of
/// `CatTrafficLog`: `HH:mm:ss.SSS` (local time) + two spaces + `→` (sent) / `←` (received) / `·` (note) + text.
///
/// **Secrets never reach the file:** the application password and the API key are written as `***`, the e-mail as
/// `t***@example.com`; error and response texts are scrubbed of the secret values too. The file is created by the
/// first line written (nothing is written, and no file exists, while Club Log is unused). A file error is ignored —
/// a log must never break an upload. Thread-safe (the upload lane, the cty download and the model write from
/// different threads); no rotation, like `cat.log`.
public final class ClubLogTrafficLog: Sendable {

    /// The shared instance; without `setFile` it writes nothing (tests, the inert app).
    public static let shared = ClubLogTrafficLog()

    /// Longest response body kept in a line.
    public static let maxBodyLength = 200

    private let clock: @Sendable () -> Date
    private let file = OSAllocatedUnfairLock<URL?>(initialState: nil)
    /// Serialises the writes so the lines of two threads do not interleave.
    private let writing = OSAllocatedUnfairLock()

    public init(file: URL? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
        self.file.withLock { $0 = file }
    }

    /// Sets the file to append to (`nil` = log nothing); the folder is created on the first write.
    public func setFile(_ url: URL?) {
        file.withLock { $0 = url }
    }

    // MARK: - realtime.php

    /// `→ POST <url>` and the form fields, the secrets masked; the ADIF record in clear text on one line.
    public func upload(url: String, email: String?, callsign: String?, adif: String?) {
        write("\u{2192} POST " + url)
        write("\u{2192} email=" + Self.maskEmail(email) + " password=*** api=*** callsign=" + Self.oneLine(callsign ?? ""))
        write("\u{2192} adif=" + Self.oneLine(adif ?? ""))
    }

    /// `← HTTP <status>` and the first line of the body (≤ `maxBodyLength`).
    public func response(status: Int, body: Data, secrets: [String]) {
        let text = Self.scrub(String(decoding: body, as: UTF8.self), secrets)
        write("\u{2190} HTTP \(status)" + (text.isEmpty ? "" : " " + Self.firstLine(text)))
    }

    /// The network error instead of a response.
    public func failure(_ message: String, secrets: [String]) {
        write("\u{00B7} error: " + Self.firstLine(Self.scrub(message, secrets)))
    }

    /// A note (the outcome of the attempt).
    public func note(_ text: String) {
        write("\u{00B7} " + Self.oneLine(text))
    }

    // MARK: - cty.xml

    /// `→ GET <url>` with the `api` value masked.
    public func ctyRequest(url: URL) {
        write("\u{2192} GET " + Self.maskApi(url.absoluteString))
    }

    public func ctyResponse(status: Int, bytes: Int) {
        write("\u{2190} HTTP \(status), \(bytes) bytes")
    }

    // MARK: - text helpers

    /// `t***@example.com`; no `@` → `***`; empty → empty.
    static func maskEmail(_ email: String?) -> String {
        guard let email, !email.isEmpty else { return "" }
        guard let at = email.lastIndex(of: "@"), at > email.startIndex else { return "***" }
        return String(email[email.startIndex]) + "***" + email[at...]
    }

    /// The value of `api=` in a URL → `***`.
    static func maskApi(_ url: String) -> String {
        guard let range = url.range(of: "api=") else { return url }
        let valueStart = range.upperBound
        let end = url[valueStart...].firstIndex(of: "&") ?? url.endIndex
        return String(url[..<valueStart]) + "***" + url[end...]
    }

    static func scrub(_ text: String, _ secrets: [String]) -> String {
        var result = text
        for secret in secrets where !secret.isEmpty {
            result = result.replacingOccurrences(of: secret, with: "***")
            result = result.replacingOccurrences(of: JavaUrlEncoder.encode(secret), with: "***")
        }
        return result
    }

    static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    static func firstLine(_ text: String) -> String {
        let trimmed = JavaText.trim(text)
        let line = trimmed.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? ""
        return line.count > maxBodyLength ? String(line.prefix(maxBodyLength)) + "…" : line
    }

    // MARK: - file

    private func write(_ body: String) {
        guard let url = file.withLock({ $0 }) else { return }
        let line = CatTrafficLog.timestamp(clock(), timeZone: TimeZone.current) + "  " + body + "\n"
        writing.withLock {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let fd = url.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o666) }
                guard fd >= 0 else { return }
                defer { Darwin.close(fd) }
                let bytes = Array(line.utf8)
                var offset = 0
                while offset < bytes.count {
                    let n = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
                    if n < 0 {
                        if errno == EINTR { continue }
                        return
                    }
                    offset += n
                }
            } catch {
                return
            }
        }
    }
}
