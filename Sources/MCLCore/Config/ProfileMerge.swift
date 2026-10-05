import Foundation

/// A profile that Jackson rejected while merging it into the configuration (`ConfigProfiles.loadInto` throws).
public struct ProfileMergeError: Error, Equatable, Sendable {
    /// The Java exception class (`com.fasterxml.jackson…`).
    public let javaClass: String
    /// `Throwable.getMessage()` — Kotlin shows `"Profil: " + message`.
    public let javaMessage: String?
    /// The configuration as Jackson left it: `readerForUpdating` changes the live `AppConfig` in place, so
    /// everything read before the failure stays applied (Kotlin then skips `saveConfig()`, but keeps the object).
    /// For parity checks and diagnostics only — a failed load is atomic in the app: never assign this to the live
    /// configuration.
    public let partial: AppConfig

    /// The class of the error raised when the Swift side itself cannot encode or decode the configuration
    /// (never from Jackson; the merge is then refused instead of resetting settings).
    public static let swiftCodingFailure: String = "Swift.EncodingError"
}

/// The status line shows `getMessage()` like any other Java exception (`"Profil: " + message`).
extension ProfileMergeError: JavaThrowable {}

/// Loading a configuration profile like v1.1.1 (`ConfigProfiles.java`): the profile file is merged into the
/// current configuration by Jackson's `readerForUpdating` with `setDefaultMergeable(true)` and non-mergeable
/// `List`/`Map` — a nested object is merged field by field (a key missing in the profile keeps the current
/// value), a list or a map is replaced whole, a scalar is replaced; `null`, unknown keys, wrong types and syntax
/// errors behave as measured on the JVM (maintainer-only probe, gate `ProfileMergeJavaParityTests`).
///
/// Known differences (Swift's configuration types cannot hold them): a `null` that Java keeps — in a field
/// whose getter returns it, an element of a list or a value of a map — becomes the field default or is dropped;
/// a value Java accepts but a Swift field type could not represent would likewise decode to the field default (not
/// the current value; today the Swift types mirror Java, so this does not occur); a lone UTF-16 surrogate becomes
/// U+FFFD. The result is decoded like `ConfigStore.load` (`JSONDecoder`), except that non-finite `double` values
/// travel as the strings `NaN`/`Infinity`/`-Infinity` both ways, so that a `NaN` or an infinity — in the current
/// configuration or in the profile — is kept as Java keeps it.
public enum ProfileMerge {

    /// Merges the profile file `profileData` into `current`.
    public static func merge(current: AppConfig, profileData: Data) throws(ProfileMergeError) -> AppConfig {
        var root: [String: ProfileJson]
        do {
            root = try fields(of: current)
        } catch {
            throw codingFailure("Current configuration cannot be encoded", error, current)
        }
        let reader = JacksonMergeReader(data: profileData, rootDefaults: defaultFields)
        do {
            try reader.mergeRoot(into: &root)
        } catch {
            let partial: AppConfig = (try? decode(root)) ?? current
            throw ProfileMergeError(javaClass: error.javaClass, javaMessage: error.message, partial: partial)
        }
        do {
            return try decode(root)
        } catch {
            throw codingFailure("Merged configuration cannot be decoded", error, current)
        }
    }

    private static func codingFailure(_ what: String, _ error: any Error, _ current: AppConfig) -> ProfileMergeError {
        ProfileMergeError(javaClass: ProfileMergeError.swiftCodingFailure,
                          javaMessage: what + ": " + String(describing: error), partial: current)
    }

    /// `ConfigProfiles.isValidName`: `[\p{L}\p{N} _-]{1,40}` (code points) and not blank.
    public static func isValidName(_ name: String) -> Bool {
        guard let pattern = try? JavaRegexCache.shared.regex("[\\p{L}\\p{N} _-]{1,40}"), pattern.matches(name) else {
            return false
        }
        return !JavaText.isBlank(name)
    }

    /// The sorting of `ConfigProfiles.list()` (`String.compareTo`: UTF-16 units).
    public static func sortedNames(_ names: [String]) -> [String] {
        names.sorted { left, right in
            left.utf16.lexicographicallyPrecedes(right.utf16)
        }
    }

    /// The profile name of a file in the profile directory (`endsWith(".json")`, case-sensitive; the file
    /// `.json` itself is the name `""`), `nil` for other files.
    public static func nameFromFile(_ fileName: String) -> String? {
        let units: [UInt16] = Array(fileName.utf16)
        let suffix: [UInt16] = Array(".json".utf16)
        guard units.count >= suffix.count, Array(units.suffix(suffix.count)) == suffix else { return nil }
        return String(decoding: units.dropLast(suffix.count), as: UTF16.self)
    }

    // MARK: - JSON trees

    /// The tree of a new `AppConfig` (what a root-level bean is merged into after `"bean": null` reset it).
    private static let defaultFields: [String: ProfileJson] = (try? fields(of: AppConfig())) ?? [:]

    /// The non-finite `double` values as strings (Jackson's own spelling), both ways.
    static let nonFiniteEncoding: JSONEncoder.NonConformingFloatEncodingStrategy =
        .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
    static let nonFiniteDecoding: JSONDecoder.NonConformingFloatDecodingStrategy =
        .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")

    /// The JSON tree of a configuration; throws instead of returning a partial or empty tree.
    static func fields(of config: AppConfig) throws -> [String: ProfileJson] {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = nonFiniteEncoding
        let data: Data = try encoder.encode(config)
        guard case .object(let fields)? = ProfileJson.parse(data) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [],
                                                                    debugDescription: "not a JSON object"))
        }
        return fields
    }

    static func decode(_ fields: [String: ProfileJson]) throws -> AppConfig {
        let data: Data = try JSONEncoder().encode(ProfileJson.object(fields).decodable)
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = nonFiniteDecoding
        return try decoder.decode(AppConfig.self, from: data)
    }
}
