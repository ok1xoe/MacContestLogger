import Foundation
import MCLCore

/// Export and clearing of the loaded call history (Tools menu).
extension DataToolsModel {

    public enum CallHistoryFormat: Equatable, Sendable {
        /// The N1MM+ call history file (`!!Order!!` header), loadable again.
        case n1mm
        /// RFC 4180 CSV with a header line, for a spreadsheet.
        case csv

        public var fileExtension: String {
            self == .csv ? "csv" : "txt"
        }
    }

    /// Whether a call history is loaded (the menu items act only then).
    public var hasCallHistory: Bool {
        callData.callHistory.size > 0
    }

    /// The suggested file name of an export.
    public func callHistoryFileName(_ format: CallHistoryFormat) -> String {
        "call-history." + format.fileExtension
    }

    /// Writes the loaded call history to `file` (atomically). The source file is not touched.
    public func exportCallHistory(to file: URL, format: CallHistoryFormat) async {
        let history: CallHistory = callData.callHistory
        guard history.size > 0 else {
            status.show("Call history je prázdná")
            return
        }
        do {
            try await BlockingQueue.run {
                switch format {
                case .n1mm:
                    try history.save(file.path, keepingFileLines: true)
                case .csv:
                    try Data(history.csvText().utf8).write(to: file, options: .atomic)
                }
            }
            status.show("Call history exportována do %s (%s volaček)", .string(file.path), .int(history.size))
        } catch let error as CallHistorySaveError {
            status.show("Export call history selhal: %s", .string(error.message))
        } catch {
            status.show("Export call history selhal: %s", .string(ErrorText.message(error)))
        }
    }

    /// `exportCallHistory`, run in the background (the save panel's choice).
    public func startExportCallHistory(to file: URL, format: CallHistoryFormat) {
        track { [weak self] in
            await self?.exportCallHistory(to: file, format: format)
        }
    }

    /// N1MM File → Import → Import Call History with several files: the chosen files join the additional call history
    /// files (`callHistoryExtraFiles`), merged after the primary one into one table; the configuration is saved and
    /// the call history reloads (`CallDataModel.observePaths`). Files already in use are skipped.
    public func importCallHistoryFiles(_ files: [URL]) {
        let primary: String = callData.primaryCallHistoryPath
        var extras: [String] = config.config.callHistoryExtraFiles
        var added: Int = 0
        for file in files {
            let path: String = file.path
            if path == primary || extras.contains(path) {
                continue
            }
            extras.append(path)
            added += 1
        }
        guard added > 0 else {
            status.show("Vybrané soubory už call history používá")
            return
        }
        config.config.callHistoryExtraFiles = extras
        config.save(failureKey: "Uložení nastavení selhalo: %s")
        status.show("Call history: přidáno %s souborů ke sloučení", .int(added))
    }

    /// The active contest's own call history file (N1MM Contest Setup → Associated Files); empty = the global one.
    public var contestCallHistoryFile: String? {
        guard contest.isActive else { return nil }
        return contest.activeSetup?.callHistoryFile ?? ""
    }

    /// Associates `path` (trimmed; blank = none) with the active contest: written into its setup in the database at
    /// once, then the call history switches to it (`CallDataModel.observePaths`).
    public func setContestCallHistoryFile(_ path: String) {
        let trimmed: String = KotlinStrings.trim(path)
        track { [weak self] in
            guard let self else { return }
            guard await self.contest.updateSetup({ $0.callHistoryFile = trimmed }) else { return }
            if trimmed.isEmpty {
                self.status.show("Závod používá hlavní soubor call history")
            } else {
                self.status.show("Call history závodu: %s", .string(trimmed))
            }
        }
    }

    /// The confirmed „Vymazat call history", run in the background.
    public func startClearCallHistory() {
        track { [weak self] in
            await self?.clearCallHistory()
        }
    }

    /// The question's text: the file that is emptied and where its copy is kept.
    public var clearCallHistoryTarget: String {
        callData.primaryCallHistoryPath
    }

    /// „Vymazat call history", after the confirmation: a copy of the file is kept beside it
    /// (`<file>.bak-<UTC time>`), then the file is rewritten with its columns and no callsign, and the loaded history
    /// is empty. Without a file there is nothing to clear. Only the primary file is cleared (the additional files
    /// stay merged in).
    public func clearCallHistory() async {
        let path: String = clearCallHistoryTarget
        let history: CallHistory = callData.primaryCallHistory
        guard history.size > 0, !path.isEmpty else {
            status.show("Call history je prázdná")
            return
        }
        let backup: String = path + ".bak-" + Self.backupStamp(now())
        let emptied: CallHistory = history.emptied()
        do {
            try await BlockingQueue.run {
                if FileManager.default.fileExists(atPath: path) {
                    try FileManager.default.copyItem(atPath: path, toPath: backup)
                }
                try emptied.save(path, keepingFileLines: true)
            }
        } catch let error as CallHistorySaveError {
            status.show("Vymazání call history selhalo: %s", .string(error.message))
            return
        } catch {
            status.show("Vymazání call history selhalo: %s", .string(ErrorText.message(error)))
            return
        }
        callData.adoptCallHistory(emptied, path: path)
        status.show("Call history vymazána (%s volaček), záloha: %s", .int(history.size), .string(backup))
    }

    private static func backupStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
