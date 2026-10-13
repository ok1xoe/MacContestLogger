import Foundation
import MCLCore

/// N1MM QuickEdit: Ctrl+Q puts the last logged QSO into the Entry window's fields (again = one QSO back), Ctrl+A one
/// QSO forward; Enter saves the change to that QSO, Esc leaves it unchanged. What was being typed comes back
/// afterwards. While editing, the fields are tinted, the window does not follow the rig and nothing is logged.
public struct QuickEditState: Equatable, Sendable {
    /// The QSO in the fields.
    public let qsoId: Int64
    /// Its position from the end of the log (1 = the last QSO) and the log's size.
    public let position: Int
    public let count: Int
    /// The QSO as loaded (the save starts from the stored row).
    let loaded: EntryForm
    /// The Entry window before QuickEdit.
    let saved: EntryForm
    let savedNote: String?
}

extension EntryModel {

    /// Ctrl+Q (`direction` -1, one QSO back; the first press takes the last QSO) and Ctrl+A (+1, one QSO forward).
    public func quickEditStep(_ direction: Int) {
        let rows: [Qso] = logbook.rows.filter { $0.id != nil }
        guard !rows.isEmpty else {
            status.show(ContestMessage("Deník je prázdný"))
            return
        }
        let index: Int
        if let current = quickEdit, let at = rows.firstIndex(where: { $0.id == current.qsoId }) {
            index = at + direction
            guard rows.indices.contains(index) else {
                status.show(ContestMessage(direction < 0 ? "QuickEdit: první QSO deníku" : "QuickEdit: poslední QSO deníku"))
                return
            }
        } else if quickEdit == nil {
            guard direction < 0 else {
                status.show(ContestMessage("QuickEdit začíná Ctrl+Q"))
                return
            }
            index = rows.count - 1
        } else {
            index = rows.count - 1
        }
        loadQuickEdit(rows[index], position: rows.count - index, count: rows.count)
    }

    private func loadQuickEdit(_ qso: Qso, position: Int, count: Int) {
        guard let id = qso.id else { return }
        let saved: EntryForm = quickEdit?.saved ?? form
        let savedNote: String? = quickEdit?.savedNote ?? pendingNote
        var loaded: EntryForm = form.wiped(contestActive: contest.isActive, rstFieldIds: EntryForm.rstFieldIds(fields))
        loaded.call = qso.call
        loaded.freqKHz = qso.freqHz > 0 ? FrequencyText.formatHz(Int64(qso.freqHz)) : ""
        if let mode = qso.mode {
            loaded.mode = mode
        }
        loaded.rstSent = qso.rstSent
        loaded.rstRcvd = qso.rstRcvd
        loaded.exch = qso.exchangeRcvd
        if contest.isActive {
            loaded.contestExchange = JavaLinkedMap()
            let received = try? contest.runtime.freshSession()?.receivedFromFlat(
                call: qso.call, exchangeRcvdFlat: qso.exchangeRcvd, serialRcvd: qso.serialRcvd)
            let ids: [String?] = contest.exchangeFields(call: qso.call).map(\.id)
            for (fieldId, value) in received?.entries ?? [] where ids.contains(fieldId) {
                loaded.contestExchange.put(fieldId, value ?? "")
            }
        }
        quickEdit = QuickEditState(qsoId: id, position: position, count: count, loaded: loaded, saved: saved,
                                   savedNote: savedNote)
        form = loaded
        pendingNote = nil
        esmProgress = .empty
        selfSpot.prefilledFromSpot()
        updatePreview()
        status.show(ContestMessage("QuickEdit %s/%s: Enter uloží, Esc zruší", .int(position), .int(count)))
        focusRequest += 1
    }

    /// Enter (or Log It) in QuickEdit: the fields into the QSO, then the Entry window as before.
    public func saveQuickEdit() {
        guard let state = quickEdit else { return }
        guard let old = logbook.rows.first(where: { $0.id == state.qsoId }) else {
            status.show(ContestMessage("QSO už v deníku není"))
            leaveQuickEdit(state)
            return
        }
        if KotlinStrings.isBlank(form.call) {
            status.show(ContestMessage("Volačka nesmí být prázdná"))
            return
        }
        let assembled: Qso
        if contest.isActive {
            assembled = QsoAssembly.contest(form: form, fields: fields, rstFieldIds: EntryForm.rstFieldIds(fields),
                                            serial: old.serialSent ?? 0, runMode: old.runMode, sentFlat: nil,
                                            note: nil, at: nil)
        } else {
            assembled = QsoAssembly.free(form: form, serial: old.serialSent ?? 0, runMode: old.runMode, note: nil,
                                         at: nil)
        }
        var new: Qso = old
        new.call = assembled.call
        if form.freqKHz != state.loaded.freqKHz, assembled.freqHz > 0 {
            new.freqHz = assembled.freqHz
        }
        new.mode = assembled.mode
        new.rstSent = assembled.rstSent
        new.rstRcvd = assembled.rstRcvd
        new.exchangeRcvd = assembled.exchangeRcvd
        new.serialRcvd = assembled.serialRcvd
        if new != old {
            logbook.startUpdate(LogbookMutations.Edit(old: old, new: new))
            status.show(ContestMessage("QuickEdit: %s uloženo", .string(new.call)))
        }
        leaveQuickEdit(state)
    }

    /// Esc in QuickEdit: the QSO stays as it was.
    public func cancelQuickEdit() {
        guard let state = quickEdit else { return }
        status.show(ContestMessage("QuickEdit zrušen"))
        leaveQuickEdit(state)
    }

    private func leaveQuickEdit(_ state: QuickEditState) {
        quickEdit = nil
        form = state.saved
        pendingNote = state.savedNote
        selfSpot.typed()
        trackCallForSelfSpot()
        updatePreview()
        focusRequest += 1
    }
}
