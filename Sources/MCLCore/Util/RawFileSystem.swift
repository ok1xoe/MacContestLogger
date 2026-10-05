import Foundation

/// A file path as **raw bytes**, as returned by `readdir` or as
/// passed in — without going through `URL(fileURLWithPath:)`, which converts the name
/// to NFD (`é.yaml` → `e\u{301}.yaml`) and on a normalization-sensitive volume (SMB, NFS, FAT) would then
/// open a different file than Java, or
/// none. The bytes go unchanged to `open()` and to error messages.
struct RawPath: Sendable, Equatable {
    /// Path bytes without the trailing zero.
    let bytes: [UInt8]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    init(_ path: String) {
        self.bytes = Array(path.utf8)
    }

    /// Path for messages — Java's `Path.toString()` (invalid UTF-8 is replaced
    /// with U+FFFD, like Java's decoding of file names).
    var display: String { String(decoding: bytes, as: UTF8.self) }
}

/// Files and directories via POSIX the way Java's `java.nio.file` handles them
/// (`Files.isDirectory`, `Files.list`, `Files.newInputStream`, `Path.resolve`).
///
/// Shared by `MultiplierSetRegistry.loadDir` and `ContestCatalog.fromDir` so that
/// file selection and order are the same in both places as in Java:
/// - `readdir`, not `FileManager.contentsOfDirectory` — that **omits** a hidden AppleDouble
///   `._x.yaml` next to `x.yaml` (measured), Java sees it,
/// - names as raw bytes, a case-sensitive `.yaml` filter
///   and ordering **by unsigned bytes** (`Path.compareTo`) — never Swift's
///   `<`/`hasSuffix` with canonical equivalence,
/// - the directory path **as passed in**: a relative one stays relative
///   and `..` is not resolved (Java `Path` is not canonicalized).
enum RawFileSystem {

    /// Java `Path` from a `URL`: a relative path stays relative (`rel/dir`),
    /// an absolute one unchanged (`..` stays), only with `UnixPath` normalization
    /// (`javaPath(_:)`).
    ///
    /// `URL(fileURLWithPath: "rel/dir")` carries the current directory as its base
    /// and its `path` returns an absolute path with `..` resolved (measured);
    /// `relativePath` returns the given text. When the base is a directory other than the
    /// current one, `relativePath` would point elsewhere, hence `path` is used.
    ///
    /// Note: `URL(fileURLWithPath:)` converts names to NFD already at construction
    /// (also `relativePath`), so a directory passed by the caller as a `URL` carries NFD
    /// bytes. On APFS/HFS+ that does not matter (lookup is normalization-insensitive);
    /// file names **inside** the directory do not go through this path.
    static func javaPath(of url: URL) -> String {
        let text: String
        if let base = url.baseURL, base.path != FileManager.default.currentDirectoryPath {
            text = url.path
        } else {
            text = url.relativePath
        }
        return javaPath(text)
    }

    /// Normalization when building a Java `UnixPath`: merges repeated `/`
    /// and removes trailing `/` (except the root itself). Nothing more.
    static func javaPath(_ path: String) -> String {
        var out = ""
        var previousSlash = false
        for scalar in path.unicodeScalars {
            if scalar == "/" {
                if previousSlash { continue }
                previousSlash = true
            } else {
                previousSlash = false
            }
            out.unicodeScalars.append(scalar)
        }
        if out.unicodeScalars.count > 1 && out.unicodeScalars.last == "/" {
            out.unicodeScalars.removeLast()
        }
        return out
    }

    /// Java `baseDir.resolve(other)` for `UnixPath`: an absolute `other`
    /// wins, an empty one gives `baseDir`; the result without canonicalization (`..` stays).
    static func resolve(_ baseDir: String, _ other: String) -> String {
        if other.isEmpty { return baseDir }
        if other.utf8.first == UInt8(ascii: "/") { return javaPath(other) }
        return javaPath(baseDir + "/" + other)
    }

    /// Java `Files.isDirectory(path)` — `stat` follows symbolic links;
    /// a missing path and a `stat` error give `false`.
    static func isDirectory(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFDIR
    }

    /// Java `Files.createDirectories` from the top down (shared by `DefinitionUpdater` and `ScpDownloader`):
    /// an existing directory is fine, missing links are created by `mkdir(0777)`. Returns `nil`, or
    /// the path link and `errno` at which it failed — a file at the last link gives `EEXIST`,
    /// a file higher in the path gives `ENOTDIR` at the following link. The caller composes the error text (the shape of the Java
    /// exception differs). A relative path is composed relatively (without a leading `/`).
    ///
    /// `CallHistory.save` has its own, more faithful variant of the JDK 21 algorithm (first `dir` itself, then the nearest
    /// existing ancestor via `access`) — measured by the error texts of the `callhistory/` probe.
    static func createDirectories(_ directory: String) -> (path: String, errno: Int32)? {
        if isDirectory(directory) { return nil }
        let absolute: Bool = directory.utf8.first == UInt8(ascii: "/")
        let parts = directory.split(separator: "/", omittingEmptySubsequences: true)
        var prefix: String? = absolute ? "" : nil
        for (index, part) in parts.enumerated() {
            let current: String = prefix.map { $0 + "/" + part } ?? String(part)
            prefix = current
            let isLast: Bool = index == parts.count - 1
            var info = stat()
            if stat(current, &info) == 0 && (isDirectory(current) || !isLast) { continue }
            if mkdir(current, 0o777) != 0 {
                let code: Int32 = errno
                if code == EEXIST && isDirectory(current) { continue }
                return (current, code)
            }
        }
        return nil
    }

    /// Directory entry names as raw bytes (without `.` and `..`), including
    /// hidden ones, in `readdir` order; `nil` when the directory cannot be opened
    /// (Java `Files.list` → `IOException`).
    ///
    /// A `readdir` error in the middle of a listing (Java: `IOException`) is not distinguished from
    /// the end of the listing — practically unreachable.
    static func listDirectory(_ path: String) -> [[UInt8]]? {
        guard let directory = opendir(path) else { return nil }
        defer { closedir(directory) }
        var names: [[UInt8]] = []
        while let entry = readdir(directory) {
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafeBytes(of: entry.pointee.d_name) { Array($0.prefix(length)) }
            if name == [0x2E] || name == [0x2E, 0x2E] { continue }
            names.append(name)
        }
        return names
    }

    /// Java `Files.list(dir).filter(p -> name.endsWith(".yaml")).sorted()`:
    /// non-recursive, including hidden files and subdirectories named `*.yaml`, a case-sensitive
    /// filter, order by name bytes (whole paths have a
    /// common prefix, so name order = `Path.compareTo` order).
    /// Entry path = `dir.resolve(name)` with the raw bytes of the name.
    /// `nil` when the directory cannot be traversed.
    static func yamlFiles(in directory: String) -> [RawPath]? {
        guard let names = listDirectory(directory) else { return nil }
        let suffix = Array(".yaml".utf8)
        var prefix = Array(directory.utf8)
        if prefix.last != UInt8(ascii: "/") { prefix.append(UInt8(ascii: "/")) }
        return names
            .filter { $0.suffix(suffix.count).elementsEqual(suffix) }
            .sorted { $0.lexicographicallyPrecedes($1) }
            .map { RawPath(bytes: prefix + $0) }
    }

    /// Result of reading a file, distinguished as in Java: an **open** error
    /// (`Files.newInputStream` → `IOException`, the loader reports the path) versus
    /// a **read** error of an open file (a directory opens in Java and fails only at
    /// `read` inside Jackson — "Is a directory").
    enum ReadResult {
        case data(Data)
        case openFailed
        case readFailed(String)
    }

    /// Reads a whole file via POSIX `open`/`read` (Foundation
    /// `FileHandle(forReadingFrom:)` rejects a directory already at open).
    static func readFile(_ path: RawPath) -> ReadResult {
        let descriptor = (path.bytes + [0]).withUnsafeBufferPointer { buffer in
            buffer.withMemoryRebound(to: CChar.self) { open($0.baseAddress!, O_RDONLY | O_CLOEXEC) }
        }
        guard descriptor >= 0 else { return .openFailed }
        defer { close(descriptor) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                return .readFailed(String(cString: strerror(errno)))
            }
            data.append(contentsOf: buffer[0..<count])
        }
        return .data(data)
    }

    /// Which step of the atomic write failed and with what `errno`. The caller
    /// composes the message text — `DefinitionEditing.save` and `DefinitionUpdater` each
    /// have their own (`save` error texts).
    enum AtomicWriteFailure: Error {
        /// `mkstemps` did not create a temporary file in the directory.
        case createTemporary(errno: Int32)
        /// Writing to the temporary file or its `close` failed.
        case write(temporary: String, errno: Int32)
        /// `rename` of the temporary file over the target failed.
        case rename(temporary: String, errno: Int32)
    }

    /// Writes `bytes` to `target` **atomically**: a temporary file
    /// `<directory>/<prefix>XXXXXXXXXX<suffix>` (`mkstemps`, permissions 0600 like Java's
    /// `Files.createTempFile`, the target carries them after the move), writing of everything
    /// (`EINTR` is retried), `close` and `rename` over the target. The temporary file
    /// does not remain after an error. Shared by `DefinitionEditing.save`, `DefinitionUpdater`,
    /// `CallHistory.save` (`callhistory<n>.tmp`) and `ScpDownloader` (`master<n>.scp.part`).
    ///
    /// Measured against Java (`AtomicWriteTests`, maintainer-only probe):
    /// the target has **always 0600** after writing — even if it previously had 0644 or 0777;
    /// a symbolic link at the target is replaced by a file (its target stays);
    /// a directory at the target is rejected by `rename` (Java `FileSystemException`).
    /// The `directory` directory must exist — Java's `Files.createDirectories` is done by the caller.
    /// `fsync` is deliberately not done — Java (`Files.write` + `Files.move`) does not call it either; after a system crash
    /// the old content may remain, not a half-written file.
    static func writeAtomically(_ bytes: [UInt8], to target: String, temporaryIn directory: String,
                                prefix: String, suffix: String = ".tmp") throws(AtomicWriteFailure) {
        var template = Array(resolve(directory, prefix + "XXXXXXXXXX" + suffix).utf8CString)
        let descriptor = template.withUnsafeMutableBufferPointer {
            mkstemps($0.baseAddress!, Int32(suffix.utf8.count))
        }
        guard descriptor >= 0 else {
            throw .createTemporary(errno: errno)
        }
        let temporary = template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        defer { unlink(temporary) }
        var written = 0
        while written < bytes.count {
            let count = bytes[written...].withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                let code = errno
                close(descriptor)
                throw .write(temporary: temporary, errno: code)
            }
            written += count
        }
        guard close(descriptor) == 0 else {
            throw .write(temporary: temporary, errno: errno)
        }
        guard rename(temporary, target) == 0 else {
            throw .rename(temporary: temporary, errno: errno)
        }
    }
}
