import Foundation
import Testing
@testable import MCLCore

/// Nesting of groups and character classes in `JavaRegex`: above
/// `16` a loud `.unsupported`, **never a process
/// crash**. The pattern also arrives from the network (`validation.regex`
/// in a definition downloaded by `DefinitionUpdater`), so everything runs on its own thread
/// with 512 KB like Swift concurrency threads.
///
/// Java values measured by a probe over `java.util.regex.Pattern` (JDK 21):
/// Java compiles 16, 17 and 1000 nested groups or classes, at 10,000 it reports
/// `PatternSyntaxException` „Stack overflow during pattern compilation";
/// a class with 10,000 ranges passes. The match results below are Java's.
@Suite struct JavaRegexNestingTests {

    static func compile(_ pattern: String) async -> Result<JavaRegex, JavaRegexError> {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: Result { () throws(JavaRegexError) in try JavaRegex(pattern) })
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }
    }

    static let limit = JavaRegexTranslator.maxNestingDepth

    static func groups(_ depth: Int, open: String = "(") -> String {
        String(repeating: open, count: depth) + "a" + String(repeating: ")", count: depth)
    }

    /// `[a[b[c…]]]` — a union of nested classes, letters in sequence from `a`.
    static func classes(_ depth: Int) -> String {
        (0..<depth).map { "[" + String(Character(Unicode.Scalar(UInt8(97 + $0 % 26)))) }.joined()
            + String(repeating: "]", count: depth)
    }

    @Test func limitLeavesRoomForRealPatterns() {
        #expect(Self.limit == 16)
    }

    @Test func atLimitMatchesLikeJava() async throws {
        let capturing = try await Self.compile(Self.groups(Self.limit)).get()
        #expect(capturing.groupCount == 16)
        #expect(capturing.wholeMatch("a")?.group(16) == "a")
        #expect(!capturing.matches("b"))

        let nonCapturing = try await Self.compile(Self.groups(Self.limit, open: "(?:")).get()
        #expect(nonCapturing.matches("a"))

        // Java: a → true, p → true, q → false, z → false.
        let classes = try await Self.compile(Self.classes(Self.limit)).get()
        #expect(classes.matches("a") && classes.matches("p"))
        #expect(!classes.matches("q") && !classes.matches("z"))

        // Groups and classes together (8 + 8 levels). Java: a → true (group 1 "a"),
        // x → true, b → false.
        let mixed = try await Self.compile("(" + String(repeating: "(?:", count: 7) + "[x"
                                           + String(repeating: "[a", count: 7)
                                           + String(repeating: "]", count: 8)
                                           + String(repeating: ")", count: 8)).get()
        #expect(mixed.wholeMatch("a")?.group(1) == "a")
        #expect(mixed.matches("x") && !mixed.matches("b"))

        // Lookahead is also a group. Java: a → true.
        let lookahead = try await Self.compile(String(repeating: "(?=", count: 15) + "a"
                                               + String(repeating: ")", count: 15) + "a").get()
        #expect(lookahead.matches("a"))
    }

    @Test func overLimitIsUnsupportedAtTheOpener() async {
        // 17. `(` is at index 16, 17. `[` (the pair "[x") at index 32.
        for (pattern, index) in [(Self.groups(17), 16), (Self.groups(17, open: "(?:"), 48),
                                 (Self.classes(17), 32)] {
            guard case .failure(let error) = await Self.compile(pattern) else {
                Issue.record("\(pattern) compiled")
                continue
            }
            #expect(error.kind == .unsupported)
            #expect(error.index == index, "\(pattern)")
            #expect(error.reason.contains("zanoření"))
        }
    }

    /// Far above the limit: an error, not a crash (without the limit the debug build crashed from
    /// 33 groups and 93 classes).
    @Test(arguments: ["(", "(?:", "(?=", "(?<=", "(?<g", "[a"])
    func veryDeepIsRejectedWithoutCrash(_ open: String) async {
        let pattern: String
        if open == "[a" {
            pattern = String(repeating: "[a", count: 10_000) + String(repeating: "]", count: 10_000)
        } else if open == "(?<g" {
            // Named groups need different names.
            pattern = (0..<10_000).map { "(?<g\($0)>" }.joined() + "a"
                + String(repeating: ")", count: 10_000)
        } else {
            pattern = Self.groups(10_000, open: open)
        }
        guard case .failure(let error) = await Self.compile(pattern) else {
            Issue.record("\(open)… compiled")
            return
        }
        #expect(error.kind == .unsupported)
    }

    /// Wide (not deep) classes: the predicate used to be composed as a tree of depth
    /// equal to the number of items and its evaluation overflowed the stack around 1,750
    /// items. Java compiles them (measured on ranges: a → true, c → false).
    @Test func wideClassesDoNotOverflow() async throws {
        let ranges = try await Self.compile("[" + String(repeating: "a-b", count: 10_000) + "]").get()
        #expect(ranges.matches("a") && !ranges.matches("c"))
        let unions = try await Self.compile("[" + String(repeating: "[a]", count: 10_000) + "]").get()
        #expect(unions.matches("a") && !unions.matches("b"))
        let intersections = try await Self.compile("[a" + String(repeating: "&&[a]", count: 10_000) + "]").get()
        #expect(intersections.matches("a") && !intersections.matches("b"))
    }
}
