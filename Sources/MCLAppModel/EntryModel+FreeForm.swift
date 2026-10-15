import Foundation
import MCLCore

/// N1MM's free-form exchange box (`exchange.freeForm: true`, ARRL Sweepstakes): one box instead of the received
/// fields; its words are assigned to the fields by `ExchangeFreeForm` on every keystroke, and a callsign typed in it
/// replaces the logged call.
extension EntryModel {

    /// The active contest takes its exchange in one free-form box.
    public var freeFormExchange: Bool {
        contest.isActive && contest.definition?.exchange?.freeForm == true
    }

    /// The fields of the Tab order: the one box in a free-form contest, else the received fields.
    public var focusFields: [ContestDefinition.ExchangeField] {
        guard freeFormExchange else { return fields }
        return [ContestDefinition.ExchangeField(id: ExchangeFreeForm.boxId, type: .TEXT, required: false,
                                                source: nil, appliesWhen: nil, validation: nil)]
    }

    /// The box text: what the operator typed while it still gives the form's values, otherwise the values filled in
    /// elsewhere (call history, a spot, a wipe) in field order.
    public var freeFormText: String {
        if let raw = freeFormRaw, ExchangeFreeForm.parse(raw, fields: fields).values == form.contestExchange {
            return raw
        }
        return ExchangeFreeForm.text(form.contestExchange, fields: fields)
    }

    /// The interpretation under the box (`nr 123 · prec A · ck 72 · sec OH`).
    public var freeFormPreview: String {
        ExchangeFreeForm.preview(ExchangeFreeForm.parse(freeFormText, fields: fields), fields: fields)
    }

    /// The call typed in the box (logged instead of the call field's), `nil` = none.
    var freeFormCall: String? {
        guard freeFormExchange else { return nil }
        return ExchangeFreeForm.parse(freeFormText, fields: fields).call
    }

    /// The operator typed into the box.
    public func editFreeForm(_ text: String) {
        let upper: String = KotlinStrings.uppercase(text)
        let result = ExchangeFreeForm.parse(upper, fields: fields)
        autoFilled = [:]
        lastEditedField = ExchangeFreeForm.boxId
        freeFormRaw = upper
        form.contestExchange = result.values
        form.touchedFields = Set(result.values.keys)
        updatePreview()
    }

    /// A word put into the box from elsewhere (Digital Interface Cmd+click) goes after what is typed.
    func appendFreeForm(_ word: String) {
        let current: String = freeFormText
        editFreeForm(current.isEmpty ? word : current + " " + word)
    }
}
