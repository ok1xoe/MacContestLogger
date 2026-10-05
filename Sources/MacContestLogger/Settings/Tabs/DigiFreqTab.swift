import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `DigiFreqTab` (`DF:28-53`): the digi channels (mode, from–to kHz), add and delete.
struct DigiFreqTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let language: LanguageModel = app.language
        SettingsGroup(title: language.tr("Digitální módy — frekvenční rozsahy (kHz)")) {
            HStack(spacing: 0) {
                Text(verbatim: language.tr("Mód"))
                    .windowFont(12, weight: .bold)
                    .frame(width: 140, alignment: .leading)
                Text(verbatim: "Od (kHz)")
                    .windowFont(12, weight: .bold)
                    .frame(width: 100, alignment: .leading)
                Text(verbatim: "Do (kHz)")
                    .windowFont(12, weight: .bold)
                    .frame(width: 100, alignment: .leading)
            }
            ForEach($draft.digiChannels) { $channel in
                HStack(spacing: 0) {
                    SettingsTextField(text: $channel.mode)
                        .frame(width: 130)
                    SettingsTextField(text: $channel.fromKhz)
                        .frame(width: 84)
                        .padding(.leading, 10)
                    SettingsTextField(text: $channel.toKhz)
                        .frame(width: 88)
                        .padding(.leading, 6)
                    SettingsDeleteButton(help: language.tr("Smazat kanál")) {
                        draft.digiChannels.removeAll { $0.id == channel.id }
                    }
                    .padding(.leading, 6)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
            SettingsButton(language.tr("Přidat kanál")) {
                draft.digiChannels.append(DigiChannelDraft(mode: "FT8", fromKhz: 0, toKhz: 0))
            }
            .padding(.top, 4)
            SettingsCaption(language.tr("Zadej přímo dolní a horní frekvenci kanálu. RTTY/PSK nemají pevný kanál ")
                + language.tr("(jsou to segmenty v bandplánu), proto se sem nezadávají."))
                .padding(.top, 4)
        }
    }
}
