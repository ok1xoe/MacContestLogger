import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `BlacklistEditor` (`DX:159-197`): the entries with „Smazat", a new entry (upper-cased as typed) and
/// „Přidat". The hint follows `title.contains("spot")` over the **translated** title (a kept defect).
struct BlacklistEditor: View {
    let language: LanguageModel
    let title: String
    @Binding var items: [String]

    @StateObject private var newItemState = ViewState<String>("")
    private var newItem: String {
        get { newItemState.value }
        nonmutating set { newItemState.value = newValue }
    }

    var body: some View {
        SettingsGroup(title: title) {
            SettingsCaption(language.tr(SettingsTexts.blacklistHintKey(translatedTitle: title)))
            ForEach(Array(items.enumerated()), id: \.offset) { index, value in
                HStack(spacing: 8) {
                    Text(verbatim: value)
                        .windowFont(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SettingsButton("Smazat") {
                        guard index < items.count else { return }
                        items.remove(at: index)
                    }
                }
            }
            HStack(spacing: 8) {
                SettingsTextField(text: $newItemState.value, filter: .uppercase)
                    .frame(maxWidth: .infinity)
                SettingsButton(language.tr("Přidat")) {
                    if let added = SettingsInputFilter.addingBlacklistEntry(newItem, to: items) {
                        items = added
                    }
                    newItem = ""
                }
            }
        }
    }
}
