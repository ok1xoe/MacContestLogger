import Foundation

/// An error that stands for a Java exception: the full Java class name and `Throwable.getMessage()` literally
/// (`nil` = Java `null`). The Kotlin UI shows `it.message` in its status texts (`"… (${it.message})"` prints
/// `null` for a missing message, see `IoTexts.template`), so every error of the `IO/` area that can reach a status
/// line carries both.
///
/// Measured against v1.1.1 (maintainer-only probe, rows `MAL`, `FS`, `ADIF`, `CAB`, `DB`).
public protocol JavaThrowable: Error {
    /// The full name of the Java exception class (`java.io.UncheckedIOException`).
    var javaClass: String { get }
    /// Java `getMessage()`; `nil` = `null`.
    var javaMessage: String? { get }
}

/// Describing any error the Java way.
public enum JavaThrowables {

    /// The Java class and message of `error`:
    /// - a `JavaThrowable` describes itself;
    /// - a Foundation file error gets the class Java's `java.nio.file` would throw for the same `errno`
    ///   (`UnixException.translateToIOException`, probe row `FS`): a missing file `NoSuchFileException`, no
    ///   permission (`EACCES`) `AccessDeniedException` — both with only the path as the message — and `EPERM`
    ///   `FileSystemException: <path>: Operation not permitted`, when the error names the file; any other Foundation error keeps its localized description as an `IOException`;
    /// - anything else: the Swift type name and `String(describing:)`.
    public static func describe(_ error: any Error) -> (javaClass: String, message: String?) {
        if let java = error as? any JavaThrowable {
            return (java.javaClass, java.javaMessage)
        }
        let bridged = error as NSError
        let system: Set<String> = [NSCocoaErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain]
        guard system.contains(bridged.domain) else {
            return ("Swift." + String(describing: type(of: error)), String(describing: error))
        }
        if let path = filePath(bridged), let code = posixCode(bridged) {
            switch code {
            case ENOENT: return ("java.nio.file.NoSuchFileException", path)
            case EACCES: return ("java.nio.file.AccessDeniedException", path)
            case EPERM:
                // `UnixException.translateToIOException`: only EACCES is `AccessDeniedException`.
                return ("java.nio.file.FileSystemException", path + ": " + String(cString: strerror(EPERM)))
            default: break
            }
        }
        return ("java.io.IOException", bridged.localizedDescription)
    }

    /// The Java message of `error` for a status text (`null` → `"null"`).
    public static func message(_ error: any Error) -> String {
        IoTexts.template(describe(error).message)
    }

    private static func filePath(_ error: NSError) -> String? {
        if let path = error.userInfo[NSFilePathErrorKey] as? String {
            return path
        }
        if let url = error.userInfo[NSURLErrorKey] as? URL, url.isFileURL {
            return url.path
        }
        return nil
    }

    private static func posixCode(_ error: NSError) -> Int32? {
        var code: Int32?
        if error.domain == NSPOSIXErrorDomain {
            code = Int32(truncatingIfNeeded: error.code)
        } else if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
                  underlying.domain == NSPOSIXErrorDomain {
            code = Int32(truncatingIfNeeded: underlying.code)
        } else if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case CocoaError.fileReadNoSuchFile.rawValue, CocoaError.fileNoSuchFile.rawValue:
                code = ENOENT
            case CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue:
                code = EACCES
            default:
                code = nil
            }
        }
        return code
    }
}

// MARK: - the six `IO/` errors (and the neighbours that reach the same status texts)

extension UncheckedIOError: JavaThrowable {
    public var javaClass: String { "java.io.UncheckedIOException" }
    public var javaMessage: String? { message }
}

extension CabrilloReaderError: JavaThrowable {
    public var javaMessage: String? {
        switch self {
        case .numberFormat(let message): return message
        case .unreadable(let message, _): return message
        }
    }
}

extension CabrilloExportError: JavaThrowable {
    public var javaMessage: String? {
        switch self {
        case .illegalArgument(let message): return message
        }
    }
}

extension JavaIndexOutOfBoundsError: JavaThrowable {
    public var javaMessage: String? { message }
}

extension LogExportsError: JavaThrowable {
    public var javaMessage: String? {
        switch self {
        case .nullPointer(let message): return message
        }
    }
}

extension Utf8Text.MalformedInput: JavaThrowable {
    var javaClass: String { "java.nio.charset.MalformedInputException" }
    /// `MalformedInputException.getMessage()` (probe row `MAL`).
    var javaMessage: String? { "Input length = " + String(length) }
}

extension JavaIOError: JavaThrowable {
    public var javaMessage: String? { message }
}

extension LogbookError: JavaThrowable {
    /// Java `LogbookException` (probe row `DB`).
    public var javaClass: String { "cz.ok1xoe.maccontestlogger.logbook.LogbookException" }
    public var javaMessage: String? { message }
}
