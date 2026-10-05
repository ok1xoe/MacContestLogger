import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `StationTab` (`ST:22-114`): the station's own data; latitude and longitude are read-only, computed from the
/// centre of the locator as it is typed (`gridLatLon`). Call, operator and locator are upper-cased as typed.
struct StationTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private var language: LanguageModel { app.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identityGroup
            addressGroup
            qthGroup
            equipmentGroup
            otherGroup
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        SettingsLabeledRow(label: label, labelWidth: 108, content: content)
    }

    private var identityGroup: some View {
        SettingsGroup(title: "Identita") {
            row(language.tr("Volačka")) {
                SettingsTextField(text: $draft.call, filter: .uppercase)
                SettingsCaption(language.tr("Operátor"))
                SettingsTextField(text: $draft.`operator`, filter: .uppercase)
            }
            row(language.tr("Jméno")) {
                SettingsTextField(text: $draft.name)
            }
        }
    }

    private var addressGroup: some View {
        SettingsGroup(title: "Adresa") {
            row("Adresa") {
                SettingsTextField(text: $draft.address1)
            }
            row("Adresa 2") {
                SettingsTextField(text: $draft.address2)
            }
            row(language.tr("Město")) {
                SettingsTextField(text: $draft.city)
                    .layoutPriority(2)
                SettingsCaption(language.tr("Stát"))
                SettingsTextField(text: $draft.stateRegion)
                SettingsCaption(language.tr("PSČ"))
                SettingsTextField(text: $draft.zip)
            }
            row(language.tr("Země")) {
                SettingsTextField(text: $draft.country)
            }
        }
    }

    private var qthGroup: some View {
        let latLon: (latitude: String, longitude: String)? = GridLatLon.of(draft.grid)
        return SettingsGroup(title: language.tr("QTH & lokátor")) {
            row(language.tr("Lokátor")) {
                SettingsTextField(text: $draft.grid, filter: .uppercase)
                SettingsCaption(language.tr("CQ zóna"))
                SettingsTextField(text: $draft.cqZone)
                SettingsCaption(language.tr("ITU zóna"))
                SettingsTextField(text: $draft.ituZone)
            }
            row("Licence") {
                SettingsTextField(text: $draft.license)
                SettingsCaption(language.tr("Šířka"))
                SettingsTextField(text: .constant(latLon?.latitude ?? ""))
                    .disabled(true)
                SettingsCaption(language.tr("Délka"))
                SettingsTextField(text: .constant(latLon?.longitude ?? ""))
                    .disabled(true)
            }
        }
    }

    private var equipmentGroup: some View {
        SettingsGroup(title: language.tr("Vybavení")) {
            row("Stanice TX/RX") {
                SettingsTextField(text: $draft.stationTxRx)
                SettingsCaption(language.tr("Výkon"))
                SettingsTextField(text: $draft.power)
            }
            row(language.tr("Anténa")) {
                SettingsTextField(text: $draft.antenna)
                    .layoutPriority(2)
                SettingsCaption(language.tr("Výška"))
                SettingsTextField(text: $draft.antHeight)
                SettingsCaption("n.m.")
                SettingsTextField(text: $draft.asl)
            }
        }
    }

    private var otherGroup: some View {
        let first: String = language.tr("Volačka, Operátor a Lokátor se propisují do ADIF exportu, azimutu v bandmapě a ")
        let second: String = language.tr("výpočtu skóre. Zem. šířka a délka se počítají ze středu lokátoru. ")
        let third: String = language.tr("Ostatní údaje se zatím jen ukládají.")
        return SettingsGroup(title: language.tr("Ostatní")) {
            row("ARRL sekce") {
                SettingsTextField(text: $draft.arrlSection)
                SettingsCaption("Rover QTH")
                SettingsTextField(text: $draft.roverQth)
            }
            row("Klub") {
                SettingsTextField(text: $draft.club)
            }
            row("E-mail") {
                SettingsTextField(text: $draft.email)
            }
            SettingsCaption(first + second + third)
        }
    }
}
