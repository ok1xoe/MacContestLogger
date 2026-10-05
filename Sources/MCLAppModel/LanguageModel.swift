import Foundation
import MCLCore
import Observation

/// The UI language (checklist rows 45; 46): the current `Translator` as observable state, so every view
/// and the menu re-render on a switch, without a restart.
///
/// Kotlin keeps the language in the global `I18n` and switches it only from Settings; the mechanism is here
/// already. Loading a language reads files, so `load` and `switchTo` do it on `BlockingQueue`.
@Observable @MainActor
public final class LanguageModel {

    public private(set) var translator: Translator
    /// Directory of `lang_<code>.json` (Kotlin `AppPaths.languageDir()`).
    public let languageDir: URL
    /// Decimal separator for `%f` (Kotlin formats in the default locale): `Locale.current.decimalSeparator`.
    public let decimalSeparator: String

    public init(translator: Translator, languageDir: URL, decimalSeparator: String = LanguageModel.systemDecimalSeparator) {
        self.translator = translator
        self.languageDir = languageDir
        self.decimalSeparator = decimalSeparator
    }

    /// `Locale.current.decimalSeparator`, `"."` when the locale has none.
    public nonisolated static var systemDecimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }

    /// Kotlin start-up (`App.kt`, commit #159): `LanguageCatalog.ensureDir` (the shipped languages are unpacked so
    /// the user has templates) and `I18n.use(code)`. Blocking file I/O on `BlockingQueue`.
    public nonisolated static func load(code: String?, languageDir: URL) async -> Translator {
        let result: Translator? = try? await BlockingQueue.run {
            LanguageCatalog.ensureDir(languageDir)
            return Translator.use(code, in: languageDir)
        }
        return result ?? .source
    }

    /// The current language code (`cs` = Czech originals).
    public var code: String {
        translator.language
    }

    /// Kotlin `tr(cs)`.
    public func tr(_ cs: String) -> String {
        translator.translate(cs)
    }

    /// Kotlin `tr(cs, args)` with the system decimal separator.
    public func tr(_ cs: String, _ args: Translator.Arg...) -> String {
        translator.translate(cs, args, decimalSeparator: decimalSeparator)
    }

    /// A core message in the current language.
    public func text(_ message: ContestMessage) -> String {
        message.text(translator, decimalSeparator: decimalSeparator)
    }

    /// A status line of the entry window in the current language.
    public func text(_ status: EntryStatus) -> String {
        status.text(translator, decimalSeparator: decimalSeparator)
    }

    /// A status text in the current language.
    public func text(_ status: StatusText) -> String {
        switch status {
        case .message(let message):
            return text(message)
        case .joined(let parts, let separator):
            return parts.map { text($0) }.joined(separator: separator)
        }
    }

    /// Switches the language (Kotlin `I18n.use(code)` from Settings): loads it off the main thread, then replaces the
    /// translator — observers re-render at once. An unknown code falls back to Czech, as in Kotlin.
    public func switchTo(_ code: String) async {
        let loaded: Translator = await Self.use(code, languageDir: languageDir)
        apply(loaded)
    }

    /// Loads a language off the main thread without switching to it (the Settings commit loads the new language
    /// before the write and switches only after the write succeeded). An unknown code gives Czech.
    public func prepare(_ code: String) async -> Translator {
        await Self.use(code, languageDir: languageDir)
    }

    /// Replaces the translator (a language loaded elsewhere).
    public func apply(_ translator: Translator) {
        self.translator = translator
    }

    /// Kotlin `I18n.available()`: Czech (label translated) + the languages of the directory.
    public func available() async -> [LanguageCatalog.Language] {
        let current: Translator = translator
        let dir: URL = languageDir
        let result: [LanguageCatalog.Language]? = try? await BlockingQueue.run {
            current.available(in: dir)
        }
        return result ?? current.available(in: nil as String?)
    }

    private nonisolated static func use(_ code: String, languageDir: URL) async -> Translator {
        let result: Translator? = try? await BlockingQueue.run {
            Translator.use(code, in: languageDir)
        }
        return result ?? .source
    }
}
