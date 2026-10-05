import os

/// Thread-safe cache of translated `JavaRegex` by **pattern text**.
///
/// In the engine Java calls `Pattern.compile` on every evaluation (the `matches` expression,
/// `ExchangeEngine.applyValidation`, `ExchangeGrab`); HotSpot can bear that, whereas translating
/// a Java pattern to ICU (`JavaRegexTranslator` + two `NSRegularExpression`s) is expensive here
/// and is repeated for every QSO when replaying a logbook The cache
/// does not change behavior: for the same text it returns the same result as `JavaRegex(pattern)` —
/// the translated pattern, or **the same error** (the error is remembered too, because the translation is
/// deterministic).
///
/// - The key is the pattern by **UTF-16 units** like a Java `String`: Swift `String` equality
///   is canonical (`[Å]` == `[A\u{30A}]`), but in Java they are two different patterns. The key
///   (`JavaStringKey`) is not allocated on lookup.
/// - Capacity is limited because a pattern may come from data (`matches(call, exch)`);
///   when full, the whole cache is emptied and refilled — simple, and for the fixed patterns
///   of a definition (dozens) it never applies.
/// - The translation runs outside the lock; a concurrent translation of the same pattern gives the same and either one is stored.
final class JavaRegexCache: Sendable {

    /// Shared engine instance.
    static let shared = JavaRegexCache(capacity: 1024)

    private let capacity: Int
    private let entries = OSAllocatedUnfairLock<[JavaStringKey: Result<JavaRegex, JavaRegexError>]>(initialState: [:])

    /// - Parameter capacity: at most how many patterns are remembered (at least 1).
    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// Equivalent of `JavaRegex(pattern)` (Java `Pattern.compile`) with memory.
    func regex(_ pattern: String) throws(JavaRegexError) -> JavaRegex {
        let key = JavaStringKey(pattern)
        if let cached = entries.withLock({ $0[key] }) {
            return try cached.get()
        }
        let compiled: Result<JavaRegex, JavaRegexError>
        do throws(JavaRegexError) {
            compiled = .success(try JavaRegex(pattern))
        } catch {
            compiled = .failure(error)
        }
        let capacity = self.capacity
        entries.withLock { entries in
            if entries.count >= capacity && entries[key] == nil {
                entries.removeAll(keepingCapacity: true)
            }
            entries[key] = compiled
        }
        return try compiled.get()
    }

    /// Number of remembered patterns (for tests).
    var count: Int {
        entries.withLock { $0.count }
    }

    /// Is the pattern (exactly by UTF-16) in the cache? (for tests)
    func contains(_ pattern: String) -> Bool {
        let key = JavaStringKey(pattern)
        return entries.withLock { $0[key] != nil }
    }
}
