import Foundation
import MCLCore

/// The country-table check of the open database (N1MM warns when a database whose country table is older than the
/// downloaded country file is opened): the DXCC data stamp in the database's `meta` against the data in use
/// (`DxccDataStamp`).
extension DataToolsModel {

    /// The warning of an outdated country table (status line and the Info window's messages).
    static func outdatedDxccWarning(stored: DxccDataStamp, current: DxccDataStamp) -> ContestMessage {
        ContestMessage(
            "Deník byl vyplněn starší tabulkou zemí (%s, %s) než je aktuální (%s, %s) — použij Nástroje → Přepočítat DXCC v deníku…",
            .string(stored.source.rawValue), .string(stored.day), .string(current.source.rawValue),
            .string(current.day))
    }

    /// Checks the open database against the current DXCC data: a database without a stamp (or an empty one) gets the
    /// current stamp silently; a log filled with an older table is reported (`warn`), and keeps its stamp until it
    /// is refilled. Run after a database is opened (also at start-up); with `warn` false (after the data was
    /// reloaded) only the silent store happens.
    @discardableResult
    public func checkDxccStamp(warn: Bool = true) async -> DxccDataStamp.Decision? {
        let current: DxccDataStamp? = contest.environment.dxccStamp
        guard current != nil else { return nil }
        let decision: DxccDataStamp.Decision? = await logbookModel.checkDxccStamp(current)
        if warn, case .warn(let stored, let now) = decision {
            let text: ContestMessage = Self.outdatedDxccWarning(stored: stored, current: now)
            status.show(text)
            messages.add(language.text(text), at: self.now())
        }
        return decision
    }

    /// After a refill without an error, the log is filled with the current data: its stamp is recorded.
    func recordDxccStampAfterRefill() async {
        guard let current = contest.environment.dxccStamp else { return }
        await logbookModel.storeDxccStamp(current)
    }
}
