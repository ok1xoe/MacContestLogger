import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `ProfilesWindow` (`profiles` 480×380, `PW:31-67`): save the current configuration under a name, load or
/// delete a saved profile. Not reopened after a restart (Kotlin `showProfiles` starts `false`,
/// `WindowsModel.notPersisted`); its geometry is kept like every window's.
struct ProfilesWindowView: View {
    let host: AppHost

    @StateObject private var session = WindowSession(id: "profiles", persistSize: true,
                                                     defaultSize: CGSize(width: 480, height: 380))
    @StateObject private var form = DialogFormState()

    private var binder: WindowGeometryBinder { session.binder }

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .navigationTitle(app.language.tr("Profily nastavení"))
                    .onAppear { binder.setStore(app.geometry) }
                    .task { await app.profiles.refresh() }
                    .background(WindowAccessor { window in
                        binder.isTerminating = { host.isTerminating }
                        binder.onClose = { app.windows.setOpen("profiles", false) }
                        binder.attach(window)
                    })
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 300, minHeight: 200)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        return VStack(alignment: .leading, spacing: 6) {
            WindowTopBar(size: $session.fontSize, language: language)
            nameRow(app)
            Text(verbatim: language.tr(
                "Profil = celé nastavení (stanice, rig, klávesy, zprávy, cluster…). Načtení přepíše aktuální nastavení."))
                .windowFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            ProfileList(app: app)
        }
        .padding(8)
        .windowFont(13)
        .environment(\.windowFontSize, session.fontSize)
    }

    /// „Jméno profilu" and „Uložit aktuální" (Kotlin: only a non-blank name, the field cleared after saving).
    private func nameRow(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let profiles: ProfilesModel = app.profiles
        let form: DialogFormState = self.form
        return HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: language.tr("Jméno profilu"))
                    .windowFont(11)
                    .foregroundStyle(.secondary)
                TextField(text: $form.text) {
                    Text(verbatim: language.tr("Jméno profilu"))
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
            }
            Button(language.tr("Uložit aktuální")) {
                let name: String = form.text
                guard !KotlinStrings.isBlank(name) else { return }
                form.text = ""
                Task { await profiles.save(name: name) }
            }
        }
    }
}

/// The saved profiles with „Načíst" / „Smazat", or „Žádné profily.".
private struct ProfileList: View {
    let app: AppModel

    var body: some View {
        let profiles: ProfilesModel = app.profiles
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 0) {
            if profiles.names.isEmpty {
                Text(verbatim: language.tr("Žádné profily."))
                    .foregroundStyle(.secondary)
            }
            WindowFontReader { size in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(profiles.names, id: \.self) { name in
                            row(name, profiles: profiles, language: language, fontSize: size)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func row(_ name: String, profiles: ProfilesModel, language: LanguageModel, fontSize: Int) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(verbatim: name)
                .font(.system(size: CGFloat(fontSize)))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(language.tr("Načíst")) {
                Task { await profiles.load(name) }
            }
            Button("Smazat") {
                Task { await profiles.delete(name) }
            }
        }
        .padding(.vertical, 2)
    }
}
