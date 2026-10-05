import Foundation

/// Java `InvalidPathException` from `Path.of` (`getMessage()` literally, e.g.
/// `Nul character not allowed: a\u{0}b`).
public struct JavaInvalidPathError: Error, Equatable, Sendable {
    public let message: String
}

/// `java.nio.file.Path` of the default macOS file system (`sun.nio.fs.UnixPath`, JDK 21) purely
/// over a string — without touching the disk. Only what the voice key and contest recording need
/// (`VoiceMessagePlanner`: `Path.of`, `isAbsolute`, `resolve`, `normalize`, `relativize`;
/// `ContestRecorder`/`MacSpeech`: `resolve`), ported from `UnixPath`:
///
/// - `Path.of` merges repeated `/` and trims trailing ones (`a//b/` → `a/b`, `//` → `/`), throws on NUL;
///   otherwise it does not change the text — `.`/`..` stay, **Unicode is not normalized** (`Ž` ≠ `Z` + U+030C,
///   measured on `MacOSXFileSystem`);
/// - the empty path has one empty name; `.` normalizes to the empty path;
/// - `normalize` on an absolute path drops `..` above the root (`/wav/../../cq3.wav` → `/cq3.wav`),
///   on a relative one it keeps it (`a/../..` → `..`);
/// - `relativize` between an absolute and a relative path throws, as does the case where `..` is left in the unmatched part of the base
///   (message with two spaces, as in the JDK).
///
/// Equality is by UTF-16 units (Java's `equals` compares bytes), not Swift's canonical equality.
/// A lone half of a surrogate pair (Java: `InvalidPathException … unmappable characters`)
/// cannot be carried by Swift's `String`.
public struct JavaPath: Hashable, Sendable, CustomStringConvertible {

    /// Java `toString()`.
    public let description: String

    private init(normalized: String) {
        description = normalized
    }

    /// Java `Path.of(text)`.
    public init(_ text: String) throws(JavaInvalidPathError) {
        let units = Array(text.utf16)
        if units.contains(0) {
            throw JavaInvalidPathError(message: "Nul character not allowed: " + text)
        }
        var end = units.count
        while end > 0 && units[end - 1] == 0x2F { end -= 1 }
        if end == 0 {
            description = units.isEmpty ? "" : "/"
            return
        }
        var result: [UInt16] = []
        result.reserveCapacity(end)
        var previous: UInt16 = 0
        for unit in units[0..<end] {
            if unit == 0x2F && previous == 0x2F { continue }
            result.append(unit)
            previous = unit
        }
        description = result.count == units.count ? text : String(decoding: result, as: UTF16.self)
    }

    public static func == (left: JavaPath, right: JavaPath) -> Bool {
        left.description.utf16.elementsEqual(right.description.utf16)
    }

    public func hash(into hasher: inout Hasher) {
        for unit in description.utf16 {
            hasher.combine(unit)
        }
    }

    /// Java `isAbsolute()`.
    public var isAbsolute: Bool {
        description.utf16.first == 0x2F
    }

    private var isEmpty: Bool {
        description.isEmpty
    }

    /// Names (`getName(i)`): the empty path has one empty name, the root `/` none.
    private var names: [String] {
        if isEmpty { return [""] }
        // By UTF-16 units: `/` + a combining character is one grapheme in Swift, a separator in Java.
        return description.utf16.split(separator: 0x2F, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF16.self) }
    }

    /// Java `getNameCount()`.
    public var nameCount: Int {
        names.count
    }

    /// Java `resolve(Path)`: an absolute `other` wins, an empty side is omitted.
    public func resolve(_ other: JavaPath) -> JavaPath {
        if other.isAbsolute || isEmpty { return other }
        if other.isEmpty { return self }
        if description == "/" { return JavaPath(normalized: "/" + other.description) }
        return JavaPath(normalized: description + "/" + other.description)
    }

    /// Java `resolve(String)` = `resolve(Path.of(other))`.
    public func resolve(_ other: String) throws(JavaInvalidPathError) -> JavaPath {
        resolve(try JavaPath(other))
    }

    /// Java `normalize()`.
    public func normalize() -> JavaPath {
        let parts = names
        let count = parts.count
        if count == 0 || isEmpty { return self }
        var ignore = [Bool](repeating: false, count: count)
        var remaining = count
        var hasDotDot = false
        for (index, name) in parts.enumerated() {
            if name == "." {
                ignore[index] = true
                remaining -= 1
            } else if name.utf16.starts(with: [0x2E, 0x2E]) {
                hasDotDot = true
            }
        }
        if hasDotDot {
            var previousRemaining: Int
            repeat {
                previousRemaining = remaining
                var previousName = -1
                for index in 0..<count {
                    if ignore[index] { continue }
                    if parts[index] != ".." {
                        previousName = index
                        continue
                    }
                    if previousName >= 0 {
                        // name/<ignored>/.. → drop both
                        ignore[previousName] = true
                        ignore[index] = true
                        remaining -= 2
                        previousName = -1
                    } else if isAbsolute && !ignore[0..<index].contains(false) {
                        // /<ignored>/.. → drop `..` above the root
                        ignore[index] = true
                        remaining -= 1
                    }
                }
            } while previousRemaining > remaining
        }
        if remaining == count { return self }
        if remaining == 0 { return JavaPath(normalized: isAbsolute ? "/" : "") }
        let kept: [String] = parts.indices.filter { !ignore[$0] }.map { parts[$0] }
        let joined = kept.joined(separator: "/")
        return JavaPath(normalized: isAbsolute ? "/" + joined : joined)
    }

    /// Java `relativize(Path)`.
    public func relativize(_ other: JavaPath) throws(JavaIllegalArgumentError) -> JavaPath {
        if other == self { return JavaPath(normalized: "") }
        if isAbsolute != other.isAbsolute {
            throw JavaIllegalArgumentError(message: "'other' is different type of Path")
        }
        if isEmpty { return other }
        var base = self
        var child = other
        if base.hasDotOrDotDot || child.hasDotOrDotDot {
            base = base.normalize()
            child = child.normalize()
        }
        let baseNames = base.names
        let childNames = child.names
        var index = 0
        // Names are compared by bytes (= by UTF-16 units), not by Swift's canonical equality.
        while index < min(baseNames.count, childNames.count) && JavaText.equals(baseNames[index], childNames[index]) {
            index += 1
        }
        let childRemaining: String = index == childNames.count
            ? "" : childNames[index...].joined(separator: "/")
        if index == baseNames.count { return JavaPath(normalized: childRemaining) }
        let baseRemaining = JavaPath(normalized: baseNames[index...].joined(separator: "/"))
        if baseRemaining.hasDotOrDotDot {
            throw JavaIllegalArgumentError(
                message: "Unable to compute relative  path from " + description + " to " + other.description)
        }
        if baseRemaining.isEmpty { return JavaPath(normalized: childRemaining) }
        let dotdots = baseRemaining.nameCount
        var parts = [String](repeating: "..", count: dotdots)
        if !childRemaining.isEmpty { parts.append(childRemaining) }
        return JavaPath(normalized: parts.joined(separator: "/"))
    }

    /// `resolve(name)` for a file name composed by the program itself (`A.wav`, hash in the TTS cache,
    /// `20261128-12.wav`): without NUL and without `/`, so `Path.of` cannot fail nor merge anything.
    func resolve(fileName name: String) -> JavaPath {
        precondition(!name.utf16.contains(0) && !name.utf16.contains(0x2F) && !name.isEmpty, "jméno souboru: \(name)")
        return resolve(JavaPath(normalized: name))
    }

    private var hasDotOrDotDot: Bool {
        names.contains { $0 == "." || $0 == ".." }
    }
}
