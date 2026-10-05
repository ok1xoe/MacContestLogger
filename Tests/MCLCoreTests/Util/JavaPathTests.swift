import Testing
@testable import MCLCore

/// `JavaPath` — `java.nio.file.Path` of the default file system of macOS (`sun.nio.fs.UnixPath`)
/// over a string, as needed by `VoiceMessagePlanner` (`resolve` + `normalize`, `relativize` for
/// reporting missing files, `isAbsolute`) and `ContestRecorder`/`MacSpeech` (`resolve`).
/// Measured on JDK 21.0.2 (maintainer-only probe, rows `P.*`; `MacOSXFileSystem`).
///
/// Traps: `Path.of` merges repeated `/` and trims the trailing one; an empty path has one (empty) name;
/// `normalize` goes above the root only for a relative path (`/..` → `/`, `a/../..` → `..`); `.` normalises to
/// an empty path; `relativize` between an absolute and a relative one throws, with a leftover `..` in the base too (the text
/// with **two spaces** `relative  path`); macOS **does not normalise Unicode** (`Ž` ≠ `Z` + U+030C).
@Suite struct JavaPathTests {

    /// The result by UTF-16 units (Swift `==` would consider `Ž` and `Z` + U+030C equal).
    private static func run(_ body: () throws -> String) -> [UInt16] {
        Array(text(body).utf16)
    }

    private static func text(_ body: () throws -> String) -> String {
        do {
            return try body()
        } catch let error as JavaInvalidPathError {
            return "EXC InvalidPathException: " + error.message
        } catch let error as JavaIllegalArgumentError {
            return "EXC IllegalArgumentException: " + error.message
        } catch {
            return "EXC \(error)"
        }
    }

    /// `Path.of(s)`: `toString`, `isAbsolute`, `normalize().toString`, `getNameCount`.
    @Test func ofMatchesJava() {
        let measured: [(String, String, String, String, String)] = [
            ("", "", "false", "", "1"),
            ("/", "/", "true", "/", "0"),
            ("//", "/", "true", "/", "0"),
            ("///a", "/a", "true", "/a", "1"),
            ("a//b/", "a/b", "false", "a/b", "2"),
            ("/wav/", "/wav", "true", "/wav", "1"),
            (".", ".", "false", "", "1"),
            ("..", "..", "false", "..", "1"),
            ("./", ".", "false", "", "1"),
            ("./a", "./a", "false", "a", "2"),
            ("a/./b", "a/./b", "false", "a/b", "3"),
            ("a/../b", "a/../b", "false", "b", "3"),
            ("../a", "../a", "false", "../a", "2"),
            ("a/..", "a/..", "false", "", "2"),
            ("/..", "/..", "true", "/", "1"),
            ("/../a", "/../a", "true", "/a", "2"),
            ("/a/b/../../..", "/a/b/../../..", "true", "/", "5"),
            ("a/b/../../..", "a/b/../../..", "false", "..", "5"),
            ("a/b/../../../c", "a/b/../../../c", "false", "../c", "6"),
            ("sub/../cq.wav", "sub/../cq.wav", "false", "cq.wav", "3"),
            ("../../cq3.wav", "../../cq3.wav", "false", "../../cq3.wav", "3"),
            ("x\u{0}y", "EXC InvalidPathException: Nul character not allowed: x\u{0}y", "EXC InvalidPathException: Nul character not allowed: x\u{0}y", "EXC InvalidPathException: Nul character not allowed: x\u{0}y", "EXC InvalidPathException: Nul character not allowed: x\u{0}y"),
            ("Z\u{30C}.wav", "Z\u{30C}.wav", "false", "Z\u{30C}.wav", "1"),
            ("\u{17D}.wav", "\u{17D}.wav", "false", "\u{17D}.wav", "1"),
            ("a\\b", "a\\b", "false", "a\\b", "1"),
            ("~/x", "~/x", "false", "~/x", "2"),
            ("/wav/./", "/wav/.", "true", "/wav", "2"),
            ("...", "...", "false", "...", "1"),
            ("a/.../b", "a/.../b", "false", "a/.../b", "3"),
            (".a/..b", ".a/..b", "false", ".a/..b", "2"),
            ("/a/./../b/./c/", "/a/./../b/./c", "true", "/b/c", "6"),
            ("a/\u{301}b/../c", "a/\u{301}b/../c", "false", "a/c", "4"),
        ]
        for (input, text, absolute, normalized, count) in measured {
            #expect(Self.run { try JavaPath(input).description } == Array(text.utf16), "\(input.debugDescription)")
            #expect(Self.run { String(try JavaPath(input).isAbsolute) } == Array(absolute.utf16), "\(input.debugDescription)")
            #expect(Self.run { try JavaPath(input).normalize().description } == Array(normalized.utf16), "\(input.debugDescription)")
            #expect(Self.run { String(try JavaPath(input).nameCount) } == Array(count.utf16), "\(input.debugDescription)")
        }
    }

    /// `Path.of(a).resolve(b)` a `….normalize()`.
    @Test func resolveMatchesJava() {
        let measured: [(String, String, String, String)] = [
            ("/wav", "cq.wav", "/wav/cq.wav", "/wav/cq.wav"),
            ("/wav", "sub/../cq.wav", "/wav/sub/../cq.wav", "/wav/cq.wav"),
            ("/wav", "../../cq3.wav", "/wav/../../cq3.wav", "/cq3.wav"),
            ("/wav", "/abs.wav", "/abs.wav", "/abs.wav"),
            ("/wav", "", "/wav", "/wav"),
            ("", "a", "a", "a"),
            ("", "", "", ""),
            ("/", "a", "/a", "/a"),
            ("rel", "a", "rel/a", "rel/a"),
            ("/wav/", "a//b", "/wav/a/b", "/wav/a/b"),
            ("/wav", "./a", "/wav/./a", "/wav/a"),
            ("/wav/letters", "DL1.wav", "/wav/letters/DL1.wav", "/wav/letters/DL1.wav"),
            ("/wav", "OK1XOE/cq.wav", "/wav/OK1XOE/cq.wav", "/wav/OK1XOE/cq.wav"),
            ("/wav", "Z\u{30C}.wav", "/wav/Z\u{30C}.wav", "/wav/Z\u{30C}.wav"),
            ("/wav", "a\u{0}", "EXC InvalidPathException: Nul character not allowed: a\u{0}", "EXC InvalidPathException: Nul character not allowed: a\u{0}"),
            (".", "a", "./a", "a"),
            ("..", "../a", "../../a", "../../a"),
        ]
        for (base, other, resolved, normalized) in measured {
            let label = "\(base.debugDescription) + \(other.debugDescription)"
            #expect(Self.run { try JavaPath(base).resolve(other).description } == Array(resolved.utf16), "\(label)")
            #expect(Self.run { try JavaPath(base).resolve(other).normalize().description } == Array(normalized.utf16), "\(label)")
        }
    }

    /// `Path.of(a).relativize(Path.of(b))`.
    @Test func relativizeMatchesJava() {
        let measured: [(String, String, String)] = [
            ("/wav", "/wav/cq.wav", "cq.wav"),
            ("/wav", "/cq3.wav", "../cq3.wav"),
            ("/wav", "/wav", ""),
            ("/wav", "/", ".."),
            ("/", "/a", "a"),
            ("/", "/", ""),
            ("/a/b", "/a/c/d", "../c/d"),
            ("/a/./b", "/a/b/c", "c"),
            ("/a/..", "/b", "b"),
            ("/a", "/a/../b", "../b"),
            ("a", "b", "../b"),
            ("", "a", "a"),
            ("a", "", ".."),
            ("", "", ""),
            ("/wav", "a", "EXC IllegalArgumentException: 'other' is different type of Path"),
            ("a", "/wav", "EXC IllegalArgumentException: 'other' is different type of Path"),
            ("a/..", "b", "b"),
            ("/a/b/..", "/a/c", "c"),
            ("../a", "b", "EXC IllegalArgumentException: Unable to compute relative  path from ../a to b"),
            ("..", "a", "EXC IllegalArgumentException: Unable to compute relative  path from .. to a"),
            ("a", "../b", "../../b"),
            ("a", "..", "../.."),
            ("/a/b/c", "/a/b", ".."),
            ("a/b", "a/b/c/d", "c/d"),
            ("a/b/c", "a/x/y", "../../x/y"),
            ("/wav/sub", "/wav/sub/../x.wav", "../x.wav"),
            ("/a/../..", "/b", "b"),
            ("a/../..", "b", "EXC IllegalArgumentException: Unable to compute relative  path from a/../.. to b"),
            ("../..", "..", "EXC IllegalArgumentException: Unable to compute relative  path from ../.. to .."),
            ("..", "../..", ".."),
            ("/wav", "/wav/Z\u{30C}.wav", "Z\u{30C}.wav"),
            (".", "a", "a"),
            ("a", ".", ".."),
            ("/a/.", "/a", ""),
            ("/w/\u{301}x", "/w/\u{301}x/y", "y"),
            ("/w/\u{17D}", "/w/Z\u{30C}", "../Z\u{30C}"),
        ]
        for (base, child, expected) in measured {
            let actual: [UInt16] = Self.run { try JavaPath(base).relativize(try JavaPath(child)).description }
            #expect(actual == Array(expected.utf16), "\(base.debugDescription) → \(child.debugDescription)")
        }
    }

    /// `Path.equals` = byte match after `Path.of` (without `.` normalisation and without Unicode normalisation).
    @Test func equalityMatchesJava() throws {
        #expect(try JavaPath("\u{17D}") != JavaPath("Z\u{30C}"))
        #expect(try JavaPath("a/") == JavaPath("a"))
        #expect(try JavaPath("a/./b") != JavaPath("a/b"))
        #expect(try JavaPath("/a") != JavaPath("a"))
    }
}
