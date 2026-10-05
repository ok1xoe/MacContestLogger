import Foundation

public extension KeyedDecodingContainer {
    /// Reads a value, or returns the default. A missing key, `null` and a wrong type
    /// all end with the default value — never with an error.
    ///
    /// The Java version uses Jackson, which leaves a missing property at its default
    /// value. If Swift threw an error in that case, `ConfigStore` would
    /// return an empty configuration and the user would lose all settings.
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        guard let decoded = try? decodeIfPresent(T.self, forKey: key) else { return fallback }
        return decoded
    }
}
