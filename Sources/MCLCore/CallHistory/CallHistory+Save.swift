import Foundation

/// `CallHistory.save` error — Java `IOException` from `java.nio.file`: the class name and `getMessage()`
/// (which the UI shows in the status line "Uložení call history selhalo: …").
public struct CallHistorySaveError: Error, Equatable, Sendable {
    /// Simple name of the Java exception (`FileSystemException`, `AccessDeniedException`…).
    public let exception: String
    public let message: String

    public init(exception: String, message: String) {
        self.exception = exception
        self.message = message
    }

    /// `UnixException.translateToIOException(file, other)` (JDK 21): `EACCES`, `ENOENT`, `EEXIST`
    /// have their own class without a reason, the others `FileSystemException` with the `strerror` text.
    /// `getMessage()` = `file[ -> other][: reason]`.
    static func posix(_ code: Int32, file: String, other: String? = nil) -> CallHistorySaveError {
        let target: String = other.map { "\(file) -> \($0)" } ?? file
        switch code {
        case EACCES:
            return CallHistorySaveError(exception: "AccessDeniedException", message: target)
        case ENOENT:
            return CallHistorySaveError(exception: "NoSuchFileException", message: target)
        case EEXIST:
            return CallHistorySaveError(exception: "FileAlreadyExistsException", message: target)
        case ELOOP:
            let reason = "\(String(cString: strerror(code))) or unable to access attributes of symbolic link"
            return CallHistorySaveError(exception: "FileSystemException", message: "\(target): \(reason)")
        default:
            return CallHistorySaveError(exception: "FileSystemException",
                                        message: "\(target): \(String(cString: strerror(code)))")
        }
    }
}

extension CallHistory {

    /// Saves atomically (a temporary file `callhistory<n>.tmp` in the same directory + `rename`), like
    /// Java `save`: `Files.createDirectories` of the parent directory, each line of `toLines()` + `\n`
    /// (the last one too) in UTF-8, the target has permissions **0600** after the move (Java `createTempFile`). The temporary
    /// file does not remain after an error.
    ///
    /// Error texts like Java `getMessage()` (measured: the parent is a file, a read-only directory, the target
    /// is a non-empty directory); instead of the random number of the temporary file the message has the template
    /// `callhistoryXXXXXXXXXX.tmp`.
    public func save(_ path: String) throws(CallHistorySaveError) {
        let file: String = RawFileSystem.javaPath(path)
        let absolute: String = file.utf8.first == UInt8(ascii: "/")
            ? file : RawFileSystem.resolve(FileManager.default.currentDirectoryPath, file)
        guard let directory = Self.parent(absolute) else {
            throw CallHistorySaveError(exception: "NullPointerException", message: "")
        }
        try Self.createDirectories(directory)
        var text = ""
        for line in toLines() {
            text += line
            text += "\n"
        }
        do {
            try RawFileSystem.writeAtomically(Array(text.utf8), to: file, temporaryIn: directory,
                                              prefix: "callhistory", suffix: ".tmp")
        } catch {
            let template: String = RawFileSystem.resolve(directory, "callhistoryXXXXXXXXXX.tmp")
            switch error {
            case .createTemporary(let code):
                throw .posix(code, file: template)
            case .write(_, let code):
                throw CallHistorySaveError(exception: "IOException", message: String(cString: strerror(code)))
            case .rename(_, let code):
                if code == EXDEV {
                    let reason = String(cString: strerror(code))
                    throw CallHistorySaveError(exception: "AtomicMoveNotSupportedException",
                                               message: "\(template) -> \(file): \(reason)")
                }
                throw .posix(code, file: template, other: file)
            }
        }
    }

    /// Java `Path.getParent()` of an absolute path; the root has no parent.
    static func parent(_ absolute: String) -> String? {
        let units: [UInt8] = Array(absolute.utf8)
        guard let slash = units.lastIndex(of: UInt8(ascii: "/")), units.count > 1 else { return nil }
        if slash == 0 { return "/" }
        return String(decoding: units[..<slash], as: UTF8.self)
    }

    /// Java `Files.createDirectories(dir)` (JDK 21): first tries to create `dir` itself (an existing
    /// directory is fine, an existing file is `FileAlreadyExistsException`); otherwise finds the nearest
    /// existing ancestor (`access(F_OK)`) and creates the rest component by component.
    static func createDirectories(_ directory: String) throws(CallHistorySaveError) {
        do {
            try createAndCheckIsDirectory(directory)
            return
        } catch {
            if error.exception == "FileAlreadyExistsException" {
                throw error
            }
        }
        var existing: String? = parent(directory)
        while let candidate = existing {
            if access(candidate, F_OK) == 0 {
                break
            }
            let code = errno
            if code != ENOENT {
                throw .posix(code, file: candidate)
            }
            existing = parent(candidate)
        }
        guard let base = existing else {
            throw CallHistorySaveError(exception: "FileSystemException",
                                       message: "\(directory): Unable to determine if root directory exists")
        }
        // By UTF-8 bytes, not by graphemes: `/` + a combining character is one character in a Swift `String`.
        let skip: Int = base == "/" ? 1 : base.utf8.count + 1
        let rest: ArraySlice<UInt8> = Array(directory.utf8).dropFirst(skip)
        var child: String = base
        for name in rest.split(separator: UInt8(ascii: "/"), omittingEmptySubsequences: true) {
            child = RawFileSystem.resolve(child, String(decoding: name, as: UTF8.self))
            try createAndCheckIsDirectory(child)
        }
    }

    /// `mkdir(dir, 0777)`; `EEXIST` for a directory (also through a symbolic link) is fine.
    private static func createAndCheckIsDirectory(_ directory: String) throws(CallHistorySaveError) {
        if mkdir(directory, 0o777) == 0 {
            return
        }
        let code = errno
        if code == EEXIST && RawFileSystem.isDirectory(directory) {
            return
        }
        throw .posix(code, file: directory)
    }
}
