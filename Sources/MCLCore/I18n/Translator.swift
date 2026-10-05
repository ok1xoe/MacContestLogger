import Foundation

/// Core of UI localisation — a rewrite of Kotlin `ui/I18n` (`I18n.use`, `available`, `translate`, `tr(cs)`,
/// `tr(cs, args)`: logic in the core, the language state is held by the UI layer). Texts are in code
/// in Czech and are translated by the file `lang_<code>.json` (key = Czech text); a missing translation = the Czech text.
public struct Translator: Sendable, Equatable {

    /// Argument of `tr(cs, args)` (Kotlin `vararg args: Any?`): `Int`/`Long` as `.int`, `Double` as
    /// `.double`, anything else as text (`toString()`), `null` as `.string(nil)`.
    public enum Arg: Sendable, Equatable, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
        ExpressibleByStringLiteral
    {
        case int(Int)
        case double(Double)
        case string(String?)

        public init(integerLiteral value: Int) { self = .int(value) }
        public init(floatLiteral value: Double) { self = .double(value) }
        public init(stringLiteral value: String) { self = .string(value) }

        var javaFormat: JavaFormat.Arg {
            switch self {
            case .int(let value): return .int(value)
            case .double(let value): return .double(value)
            case .string(let value): return .string(value)
            }
        }
    }

    /// Language code; `cs` = Czech originals without a translation.
    public let language: String
    public let translations: LanguageCatalog.Translations

    /// Czech without a translation (the default state of `I18n`).
    public static let source = Translator(language: LanguageCatalog.sourceCode, translations: .empty)

    public init(language: String, translations: LanguageCatalog.Translations) {
        self.language = language
        self.translations = translations
    }

    /// `I18n.use(code)`: an empty or blank code (Kotlin `isNotBlank`, also NBSP) = Czech; otherwise the language from the directory
    /// with an equal code (`String.equals`) and its file; an unknown code falls back to Czech.
    public static func use(_ code: String?, in dir: String?) -> Translator {
        let wanted: String = code.flatMap { KotlinText.isBlank($0) ? nil : $0 } ?? LanguageCatalog.sourceCode
        if JavaText.equals(wanted, LanguageCatalog.sourceCode) {
            return .source
        }
        guard let found = LanguageCatalog.list(dir).first(where: { JavaText.equals($0.code, wanted) }) else {
            return .source
        }
        return Translator(language: found.code, translations: LanguageCatalog.load(found.file))
    }

    public static func use(_ code: String?, in dir: URL?) -> Translator {
        use(code, in: dir.map { RawFileSystem.javaPath(of: $0) })
    }

    /// `I18n.available()`: Czech (label `tr("Čeština")`, without a file) + languages from the directory.
    public func available(in dir: String?) -> [LanguageCatalog.Language] {
        let czech = LanguageCatalog.Language(code: LanguageCatalog.sourceCode, label: translate("Čeština"), file: nil)
        return [czech] + LanguageCatalog.list(dir)
    }

    public func available(in dir: URL?) -> [LanguageCatalog.Language] {
        available(in: dir.map { RawFileSystem.javaPath(of: $0) })
    }

    /// `tr(cs)`: the translation, or the Czech original.
    public func translate(_ cs: String) -> String {
        if JavaText.equals(language, LanguageCatalog.sourceCode) {
            return cs
        }
        return translations[cs] ?? cs
    }

    /// `tr(cs, args)` = `tr(cs).format(*args)` in the default locale; `decimalSeparator` is its decimal
    /// separator for `%f` (`cs_CZ` `","`).
    ///
    /// On a pattern that does not format (`%d` with text, a missing argument, `100% jistota` in a translation…) Java
    /// throws an exception and the UI crashes. Instead of crashing Swift formats the **Czech original** and when even that fails, returns
    /// it unformatted (a deliberate divergence from Java v1.1.1); the same goes for notations that `TranslationFormat` does not support.
    public func translate(_ cs: String, _ args: [Arg], decimalSeparator: String = ".") -> String {
        let pattern: String = translate(cs)
        if let out = TranslationFormat.render(pattern, args, decimalSeparator: decimalSeparator) {
            return out
        }
        return TranslationFormat.render(cs, args, decimalSeparator: decimalSeparator) ?? cs
    }

    /// Formatting result exactly like Java, or `nil` where Java would throw an exception (for tests and the UI layer).
    public static func format(_ pattern: String, _ args: [Arg], decimalSeparator: String = ".") -> String? {
        TranslationFormat.render(pattern, args, decimalSeparator: decimalSeparator)
    }
}
