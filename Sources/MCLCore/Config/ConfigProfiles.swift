import Foundation

/// `ConfigProfiles` errors.
public enum ConfigProfilesError: Error, Equatable, Sendable {
    /// The profile name does not pass `ConfigProfiles.isValidName` (empty, too long,
    /// or contains characters other than letters, digits, space, `_`/`-`).
    case invalidName(String)
    /// A profile of the given name does not exist (`load`/`delete` of a nonexistent file).
    case notFound(String)

    /// The message of Java's `IOException` (Kotlin shows `"Profil: " + message`).
    public var javaMessage: String? {
        switch self {
        case .invalidName(let name): return "Neplatné jméno profilu: " + name
        case .notFound(let name): return "Profil neexistuje: " + name
        }
    }
}

/// Java throws both as a plain `java.io.IOException`.
extension ConfigProfilesError: JavaThrowable {
    public var javaClass: String { "java.io.IOException" }
}

/// Configuration profiles (N1MM multiple configurations / DXLog profiles): named copies
/// of settings in `profiles/<name>.json` — e.g. "Home", "Expedition", "Multi-op".
///
/// The Java version (`ConfigProfiles.java`) works directly with `AppConfig` and `loadInto`
/// *merges* values into an existing instance via Jackson's mergeable
/// `ObjectMapper` (nested objects are overwritten field by field, lists and maps are
/// replaced whole) — in Java `AppConfig` is a mutable object with shared identity.
///
/// Loading a profile into the live configuration with Java's merge semantics is `ProfileMerge.merge`;
/// `load` below stays for the older callers.
///
/// **Design decision** (when `AppConfig` was created in Swift): `AppConfig` is a
/// value type without object identity, so Jackson's "merge into the instance,
/// identity stays" has no direct equivalent for a value — it is replaced by `load(name)`
/// returning a completely new value that the caller simply assigns (`current =
/// try profiles.load(name)`). Because `save` always writes the *complete* `AppConfig`
/// (no field is missing), the result for profiles saved by this layer is identical
/// to what a field-by-field merge would give — the difference would show only for a hand-edited/older
/// profile with missing keys, where Jackson would keep the *current* value of the target, whereas our decoding
/// pattern (`value(_:default:)`)
/// fills in the type default. This layer therefore stays a generic file layer independent of
/// `AppConfig`: name validation, listing, saving, loading as a
/// new value and deletion — the "wiring" to `AppConfig` is its use with
/// `Profile == AppConfig` (see `ConfigStoreTests.configProfilesSaveListLoadDelete`).
public struct ConfigProfiles<Profile: Codable & Sendable>: Sendable {

    private let dir: URL

    public init(dir: URL) {
        self.dir = dir
    }

    /// Valid profile name: 1–40 letters/digits/spaces/`_`/`-` (code points), not only spaces — Java's
    /// `ConfigProfiles.isValidName` (`ProfileMerge.isValidName`).
    public static func isValidName(_ name: String) -> Bool {
        ProfileMerge.isValidName(name)
    }

    /// Java `dir.resolve(name.trim() + ".json")`: Java `trim()` (code points ≤ U+0020 only — a no-break space at
    /// either end stays part of the file name; maintainer-only probe).
    private func file(for name: String) -> URL {
        dir.appendingPathComponent(JavaText.trim(name) + ".json")
    }

    /// Names of saved profiles like Java's `list()`: every entry of the directory whose name ends with `.json`
    /// (case-sensitive, also a directory and the file `.json` itself, which is the name `""`), without the suffix,
    /// sorted by `String.compareTo`; no directory or an unreadable one → no profiles. Foundation file URLs store names
    /// decomposed (`save` writes `Žluť.json` as `Z` + U+030C…), so the names are composed (NFC) first; the JDK lists a
    /// name as stored, so a name another tool stored decomposed lists composed here (the Java parity suite measurement).
    public func list() -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        let names: [String] = entries.compactMap { ProfileMerge.nameFromFile($0.precomposedStringWithCanonicalMapping) }
        return ProfileMerge.sortedNames(names)
    }

    /// Saves `profile` under `name` (overwrites an existing profile of the same name).
    public func save(_ name: String, _ profile: Profile) throws {
        guard Self.isValidName(name) else { throw ConfigProfilesError.invalidName(name) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        try data.write(to: file(for: name))
    }

    /// Loads a profile as a new value (without merging into an existing configuration,
    /// see the type's documentation comment).
    public func load(_ name: String) throws -> Profile {
        let url = file(for: name)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ConfigProfilesError.notFound(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Profile.self, from: data)
    }

    /// The bytes of a profile for `ProfileMerge.merge`, with the errors of Java `loadInto` before Jackson parses
    /// anything (measured, `profile-files.tsv`): a file that is missing or not readable (`Files.isReadable`) →
    /// `ConfigProfilesError.notFound(name)` with the name as given; a directory named `<name>.json` →
    /// `java.io.FileNotFoundException: <path> (Is a directory)` (Jackson opens it with `FileInputStream`); another
    /// read error → the Foundation error. Blocking — call off the main thread and off the shared pool.
    public func profileData(_ name: String) throws -> Data {
        let url = file(for: name)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ConfigProfilesError.notFound(name)
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw JavaIOError(url.path + " (Is a directory)", javaClass: "java.io.FileNotFoundException")
        }
        return try Data(contentsOf: url)
    }

    /// Deletes a profile; a nonexistent file is a silent no-op.
    public func delete(_ name: String) throws {
        let url = file(for: name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
