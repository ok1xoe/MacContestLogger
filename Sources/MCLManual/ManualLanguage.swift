import Foundation

/// The language of the user guide: English (`docs/*.md`, English screenshots from `docs/img/en/` where they exist) or
/// Czech (`docs/cs/*.md`, the Czech screenshots in `docs/img/`). The fixed texts of the book (title page, contents,
/// dates) follow it.
public enum ManualLanguage: String, Sendable, CaseIterable {
    case en
    case cs

    /// The directory of the pages, relative to `docs/` (`""` = `docs/` itself).
    public var pagesDir: String {
        switch self {
        case .en: return ""
        case .cs: return "cs/"
        }
    }

    /// The file name of the built guide: `MacContestLogger-manual-<lang>.<ext>`.
    public func fileName(_ ext: String) -> String {
        "MacContestLogger-manual-" + rawValue + "." + ext
    }

    /// The name kept from the first releases (`MacContestLogger-manual.<ext>`): the English guide; `nil` for Czech.
    public func legacyFileName(_ ext: String) -> String? {
        self == .en ? "MacContestLogger-manual." + ext : nil
    }

    /// The `lang` attribute of the HTML.
    public var htmlLang: String { rawValue }

    /// The subtitle on the title page and in the HTML title (`nil` = from the README's heading).
    var fixedSubtitle: String? {
        switch self {
        case .en: return nil
        case .cs: return "Uživatelská příručka"
        }
    }

    var contents: String {
        switch self {
        case .en: return "Contents"
        case .cs: return "Obsah"
        }
    }

    var atAGlance: String {
        switch self {
        case .en: return "At a glance"
        case .cs: return "Přehled"
        }
    }

    var documentSubject: String {
        switch self {
        case .en: return "MacContestLogger user guide"
        case .cs: return "Uživatelská příručka MacContestLogger"
        }
    }

    /// `Version v0.9.0 · built 2026-10-16` / `Verze v0.9.0 · sestaveno 16. 10. 2026` (either part may be missing;
    /// `nil` when both are). The date is the UTC day.
    func editionLine(version: String?, buildDate: Date?) -> String? {
        var parts: [String] = []
        if let version, !version.isEmpty {
            parts.append((self == .cs ? "Verze " : "Version ") + version)
        }
        if let buildDate {
            parts.append((self == .cs ? "sestaveno " : "built ") + day(buildDate))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `2026-10-16` (English, ISO) or `16. 10. 2026` (Czech), the UTC day.
    func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts: DateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        switch self {
        case .en: return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        case .cs: return String(format: "%d. %d. %04d", parts.day ?? 0, parts.month ?? 0, parts.year ?? 0)
        }
    }

    /// The note of the English guide's introduction when some screenshots have no English version yet.
    static let czechScreenshotsNote = "Some screenshots are not available in English yet: they show the Czech user "
        + "interface and their captions say so. The controls and their meaning are the same in both languages."

    /// What a caption of such a screenshot ends with.
    static let czechScreenshotCaption = "(Czech interface)"
}
