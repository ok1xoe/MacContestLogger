import MCLAppModel
import Observation
import SwiftUI

/// The confirmations of the data tools (Kotlin `RefillDxccConfirmDialog`, `WipeLogConfirmDialog.kt:53-80`): shown
/// by the main window while their flag is set.
@Observable @MainActor
final class DataToolsDialogs {

    static let shared = DataToolsDialogs()

    /// Kotlin `showRefillDxccConfirm`.
    var confirmingRefill = false
}

/// Presents the DXCC refill confirmation as an alert of the main window: the title counts the log's QSOs **while it
/// is shown** (Kotlin `state.qsos.size`), „Přepočítat" starts the refill (`DataToolsModel.refillDxcc`), „Zrušit"
/// closes.
struct DataToolsDialogPresenter: ViewModifier {
    let app: AppModel
    private let dialogs: DataToolsDialogs = .shared

    func body(content: Content) -> some View {
        // The log's size is read only while the alert is shown (no redraw of the main window per QSO otherwise).
        let confirmation: DataToolsModel.RefillConfirmation? = dialogs.confirmingRefill
            ? app.dataTools.refillConfirmation(count: app.logbook.rows.count) : nil
        let dataTools: DataToolsModel = app.dataTools
        content
            .alert(Text(verbatim: confirmation?.title ?? ""),
                   isPresented: Binding(get: { dialogs.confirmingRefill },
                                        set: { dialogs.confirmingRefill = $0 })) {
                Button(confirmation?.cancel ?? "", role: .cancel) {
                    dialogs.confirmingRefill = false
                }
                // Destructive, so Return does not confirm a rewrite of the whole log (Kotlin has no Enter default).
                Button(confirmation?.confirm ?? "", role: .destructive) {
                    dialogs.confirmingRefill = false
                    Task {
                        await dataTools.refillDxcc()
                    }
                }
            } message: {
                Text(verbatim: confirmation?.text ?? "")
            }
    }
}
