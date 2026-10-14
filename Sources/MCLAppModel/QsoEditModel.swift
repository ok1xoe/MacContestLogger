import Foundation
import MCLCore
import Observation

/// N1MM's Edit Contact dialog: Edit → Edit Last Contact (Ctrl+Y) and the Entry window's Edit button edit a logged QSO
/// (every field, saved to the log and rescored), Edit → Edit Current Contact edits the QSO still in the Entry window
/// (its call, frequency, mode, reports, exchange and note go back into the fields).
@Observable @MainActor
public final class QsoEditModel {

    public enum Target: Equatable, Sendable {
        /// A stored QSO by its id.
        case logged(Int64)
        /// The QSO being typed in the Entry window.
        case current
    }

    /// A received field of the Entry window (the current contact in a contest).
    public struct ExchangeField: Equatable, Sendable {
        public let id: String?
        public var text: String

        public var label: String { id ?? "" }
    }

    public let target: Target
    public var form: QsoEditForm
    /// The current contact's received fields in a contest (empty for a logged QSO and in free logging).
    public var exchangeFields: [ExchangeField]
    /// Why the last save was refused.
    public private(set) var problem: ContestMessage?

    /// Saves the dialog; `nil` = saved (the dialog closes), otherwise the problem shown.
    @ObservationIgnored let onSave: @MainActor (QsoEditModel) -> ContestMessage?
    @ObservationIgnored var onClose: (@MainActor () -> Void)?

    init(target: Target, form: QsoEditForm, exchangeFields: [ExchangeField] = [],
         onSave: @escaping @MainActor (QsoEditModel) -> ContestMessage?) {
        self.target = target
        self.form = form
        self.exchangeFields = exchangeFields
        self.onSave = onSave
    }

    /// The logged QSO's own fields (time, serial numbers, operator, X-QSO) are shown only for a logged QSO.
    public var editsLoggedQso: Bool {
        target != .current
    }

    /// The current contact in a contest shows its received fields instead of RST rx and the exchange text.
    public var showsExchangeFields: Bool {
        target == .current && !exchangeFields.isEmpty
    }

    /// OK / Enter.
    public func save() {
        if let refused = onSave(self) {
            problem = refused
        } else {
            problem = nil
            onClose?()
        }
    }

    /// Cancel / Esc / the close button.
    public func cancel() {
        onClose?()
    }

    public func setExchangeField(_ index: Int, _ text: String) {
        guard exchangeFields.indices.contains(index) else { return }
        exchangeFields[index].text = KotlinStrings.uppercase(text)
    }
}

// MARK: - the Entry window

extension EntryModel {

    /// N1MM Edit → Edit Last Contact (Ctrl+Y) and the Edit button: the last logged QSO in the edit dialog.
    public func editLastContact() {
        guard let last = logbook.lastRow, let id = last.id else {
            status.show(ContestMessage("Deník je prázdný"))
            return
        }
        editLoggedContact(id: id)
    }

    /// The edit dialog for the stored QSO `id`.
    public func editLoggedContact(id: Int64) {
        guard let qso = logbook.rows.first(where: { $0.id == id }) else { return }
        let logbook: LogbookModel = self.logbook
        let model = QsoEditModel(target: .logged(id), form: QsoEditForm(qso)) { model in
            guard let old = logbook.rows.first(where: { $0.id == id }) else {
                return ContestMessage("QSO už v deníku není")
            }
            switch model.form.apply(to: old) {
            case .failure(let problem):
                return problem.message
            case .success(let new):
                if new != old {
                    logbook.startUpdate(LogbookMutations.Edit(old: old, new: new))
                }
                return nil
            }
        }
        dialogs.openQsoEdit(model)
    }

    /// N1MM Edit → Edit Current Contact: the Entry window's QSO in the edit dialog; OK puts the values back.
    public func editCurrentContact() {
        var qso = Qso()
        qso.call = form.call
        qso.freqHz = Int(clamping: form.freqHz)
        qso.mode = form.mode
        qso.rstSent = form.rstSent
        qso.rstRcvd = form.rstRcvd
        qso.exchangeRcvd = form.exch
        qso.comment = pendingNote ?? ""
        let contestFields: [QsoEditModel.ExchangeField] = fields.map {
            QsoEditModel.ExchangeField(id: $0.id, text: form.contestExchange[$0.id] ?? "")
        }
        let model = QsoEditModel(target: .current, form: QsoEditForm(qso), exchangeFields: contestFields) {
            [weak self] model in
            self?.applyCurrentEdit(model)
        }
        dialogs.openQsoEdit(model)
    }

    private func applyCurrentEdit(_ model: QsoEditModel) -> ContestMessage? {
        let edit: QsoEditForm = model.form
        let modeText: String = KotlinStrings.uppercase(KotlinStrings.trim(edit.mode))
        let mode: Mode? = modeText.isEmpty ? nil : Mode(rawValue: modeText)
        if !modeText.isEmpty && mode == nil {
            return QsoEditForm.Problem.mode(modeText).message
        }
        let freqText: String = KotlinStrings.trim(edit.freqKHz)
        if !freqText.isEmpty && FrequencyText.parseHz(freqText) <= 0 {
            return QsoEditForm.Problem.frequency(freqText).message
        }
        callChanged(KotlinStrings.uppercase(KotlinStrings.trim(edit.call)))
        if freqText != form.freqKHz {
            setFrequency(freqText)
        }
        if let mode, mode != form.mode, !modeLocked {
            setMode(mode)
        }
        editRstSent(KotlinStrings.trim(edit.rstSent))
        if contest.isActive {
            for field in model.exchangeFields {
                editContestField(field.id, KotlinStrings.trim(field.text))
            }
        } else {
            editRstRcvd(KotlinStrings.trim(edit.rstRcvd))
            editExchange(KotlinStrings.uppercase(KotlinStrings.trim(edit.exchange)))
        }
        let note: String = KotlinStrings.trim(edit.note)
        pendingNote = note.isEmpty ? nil : note
        focusRequest += 1
        return nil
    }
}
