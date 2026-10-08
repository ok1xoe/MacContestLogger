import AppKit
import MCLAppModel

/// The AppKit side of the menu's requests (`MenuActions.Request`): the save, open and directory panels
/// of Kotlin's AWT `FileDialog`s, the print dialog and the DXCC refill confirmation. A panel's choice starts the work
/// through `ImportExportModel.start` (one job after another, off the main thread).
///
/// Panels are not modal (the app keeps running while one is open) and carry Kotlin's dialog title as their `message`
/// (macOS shows no panel title). No file-type filter: Kotlin's `FileDialog` filters nothing either. The order of the
/// checks around a panel is the model's (EDI checks the contest before its panel, the rest after it).
@MainActor
enum ExportPanels {

    static func run(_ request: MenuActions.Request, app: AppModel) {
        switch request {
        case .saveAdif(let name):
            save(message: app.language.tr("Export deníku do ADIF"), name: name) { file in
                app.exports.start { await $0.exportAdif(to: file) }
            }
        case .saveAdifRange(let name, let range):
            save(message: app.language.tr("Export deníku do ADIF"), name: name) { file in
                app.exports.start { await $0.exportAdif(to: file, range: range) }
            }
        case .saveCallHistory(let format, let name):
            let message: String = format == .csv ? app.language.tr("Export call history do CSV")
                : app.language.tr("Export call history ve formátu N1MM")
            save(message: message, name: name) { file in
                app.dataTools.startExportCallHistory(to: file, format: format)
            }
        case .saveCabrillo(let name):
            save(message: app.language.tr("Export deníku do Cabrilla"), name: name) { file in
                app.exports.start { await $0.exportCabrillo(to: file) }
            }
        case .openImport:
            // Kotlin `chooseImportPath()`: the title is not translated.
            openFile(message: "Import QSO (ADIF / Cabrillo)") { file in
                app.exports.start { await $0.importQsos(from: file) }
            }
        case .openMerge:
            openFile(message: app.language.tr("Sloučit deník (.sqlite, ADIF, Cabrillo)")) { file in
                app.exports.start { await $0.merge(from: file) }
            }
        case .chooseDirectory(.edi):
            chooseDirectory(message: app.language.tr("Adresář pro EDI soubory")) { dir in
                app.exports.start { await $0.exportEdi(to: dir) }
            }
        case .chooseDirectory(.other):
            chooseDirectory(message: app.language.tr("Adresář pro CSV, text a souhrn")) { dir in
                app.exports.start { await $0.exportOther(to: dir) }
            }
        case .print(let job):
            // The print panel runs its own modal loop: not inside the SwiftUI update that delivered the request.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    LogPrinting.run(job, app: app)
                }
            }
        case .openDataFolder(let dir):
            NSWorkspace.shared.open(dir)
        case .openBeacons:
            openFile(message: app.language.tr("Soubor majáků (Beacons.txt)")) { file in
                app.spotNavigation.loadBeacons(url: file)
            }
        case .confirmRefillDxcc:
            // The dialog reads the log's size live while it is shown (Kotlin `state.qsos.size`), not the count of
            // the request.
            DataToolsDialogs.shared.confirmingRefill = true
        }
    }

    /// Kotlin `FileDialog(…, SAVE)` with the suggested name.
    private static func save(message: String, name: String, chosen: @escaping @MainActor (URL) -> Void) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = message
        panel.nameFieldStringValue = name
        begin(panel, chosen: chosen)
    }

    /// Kotlin `FileDialog(…, LOAD)`: one file, any type.
    static func openFile(message: String, chosen: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = message
        begin(panel, chosen: chosen)
    }

    /// Kotlin `chooseDirectory(title)` (`apple.awt.fileDialogForDirectories`).
    static func chooseDirectory(message: String, chosen: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        begin(panel, chosen: chosen)
    }

    private static func begin(_ panel: NSSavePanel, chosen: @escaping @MainActor (URL) -> Void) {
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                chosen(url)
            }
        }
    }
}
