import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `OnlineCallbooksTab` (`OC:16-27`): two fixed sub-tabs, HamQTH (`HamQthTab.kt`) and QRZ.com (`QrzTab.kt`);
/// child nodes of the tab in `menu.json` are ignored, as in Kotlin.
struct OnlineCallbooksTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    @StateObject private var subState = ViewState<Int>(0)
    private var sub: Int {
        get { subState.value }
        nonmutating set { subState.value = newValue }
    }

    private var language: LanguageModel { app.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(selection: $subState.value) {
                Text(verbatim: "HamQTH").tag(0)
                Text(verbatim: "QRZ.com").tag(1)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if sub == 0 {
                hamQth
            } else {
                qrz
            }
        }
    }

    @ViewBuilder private var hamQth: some View {
        SettingsGroup(title: language.tr("HamQTH — přihlášení")) {
            SettingsCheckbox(label: "Volat HamQTH (zapnuto)", isOn: $draft.hamQthEnabled)
            SettingsField(caption: language.tr("Uživatelské jméno")) {
                SettingsTextField(text: $draft.hamQthUsername)
            }
            SettingsField(caption: "Heslo") {
                SettingsTextField(text: $draft.hamQthPassword, isPassword: true)
            }
            SettingsCaption(language.tr("Účet zdarma na hamqth.com. Bez údajů se z HamQTH nic nedohledává."))
        }
        SettingsGroup(title: language.tr("Volat HamQTH pro módy")) {
            SettingsCaption(language.tr(
                "Omezí dotazování — např. neptat se na CW spoty v digitálním závodě. Prázdné = všechny módy."))
            CallModes(list: $draft.hamQthCallModes)
        }
        SettingsGroup(title: language.tr("Stahovat údaje (predikce násobiče)")) {
            SettingsCaption(language.tr("Stažené údaje se nabídnou jako predikce podle typu násobiče v závodě ")
                + language.tr("(grid → čtverce, CQ/ITU → zóny)."))
            FetchFields(language: language, list: $draft.hamQthFetchFields)
        }
    }

    @ViewBuilder private var qrz: some View {
        SettingsGroup(title: language.tr("QRZ.com — přihlášení")) {
            SettingsCheckbox(label: "Volat QRZ.com (zapnuto)", isOn: $draft.qrzEnabled)
            SettingsField(caption: language.tr("Uživatelské jméno")) {
                SettingsTextField(text: $draft.qrzUsername)
            }
            SettingsField(caption: "Heslo") {
                SettingsTextField(text: $draft.qrzPassword, isPassword: true)
            }
            SettingsCaption(language.tr(
                "Vyžaduje QRZ XML Logbook Data předplatné pro plný přístup. Bez údajů se z QRZ nic nedohledává."))
        }
        SettingsGroup(title: language.tr("Volat QRZ pro módy")) {
            SettingsCaption(language.tr("Omezí dotazování. Prázdné = všechny módy."))
            CallModes(list: $draft.qrzCallModes)
        }
        SettingsGroup(title: language.tr("Stahovat údaje (predikce násobiče)")) {
            FetchFields(language: language, list: $draft.qrzFetchFields)
        }
    }
}

/// CW / Phone / Digi (`HQ:44-48`).
private struct CallModes: View {
    @Binding var list: [String]

    var body: some View {
        HStack(spacing: 10) {
            CheckItem(label: "CW", key: "CW", list: $list)
            CheckItem(label: "Phone", key: "PHONE", list: $list)
            CheckItem(label: "Digi", key: "DIGI", list: $list)
        }
    }
}

/// Locator / CQ zone / ITU zone / name (`HQ:55-60`).
private struct FetchFields: View {
    let language: LanguageModel
    @Binding var list: [String]

    var body: some View {
        HStack(spacing: 10) {
            CheckItem(label: language.tr("Lokátor"), key: "grid", list: $list)
            CheckItem(label: language.tr("CQ zóna"), key: "cqZone", list: $list)
            CheckItem(label: language.tr("ITU zóna"), key: "ituZone", list: $list)
            CheckItem(label: language.tr("Jméno"), key: "name", list: $list)
        }
    }
}

/// Kotlin `CheckItem` (`HQ:64-73`): on = add the key when missing, off = remove its first occurrence.
private struct CheckItem: View {
    let label: String
    let key: String
    @Binding var list: [String]

    var body: some View {
        let binding = Binding<Bool>(
            get: { list.contains(key) },
            set: { on in
                if on {
                    if !list.contains(key) {
                        list.append(key)
                    }
                } else if let index = list.firstIndex(of: key) {
                    list.remove(at: index)
                }
            })
        SettingsCheckbox(label: label, isOn: binding)
    }
}
