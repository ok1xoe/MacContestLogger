import Foundation

/// UI languages from files in the `language` directory — a rewrite of Java `i18n/LanguageCatalog` (v1.1.1). The convention is
/// `lang_<code>.json`: the user copies a file into the directory and the language appears in Settings. The menu is the content
/// of the directory, not a list in code.
///
/// The translation key is the **Czech text from the code**, the value the translation; a missing key = the Czech original. The optional key
/// `_name` is the language name for the menu (otherwise the code in upper case).
///
/// Measured by the maintainer-only probe (`I18nMeasuredTests`). Divergences (a deliberate divergence from Java v1.1.1):
/// non-string values are omitted (Java leaves them in the map and `tr()` fails on them, for `_name` already `list`),
/// `toUpperCase` of the label is without a locale (Java default locale; differs only for Turkish/Azerbaijani/Lithuanian `i`).
public enum LanguageCatalog {

    /// Source language of the texts in code — always available, needs no file.
    public static let sourceCode = "cs"

    static let prefix = "lang_"
    static let suffix = ".json"

    /// Key with the language name for the menu.
    static let nameKey = "_name"

    /// Languages shipped with the app (`Resources/i18n/lang_<code>.json` = the bytes of the Java `/i18n/<code>.json`).
    static let bundled: [String] = ["en", "de"]

    /// A language found in the directory (Java `record Language(code, label, file)`; `file` is a Java `Path`
    /// as text, `nil` for Czech in `Translator.available`).
    public struct Language: Equatable, Sendable {
        public let code: String
        public let label: String
        public let file: String?

        public init(code: String, label: String, file: String?) {
            self.code = code
            self.label = label
            self.file = file
        }

        public static func == (left: Language, right: Language) -> Bool {
            guard JavaText.equals(left.code, right.code), JavaText.equals(left.label, right.label) else {
                return false
            }
            guard let file = left.file else { return right.file == nil }
            return JavaText.equals(file, right.file)
        }
    }

    /// Translations of one file. Keys are compared by UTF-16 units like Java `String.equals`
    /// (NFC and NFD `é` are two different keys), not canonically like the Swift `String`.
    public struct Translations: Sendable, Equatable {
        let entries: [JavaStringKey: String]

        init(_ entries: [JavaStringKey: String]) {
            self.entries = entries
        }

        public static let empty = Translations([:])

        public subscript(_ cs: String) -> String? {
            entries[JavaStringKey(cs)]
        }

        public var count: Int { entries.count }

        public var isEmpty: Bool { entries.isEmpty }

        /// Entries in Java `TreeMap` order (keys by UTF-16 units).
        public var sortedEntries: [(key: String, value: String)] {
            let pairs: [(key: String, value: String)] = entries.map { (key: $0.key.text ?? "", value: $0.value) }
            return pairs.sorted { JavaText.compare($0.key, $1.key) < 0 }
        }
    }

    // MARK: - list

    /// Languages in the directory, sorted by code (`String.compareTo`). A non-existent or unreadable directory =
    /// an empty list.
    ///
    /// Takes every directory entry (also hidden, a subdirectory and a symbolic link) whose name starts with `lang_`
    /// and ends with `.json` (case-sensitive) and the code between them is neither empty nor whitespace
    /// (`String.isBlank`: U+2003 yes, NBSP no). Names are not normalised — the code carries the bytes from disk (an NFD name
    /// gives an NFD code, like `Files.list` on macOS).
    public static func list(_ dir: URL?) -> [Language] {
        list(dir.map { RawFileSystem.javaPath(of: $0) })
    }

    public static func list(_ dir: String?) -> [Language] {
        guard let dir, RawFileSystem.isDirectory(dir), let names = RawFileSystem.listDirectory(dir) else {
            return []
        }
        var out: [(index: Int, language: Language)] = []
        for raw in names {
            let name = String(decoding: raw, as: UTF8.self)
            guard let code = code(of: name) else { continue }
            let file: String = RawFileSystem.resolve(dir, name)
            out.append((out.count, Language(code: code, label: label(file, code), file: file)))
        }
        out.sort { left, right in
            let order: Int = JavaText.compare(left.language.code, right.language.code)
            return order != 0 ? order < 0 : left.index < right.index
        }
        return out.map(\.language)
    }

    /// Code from the name `lang_<code>.json`, or `nil` (another name, an empty code).
    static func code(of name: String) -> String? {
        let units: [UInt16] = Array(name.utf16)
        let head: [UInt16] = Array(prefix.utf16)
        let tail: [UInt16] = Array(suffix.utf16)
        guard units.starts(with: head), units.count >= head.count + tail.count,
            units.suffix(tail.count).elementsEqual(tail)
        else { return nil }
        let code: String = JavaChar.string(Array(units[head.count..<(units.count - tail.count)]))
        return JavaText.isBlank(code) ? nil : code
    }

    /// `_name`, or the code in upper case when missing or whitespace (`isBlank`).
    static func label(_ file: String, _ code: String) -> String {
        guard let name = load(file)[nameKey], !JavaText.isBlank(name) else {
            return JavaText.toUpperCase(code)
        }
        return name
    }

    // MARK: - load

    /// Translations from a file; on any error (missing, a directory, unreadable, bad JSON, a `null` value)
    /// empty. A bad file must not show up other than by nothing being translated.
    public static func load(_ file: URL?) -> Translations {
        load(file.map { RawFileSystem.javaPath(of: $0) })
    }

    public static func load(_ file: String?) -> Translations {
        guard let file, isRegularFile(file) else { return .empty }
        guard case .data(let data) = RawFileSystem.readFile(RawPath(file)) else { return .empty }
        return LanguageJsonReader.read([UInt8](data)).map(Translations.init) ?? .empty
    }

    /// `Files.isRegularFile` (follows symbolic links).
    static func isRegularFile(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFREG
    }

    // MARK: - ensureDir

    /// Creates the directory and puts the languages shipped with the app into it (`lang_en.json`, `lang_de.json`), so that they are
    /// in the menu right away and serve as a template. An existing file (even a link to an existing one) is not overwritten; a dangling
    /// symbolic link is replaced by a file (`Files.copy` with `REPLACE_EXISTING`). The first error ends the whole
    /// unpacking (Java `IOException`), nothing is reported.
    public static func ensureDir(_ dir: URL?) {
        ensureDir(dir.map { RawFileSystem.javaPath(of: $0) })
    }

    public static func ensureDir(_ dir: String?) {
        guard let dir else { return }
        if RawFileSystem.createDirectories(dir) != nil {
            return
        }
        for code in bundled {
            let file: String = RawFileSystem.resolve(dir, prefix + code + suffix)
            var info = stat()
            if stat(file, &info) == 0 {
                continue
            }
            guard let bytes = bundledBytes(code) else { continue }
            if !copy(bytes, to: file) {
                return
            }
        }
    }

    /// Bytes of the shipped language from the package resources. `.process("Resources")` flattens the tree, so
    /// `Resources/i18n/lang_en.json` lies in the bundle root (bytes unchanged — guarded by `bundledFilesAreJavaBytes`).
    public static func bundledBytes(_ code: String) -> [UInt8]? {
        guard let bundle = CoreResources.bundle else { return nil }
        return bundledBytes(code, in: bundle)
    }

    /// Bytes of the shipped language from the given resource bundle (the start-up check of the assembled app).
    public static func bundledBytes(_ code: String, in bundle: Bundle) -> [UInt8]? {
        let url: URL? = bundle.url(forResource: prefix + code, withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return [UInt8](data)
    }

    /// `Files.copy(in, file, REPLACE_EXISTING)`: delete what is there (a dangling link), then `CREATE_NEW` with permissions
    /// `0666 & ~umask` and write everything.
    private static func copy(_ bytes: [UInt8], to file: String) -> Bool {
        if unlink(file) != 0 && errno != ENOENT {
            return false
        }
        let descriptor: Int32 = open(file, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o666)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var offset = 0
        while offset < bytes.count {
            let written: Int = bytes[offset...].withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR { continue }
                return false
            }
            offset += written
        }
        return true
    }
}
