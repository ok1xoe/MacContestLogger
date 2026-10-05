import Foundation
import Testing

@testable import MCLCore

/// A guard: a real `config.json` written by the Java version 1.1.1 (user
/// `ok1xoe`) must pass through the Swift `ConfigStore` without losing a single key or
/// changing a single value. If a property in `AppConfig` (or some
/// of the nested configurations) were missing, had a different name than in Java, or were
/// overwritten at runtime by a faulty normalisation, the user would lose their settings
/// when switching to Swift.
///
/// The fixture `config-v1.1.1.json` is **not** a byte-exact copy of the user's file —
/// it is deliberately modified in two places so that personal data does not get into the repository:
/// `station.email` is an empty string (login credentials/tokens were
/// removed already when the fixture was taken) and `station.latitude`/`station.longitude`
/// are rounded to two decimal places (four decimal places locate
/// the house). Neither of these modifications affects what the test verifies.
///
/// The latitude/longitude (48.97, 17.87) are the centre of locator JN88WX — the contest QTH
/// Žítková pod Lokovem, consistent with `station.gridSquare` — not a home address. The file
/// paths (`contestDataDir`, `scpFile`, `callHistoryFile`, `databasesDir`) use the neutral home
/// `/Users/example`; the test only checks that every value survives the round trip, so the
/// exact path strings do not matter.
@Suite struct RealConfigCompatibilityTests {

    private func fixtureURL() throws -> URL {
        try #require(Bundle.module.url(forResource: "config-v1.1.1", withExtension: "json"))
    }

    @Test func realConfigFromVersion111LoadsWithoutLosingSettings() throws {
        let url = try fixtureURL()
        let store = ConfigStore(file: url)
        let config = store.load()

        // If decoding failed, the default AppConfig would be returned — this exposes it.
        #expect(config != AppConfig(), "the default configuration was loaded, so decoding failed")
        #expect(!config.station.call.isEmpty)
    }

    /// Compares keys recursively — not just at the first level but also inside nested
    /// configurations (`station.email`) and inside arrays of objects (`dxCluster.favorites[0].login`,
    /// `voiceKeyer.runMessages[3].text`). This also exposes the loss of a property
    /// that would stay hidden at the level of top-level keys because the whole section
    /// (`dxCluster`, `voiceKeyer`…) exists on both sides. A missing key is
    /// reported as a path separated by dots/indices, so it is at once clear where in
    /// `AppConfig` to add the corresponding property.
    @Test func everyKeyInRealConfigIsKnown() throws {
        let url = try fixtureURL()
        let data = try Data(contentsOf: url)
        let original = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let store = ConfigStore(file: url)
        let reencoded = try JSONEncoder().encode(store.load())
        let roundTripped = try #require(try JSONSerialization.jsonObject(with: reencoded) as? [String: Any])

        let lost = Self.lostKeyPaths(original: original, roundTripped: roundTripped)
        #expect(lost.isEmpty, "lost/changed configuration keys: \(lost.sorted())")
    }

    /// Builds a list of paths to keys that are in `original` but after passing through
    /// `ConfigStore` (decode → encode) in `roundTripped` are either missing
    /// or have a different **value**. Recurses into nested dictionaries and into arrays
    /// (item by item by index — `ConfigStore` does not change the order of arrays).
    ///
    /// Comparing values at the level of leaves is deliberate: a mere key match
    /// would not catch, for example, a deleted assignment in `AppConfig.init(from:)`
    /// (the property would silently stay at the default value instead of the value from
    /// the file) or a faulty normalisation that overwrites the value at runtime with
    /// something other than what the user saved. The normalisations of individual properties
    /// (lower bound, empty string…) have their own decoding tests; this
    /// guard only verifies that the user's actual value was neither lost nor
    /// changed.
    private static func lostKeyPaths(original: Any, roundTripped: Any, prefix: String = "") -> [String] {
        if let originalDict = original as? [String: Any] {
            guard let roundTrippedDict = roundTripped as? [String: Any] else {
                return [prefix.isEmpty ? "(root)" : prefix]
            }
            var lost: [String] = []
            for (key, value) in originalDict {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                guard let roundTrippedValue = roundTrippedDict[key] else {
                    lost.append(path)
                    continue
                }
                lost.append(contentsOf: lostKeyPaths(original: value, roundTripped: roundTrippedValue, prefix: path))
            }
            return lost
        }
        if let originalArray = original as? [Any] {
            guard let roundTrippedArray = roundTripped as? [Any], roundTrippedArray.count == originalArray.count
            else {
                return [prefix.isEmpty ? "(root)" : prefix]
            }
            return zip(originalArray, roundTrippedArray).enumerated().flatMap { index, pair in
                lostKeyPaths(original: pair.0, roundTripped: pair.1, prefix: "\(prefix)[\(index)]")
            }
        }
        // A list: the actual value (string, number, bool, null) must survive unchanged —
        // otherwise the user would lose the setting even if the key itself
        // stayed in place.
        if valuesMatch(original, roundTripped) { return [] }
        let path = prefix.isEmpty ? "(root)" : prefix
        return ["\(path) (expected \(describe(original)), got \(describe(roundTripped)))"]
    }

    private static func valuesMatch(_ lhs: Any, _ rhs: Any) -> Bool {
        if lhs is NSNull || rhs is NSNull { return lhs is NSNull && rhs is NSNull }
        guard let lhsObject = lhs as? NSObject, let rhsObject = rhs as? NSObject else { return false }
        return lhsObject.isEqual(rhsObject)
    }

    private static func describe(_ value: Any) -> String {
        if value is NSNull { return "null" }
        return "\(value)"
    }
}
