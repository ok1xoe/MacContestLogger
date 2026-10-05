import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `ModeControlTab` (`MT:33-55`): the mode written to the log and RTTY to the rig.
struct ModeControlTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private static let alwaysModes: [String] = ["CW", "SSB", "RTTY", "PSK", "FT8", "FT4", "DIGITAL"]

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title: language.tr("Mód zapisovaný do deníku")) {
                SettingsRadio(label: language.tr("Podle módu rigu (výchozí)"), selected: draft.modeRule == "RADIO") {
                    draft.modeRule = "RADIO"
                }
                SettingsRadio(label: language.tr("Podle bandplánu (CW / fone / digi segment)"),
                              selected: draft.modeRule == "BANDPLAN") {
                    draft.modeRule = "BANDPLAN"
                }
                HStack(spacing: 8) {
                    SettingsRadio(label: language.tr("Vždy:"), selected: draft.modeRule == "ALWAYS") {
                        draft.modeRule = "ALWAYS"
                    }
                    SettingsDropdown(label: draft.modeAlways, options: Self.alwaysModes, language: language) {
                        draft.modeAlways = $0
                    }
                    .frame(width: 120)
                }
                SettingsCaption(language.tr(
                    "Jednomódový závod má mód daný definicí; pravidlo platí pro volné logování a vícemódové závody."))
            }
            SettingsGroup(title: "RTTY do rigu") {
                HStack(spacing: 16) {
                    SettingsRadio(label: language.tr("FSK (RTTY mód rigu)"), selected: !draft.rttyAfsk) {
                        draft.rttyAfsk = false
                    }
                    SettingsRadio(label: language.tr("AFSK (datový režim, zvuk z počítače)"), selected: draft.rttyAfsk) {
                        draft.rttyAfsk = true
                    }
                }
            }
        }
    }
}
