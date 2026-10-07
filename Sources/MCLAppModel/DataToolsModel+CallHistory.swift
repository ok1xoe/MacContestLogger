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
                    try history.save(file.path)
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

    /// The confirmed „Vymazat call history", run in the background.
    public func startClearCallHistory() {
        track { [weak self] in
            await self?.clearCallHistory()
        }
    }

    /// The question's text: the file that is emptied and where its copy is kept.
    public var clearCallHistoryTarget: String {
        KotlinStrings.trim(config.config.callHistoryFile)
    }

    /// „Vymazat call history", after the confirmation: a copy of the file is kept beside it
    /// (`<file>.bak-<UTC time>`), then the file is rewritten with its columns and no callsign, and the loaded history
    /// is empty. Without a file there is nothing to clear.
    public func clearCallHistory() async {
        let path: String = clearCallHistoryTarget
        let history: CallHistory = callData.callHistory
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
                try emptied.save(path)
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
