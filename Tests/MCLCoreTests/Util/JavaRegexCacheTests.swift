import Foundation
import Testing
@testable import MCLCore

/// `JavaRegexCache`: compiled `JavaRegex` by the **exact** pattern text (UTF-16), thread-
/// safe. The behaviour must be identical to `JavaRegex(pattern)` on every call — the cache only saves
/// the compilation.
@Suite struct JavaRegexCacheTests {

    @Test func samePatternIsCompiledOnce() throws {
        let cache = JavaRegexCache(capacity: 16)
        let first = try cache.regex("[A-Z]+\\d")
        let second = try cache.regex("[A-Z]+\\d")
        #expect(cache.count == 1)
        #expect(first.icuPattern == second.icuPattern)
        #expect(second.matches("AB1"))
        #expect(!second.matches("ab1"))
    }

    /// A bad pattern: the error is remembered too and is identical to the error of a direct compilation.
    @Test func failureIsCachedAndIdenticalToDirectCompile() throws {
        let cache = JavaRegexCache(capacity: 16)
        var direct: JavaRegexError?
        do throws(JavaRegexError) { _ = try JavaRegex("(ab") } catch { direct = error }
        for _ in 0..<2 {
            var cached: JavaRegexError?
            do throws(JavaRegexError) { _ = try cache.regex("(ab") } catch { cached = error }
            #expect(cached != nil)
            #expect(cached == direct)
        }
        #expect(cache.count == 1)
    }

    /// The key is the text by UTF-16 like a Java `String`, not Swift canonical equality: `[Å]` (U+00C5)
    /// and `[A\u{30A}]` (A + combining ring) are two different patterns with different behaviour in Java.
    @Test func canonicallyEquivalentPatternsAreDistinctKeys() throws {
        let cache = JavaRegexCache(capacity: 16)
        let precomposed = try cache.regex("[\u{C5}]")
        let decomposed = try cache.regex("[A\u{30A}]")
        #expect(cache.count == 2)
        #expect(precomposed.matches("\u{C5}"))
        #expect(!decomposed.matches("\u{C5}"))
        #expect(decomposed.matches("A"))
        #expect(!precomposed.matches("A"))
    }

    /// A pattern may come from user data (`matches(call, exch)`), hence the cache is bounded;
    /// when full it is emptied and filled again — results do not change.
    @Test func capacityBoundsTheCache() throws {
        let cache = JavaRegexCache(capacity: 4)
        for i in 0..<10 {
            let regex = try cache.regex("x\(i)")
            #expect(regex.matches("x\(i)"))
            #expect(cache.count <= 4)
        }
        #expect(try cache.regex("x9").matches("x9"))
    }

    @Test func concurrentUseYieldsSameResults() async throws {
        let cache = JavaRegexCache(capacity: 256)
        let patterns = (0..<50).map { "[A-Z]{\($0 % 5 + 1)}\\d\($0)" }
        let texts = (0..<50).map { String(repeating: "Q", count: $0 % 5 + 1) + "7\($0)" }
        let rounds = try await withThrowingTaskGroup(of: [Bool].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try zip(patterns, texts).map { pattern, text in try cache.regex(pattern).matches(text) }
                }
            }
            var out: [[Bool]] = []
            for try await round in group {
                out.append(round)
            }
            return out
        }
        #expect(rounds.count == 8)
        #expect(rounds.allSatisfy { $0.allSatisfy { $0 } })
        #expect(cache.count == 50)
    }

    /// The `matches` expression and exchange-field validation take the pattern from the shared cache.
    @Test func expressionAndExchangeValidationUseSharedCache() throws {
        let exprPattern = "[QZ]cache-expr-unique"
        #expect(!JavaRegexCache.shared.contains(exprPattern))
        _ = try Expression.eval("matches('x', '\(exprPattern)')", [:])
        #expect(JavaRegexCache.shared.contains(exprPattern))

        let fieldPattern = "[QZ]cache-field-unique"
        let definition = try ExchangeMeasuredTests.definition(
            "{exchange: {received: [{id: f, type: TEXT, validation: {regex: '\(fieldPattern)'}}]}}")
        let field = try #require(definition.exchange?.received?.first ?? nil)
        #expect(!JavaRegexCache.shared.contains(fieldPattern))
        _ = try ExchangeEngine().parse(field, "abc")
        #expect(JavaRegexCache.shared.contains(fieldPattern))
    }
}
