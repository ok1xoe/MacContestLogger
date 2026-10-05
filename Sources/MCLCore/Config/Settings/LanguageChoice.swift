import Foundation

/// The language picker of the Other tab (`MT:` = `ui/configurer/ModeTabs.kt` of v1.1.1, lines 127-160). The menu
/// is the content of the language directory; the stored value is the code, never the label.
public enum LanguageChoice {

    /// `"${label}  (${code})"` — two spaces.
    public static func label(_ language: LanguageCatalog.Language) -> String {
        language.label + "  (" + language.code + ")"
    }

    /// The field text: the label of the language whose code equals the draft's (Java equality, first match), or the
    /// bare code when it is not in the menu.
    public static func selectedLabel(code: String, in languages: [LanguageCatalog.Language]) -> String {
        guard let current = languages.first(where: { JavaText.equals($0.code, code) }) else {
            return code
        }
        return label(current)
    }

    /// A picked menu text back to its code (`firstOrNull { label(it) == picked }`); `nil` keeps the draft as it is.
    public static func code(forLabel picked: String, in languages: [LanguageCatalog.Language]) -> String? {
        languages.first { JavaText.equals(label($0), picked) }?.code
    }
}
