import Darwin
import Foundation

/// Java `SerialPortInvalidPortException` (jSerialComm, `RuntimeException`) from `SerialPort.getCommPort`:
/// the port path does not exist. `message` verbatim (it goes to the status line).
public struct SerialPortInvalidPortError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public var description: String { message }
}

/// Port path selection like jSerialComm 2.11 `SerialPort.getCommPort(descriptor)` (macOS branch) — the callers
/// (`WinkeyerKeyer.open`, `Otrsp.open`, `Footswitch.open`) call it before opening and report open errors with
/// their own texts with the **original** path (maintainer-only probe, rows `ser.*`):
///
/// 1. `~/…` → home directory;
/// 2. if the last component is a symbolic link → canonical path (`/tmp/x → /dev/null` opens `/dev/null`);
/// 3. otherwise, if the path does not exist, `/dev/<path>` is tried and then `/dev/<last component>`
///    (`cu.X` → `/dev/cu.X`, `null` → `/dev/null`, `""` → `/dev/`); if neither exists →
///    `SerialPortInvalidPortError("Unable to create a serial port object from the invalid port descriptor:
///    <last tried>")` — a disconnected USB adapter thus does **not** report "nelze otevřít port", but this error.
///
/// Existence and links like `java.io.File` (normalisation of `//` and a trailing `/`, `stat` through links, canonicalisation
/// like JDK `canonicalize`: `realpath`, for a non-existent path the canonical longest existing ancestor + the rest).
/// Only reads the file system, opens nothing.
enum SerialPortDescriptor {

    static func resolve(_ descriptor: String) throws(SerialPortInvalidPortError) -> String {
        try resolve(descriptor, home: NSHomeDirectory(), cwd: FileManager.default.currentDirectoryPath)
    }

    static func resolve(_ descriptor: String, home: String, cwd: String) throws(SerialPortInvalidPortError) -> String {
        var path = descriptor
        if path.hasPrefix("~/") {
            path = home + String(path.dropFirst())
        }
        if isSymbolicLink(path, cwd: cwd) {
            return canonical(absolute(normalize(path), cwd: cwd))
        }
        if !exists(path, cwd: cwd) {
            path = "/dev/" + path
            if !exists(path, cwd: cwd) {
                let last = path.lastIndex(of: "/").map { path.index(after: $0) } ?? path.startIndex
                path = "/dev/" + String(path[last...])
            }
            if !exists(path, cwd: cwd) {
                throw SerialPortInvalidPortError(
                    message: "Unable to create a serial port object from the invalid port descriptor: " + path)
            }
        }
        return path
    }

    /// Java `new File(p).getPath()`: merges repeated `/` and removes a trailing `/` (except the root).
    static func normalize(_ path: String) -> String {
        var out = ""
        var previousSlash = false
        for ch in path {
            if ch == "/" {
                if previousSlash { continue }
                previousSlash = true
            } else {
                previousSlash = false
            }
            out.append(ch)
        }
        if out.count > 1 && out.hasSuffix("/") {
            out.removeLast()
        }
        return out
    }

    /// Java `File.getAbsolutePath()` (relative to `user.dir`).
    static func absolute(_ normalized: String, cwd: String) -> String {
        if normalized.hasPrefix("/") {
            return normalized
        }
        if normalized.isEmpty {
            return cwd
        }
        return normalize(cwd + "/" + normalized)
    }

    /// Java `File.exists()` (an empty path does not exist; `stat` through links).
    static func exists(_ path: String, cwd: String) -> Bool {
        let normalized = normalize(path)
        if normalized.isEmpty {
            return false
        }
        var info = stat()
        return stat(absolute(normalized, cwd: cwd), &info) == 0
    }

    /// jSerialComm `isSymbolicLink(File)`: canonical parent + name, then comparing the canonical and absolute path.
    static func isSymbolicLink(_ path: String, cwd: String) -> Bool {
        let normalized = normalize(path)
        guard let slash = normalized.lastIndex(of: "/") else {
            // No parent: the file itself (relative) — canonical vs. absolute path.
            let abs = absolute(normalized, cwd: cwd)
            return canonical(abs) != abs
        }
        let parent: String = slash == normalized.startIndex ? "/" : String(normalized[..<slash])
        let name = String(normalized[normalized.index(after: slash)...])
        let canonicalParent: String = canonical(absolute(parent, cwd: cwd))
        let file: String = canonicalParent == "/" ? "/" + name : canonicalParent + "/" + name
        return canonical(file) != file
    }

    /// JDK `UnixFileSystem.canonicalize` over an absolute path: merges `.`/`..`, `realpath`; if it fails,
    /// canonicalises the longest existing ancestor and appends the rest.
    static func canonical(_ absolutePath: String) -> String {
        var parts: [Substring] = []
        for part in absolutePath.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." {
                continue
            }
            if part == ".." {
                _ = parts.popLast()
                continue
            }
            parts.append(part)
        }
        var cut = parts.count
        while cut >= 0 {
            let head = "/" + parts[..<cut].joined(separator: "/")
            if let real = realPath(head) {
                let rest = parts[cut...].joined(separator: "/")
                if rest.isEmpty {
                    return real
                }
                return real == "/" ? "/" + rest : real + "/" + rest
            }
            cut -= 1
        }
        return "/" + parts.joined(separator: "/")
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else {
            return nil
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

extension SerialPort {

    /// Java `SerialPort.getCommPort(portPath)` + `setComPortParameters` + `openPort()`: the path per
    /// `SerialPortDescriptor` (error `SerialPortInvalidPortError` as in Java), then opening; **`nil`** if
    /// opening fails (Java `openPort() == false` — Java does not report the reason, the caller throws its own text).
    static func openLikeJSerialComm(portPath: String, settings: Settings, modem: any ModemControl)
        throws(SerialPortInvalidPortError) -> SerialPort? {
        let path: String = try SerialPortDescriptor.resolve(portPath)
        return try? open(path: path, settings: settings, modem: modem)
    }
}
