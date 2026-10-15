import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// „Datová složka" (N1MM's separate user files area, UserDir): where the app keeps its data now, and a restart over
/// another folder (`MCL_DATA_DIR`) — for another user, a club station or a test setup. The other folder has its own
/// settings, profiles and (by default) databases; a new folder starts like a first run.
struct DataFolderGroup: View {
    let app: AppModel

    var body: some View {
        let language: LanguageModel = app.language
        SettingsGroup(title: language.tr("Datová složka")) {
            Text(verbatim: app.dataDir.path)
                .windowFont(12, design: .monospaced)
                .textSelection(.enabled)
            FlowLayout(spacing: 8) {
                SettingsButton(language.tr("Spustit s jinou datovou složkou…")) { choose() }
                SettingsButton(language.tr("Spustit s výchozí datovou složkou")) { relaunch(nil) }
                    .disabled(!DataFolderRelaunch.differs(AppPaths.resolveDataDir(
                        userHome: FileManager.default.homeDirectoryForCurrentUser), from: app.dataDir))
            }
            SettingsCaption(language.tr(
                "Aplikace se ukončí a spustí znovu nad zvolenou složkou (vlastní nastavení, profily a databáze). config.json obsahuje absolutní cesty — složku nekopíruj, založ novou nebo použij profil."))
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = app.language.tr("Datová složka pro další spuštění")
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        guard DataFolderRelaunch.differs(dir, from: app.dataDir) else { return }
        relaunch(dir)
    }

    /// Asks, then starts the detached relaunch and quits.
    private func relaunch(_ dir: URL?) {
        let language: LanguageModel = app.language
        let alert = NSAlert()
        alert.messageText = language.tr("Restartovat s jinou datovou složkou?")
        alert.informativeText = dir?.path ?? language.tr("Výchozí datová složka")
        alert.addButton(withTitle: language.tr("Restartovat"))
        alert.addButton(withTitle: language.tr("Zrušit"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let command = DataFolderRelaunch.command(bundle: Bundle.main.bundleURL, dataDir: dir)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        do {
            try process.run()
        } catch {
            app.status.show("Restart nejde spustit: %s", .string(ErrorText.message(error)))
            return
        }
        AppQuit.request()
    }
}
