import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `AudioTab` (`VK:43-107`): the voice keyer's sound devices, the receiver input and CW pitch, the speech
/// voice, PTT and the wav files. The devices are listed off the main thread when the tab opens; „Výchozí systémové"
/// stands for the system default (stored as `""`).
struct AudioTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private var language: LanguageModel { app.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            devicesGroup
            receiverGroup
            SettingsGroup(title: language.tr("Syntéza řeči (TTS)")) {
                SettingsCaption(language.tr(
                    "Položka v hranatých závorkách ve zprávě F-klávesy se namluví syntézou řeči (macOS say): [CQ contest *] — * moje volačka, ! jeho volačka, # číslo, @ frekvence; volačky se hláskují (Oscar Kilo…). Hotové nahrávky se ukládají do cache."))
                SettingsField(caption: language.tr("Hlas (např. Daniel, Samantha, Zuzana; prázdné = systémový)")) {
                    SettingsTextField(text: $draft.ttsVoice)
                }
                .frame(maxWidth: 360, alignment: .leading)
            }
            pttGroup
            filesGroup
        }
        .onAppear { app.settingsTools.loadAudioDevices() }
    }

    private var systemDefault: String {
        language.tr(SettingsTools.systemDefaultDevice)
    }

    /// A device drop-down: blank = „Výchozí systémové", picking it stores `""`.
    private func device(_ value: Binding<String>, _ options: [String]) -> some View {
        let fallback: String = systemDefault
        return SettingsDropdown(label: ifBlank(value.wrappedValue, fallback), options: options, language: language) {
            value.wrappedValue = $0 == fallback ? "" : $0
        }
    }

    private var devicesGroup: some View {
        let tools: SettingsToolsModel = app.settingsTools
        return SettingsGroup(title: language.tr("Zvuková zařízení")) {
            SettingsCaption(language.tr(
                "Výstup = kam se přehrávají zprávy (do vysílače, např. „USB Audio CODEC\" rigu). Vstup = mikrofon pro nahrávání zpráv (Ctrl+Shift+F-klávesa)."))
            HStack(alignment: .top, spacing: 12) {
                SettingsField(caption: language.tr("Výstup (vysílač)")) {
                    device($draft.vkOutput, tools.outputDevices)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsField(caption: language.tr("Vstup (nahrávání)")) {
                    device($draft.vkInput, tools.inputDevices)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var receiverGroup: some View {
        SettingsGroup(title: language.tr("Příjem (vodopád, CW dekodér, nahrávání závodu)")) {
            SettingsCaption(language.tr(
                "Vstup, na kterém je zvuk z přijímače (USB audio rigu). CW tón = výška tónu přijímače v CW, podle ní vodopád a dekodér přepočítávají audio na frekvenci."))
            HStack(alignment: .top, spacing: 12) {
                SettingsField(caption: language.tr("Vstup přijímače")) {
                    device($draft.rxAudio, app.settingsTools.inputDevices)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsField(caption: language.tr("CW tón (Hz)")) {
                    SettingsTextField(text: $draft.cwPitch, filter: .digits(limit: 4))
                }
                .frame(width: 120)
            }
        }
    }

    private var pttGroup: some View {
        SettingsGroup(title: "PTT") {
            SettingsCaption(language.tr(
                "Vysílač se klíčuje příkazem CAT (rigctld „T 1\"), musí být připojený TRX. Bez CATu nebo s vypnutou volbou klíčuje VOX vysílače. Prodleva dá relé čas přepnout, než začne zvuk."))
            FlowLayout(spacing: 12) {
                SettingsCheckbox(label: language.tr("PTT přes CAT"), isOn: $draft.vkPttViaCat)
                    .frame(width: 220, alignment: .leading)
                SettingsField(caption: "Prodleva PTT (ms)") {
                    SettingsTextField(text: $draft.vkPttDelay, filter: .digits(limit: nil))
                }
                .frame(width: 150)
                SettingsField(caption: language.tr("Max. délka nahrávky (s)")) {
                    SettingsTextField(text: $draft.vkMaxRecord, filter: .digits(limit: nil))
                }
                .frame(width: 170)
            }
        }
    }

    private var filesGroup: some View {
        let wavDir: String = app.dataDir.appendingPathComponent("wav").path
        return SettingsGroup(title: "Soubory") {
            SettingsCaption(language.tr(
                "Adresář wav souborů (prázdné = %s). Písmena a číslice pro hlášení volačky a čísla (A.wav…Z.wav, 0.wav…9.wav, stroke.wav, query.wav, point.wav) jsou v podadresáři; {OPERATOR} = volačka operátora u klíče.",
                .string(wavDir)))
            SettingsField(caption: language.tr("Adresář wav")) {
                SettingsTextField(text: $draft.vkWavDir)
            }
            SettingsField(caption: language.tr("Písmena a číslice (relativně k wav)")) {
                SettingsTextField(text: $draft.vkLettersPath)
            }
        }
    }
}
