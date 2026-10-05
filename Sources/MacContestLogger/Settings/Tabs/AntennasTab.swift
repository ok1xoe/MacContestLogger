import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `AntennasTab` (`AT:35-78`): the antenna table (code for the band decoder 0–15, name, bands, sector), the
/// hamlib rotator, the N1MM rotor over UDP and switching the rig's antenna connector.
struct AntennasTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private var language: LanguageModel { app.language }

    var body: some View {
        SettingsGroup(title: language.tr("Antény")) {
            SettingsCaption(language.tr(
                "Kód = hodnota pro band decoder / anténní přepínač (OTRSP AUX 0–15; s volbou níž kódy 1–4 i konektor ANT rigu). Pásma: 20m,15m nebo 14, 21 (MHz). Sektor: 270-360, přes sever 300-60, prázdné = všesměrová."))
            HStack(spacing: 8) {
                SettingsCaption(language.tr("Kód")).frame(width: 60, alignment: .leading)
                SettingsCaption(language.tr("Anténa")).frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1.4)
                SettingsCaption(language.tr("Pásma")).frame(maxWidth: .infinity, alignment: .leading)
                SettingsCaption("Sektor").frame(width: 110, alignment: .leading)
                Color.clear.frame(width: 24, height: 1)
            }
            ForEach($draft.antennas) { $row in
                AntennaRow(language: language, row: $row) {
                    draft.antennas.removeAll { $0.id == row.id }
                }
            }
            SettingsButton(language.tr("Přidat anténu")) {
                let entry = AntennaEntry(code: draft.antennas.count, name: "", bands: "", sector: "")
                draft.antennas.append(AntennaDraft(entry))
            }
            .padding(.top, 4)
            rotatorGroup
            udpRotorGroup
            SettingsCheckbox(
                label: language.tr("Přepínat i anténní konektor rigu (kódy 1–4 = ANT1–ANT4, hamlib)"),
                isOn: $draft.antennaViaRig)
                .padding(.top, 4)
        }
    }

    private var rotatorGroup: some View {
        SettingsGroup(title: language.tr("Rotátor (hamlib rotctld)")) {
            SettingsCaption(language.tr(
                "Spusť rotctld, např. rotctld -m 603 -r /dev/cu.usbserial-… -t 4533. Prázdný host = bez rotátoru. Alt+J natočí na volačku, Ctrl+Alt+J dlouhou cestou, Alt+L zastaví; okno Okno → Rotátor."))
            HStack(spacing: 8) {
                SettingsTextField(text: $draft.rotatorHost)
                    .frame(maxWidth: .infinity)
                SettingsTextField(text: $draft.rotatorPort, filter: .digits(limit: nil))
                    .frame(width: 110)
            }
        }
    }

    private var udpRotorGroup: some View {
        SettingsGroup(title: language.tr("Rotátor přes UDP (N1MM Rotor protokol)")) {
            SettingsCaption(language.tr(
                "Pro PstRotator, ARSVCOM a jiné programy s N1MM Rotor UDP (výchozí port 12040). Příkazy natočení a stop se pošlou sem — i souběžně s rotctld. Prázdný host = vypnuto."))
            HStack(spacing: 8) {
                SettingsTextField(text: $draft.rotorUdpHost)
                    .frame(maxWidth: .infinity)
                SettingsTextField(text: $draft.rotorUdpPort, filter: .digits(limit: nil))
                    .frame(width: 110)
                SettingsTextField(text: $draft.rotorUdpName)
                    .frame(maxWidth: .infinity)
            }
            SettingsCaption(language.tr("host · port · jméno rotátoru (jak ho zná rotátorový program)"))
        }
    }
}

private struct AntennaRow: View {
    let language: LanguageModel
    @Binding var row: AntennaDraft
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SettingsTextField(text: $row.code, filter: .digits(limit: 2))
                .frame(width: 60)
            SettingsTextField(text: $row.name)
                .frame(maxWidth: .infinity)
                .layoutPriority(1.4)
            SettingsTextField(text: $row.bands)
                .frame(maxWidth: .infinity)
            SettingsTextField(text: $row.sector)
                .frame(width: 110)
            SettingsDeleteButton(help: language.tr("Smazat anténu"), action: onDelete)
                .frame(width: 24)
        }
    }
}
