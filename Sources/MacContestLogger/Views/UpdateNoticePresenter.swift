import MCLAppModel
import MCLCore
import SwiftUI

/// The answer of Tools / Help → check for a new program version, as an alert of the main window: a newer release
/// offers „Otevřít stránku vydání" (the browser opens only on that click), the other answers just close. A failed
/// PDF manual download offers the online documentation the same way.
struct UpdateNoticePresenter: ViewModifier {
    let app: AppModel

    func body(content: Content) -> some View {
        let updates: UpdateCheckModel = app.updates
        let language: LanguageModel = app.language
        let notice: UpdateCheckModel.Notice? = updates.notice
        content
            .alert(Text(verbatim: title(notice, language)),
                   isPresented: Binding(get: { updates.notice != nil }, set: { if !$0 { updates.notice = nil } })) {
                if case .newer(let release, _)? = notice {
                    Button(language.tr("Otevřít stránku vydání")) {
                        updates.openReleasePage(release)
                    }
                    Button(language.tr("Později"), role: .cancel) {
                        updates.notice = nil
                    }
                } else if case .manualFailed? = notice {
                    Button(language.tr("Otevřít dokumentaci online")) {
                        updates.openOnlineDocs()
                    }
                    Button(language.tr("Zavřít"), role: .cancel) {
                        updates.notice = nil
                    }
                } else {
                    Button(language.tr("Zavřít"), role: .cancel) {
                        updates.notice = nil
                    }
                }
            } message: {
                Text(verbatim: message(notice, language))
            }
    }

    private func title(_ notice: UpdateCheckModel.Notice?, _ language: LanguageModel) -> String {
        switch notice {
        case .newer?: return language.tr("Je k dispozici nová verze")
        case .upToDate?: return language.tr("Máte nejnovější verzi")
        case .failed?, nil: return language.tr("Kontrola nové verze")
        case .manualFailed(_, .pdf)?: return language.tr("PDF manuál")
        case .manualFailed(_, .html)?: return language.tr("HTML manuál")
        }
    }

    private func message(_ notice: UpdateCheckModel.Notice?, _ language: LanguageModel) -> String {
        switch notice {
        case .newer(let release, let current)?:
            return language.tr("Nová verze %s, máte %s.", .string(release.version), .string(current))
        case .upToDate(let current)?:
            return language.tr("Verze %s je nejnovější vydaná.", .string(current))
        case .failed(let text)?:
            return language.text(text)
        case .manualFailed(let text, _)?:
            return language.text(text) + "\n\n" + language.tr("Dokumentace je k dispozici online: %s",
                                                                .string(ManualDownload.docsUrl))
        case nil:
            return ""
        }
    }
}
