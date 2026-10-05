/// State of the entry form as a value. Port of the `remember` state of `ui/EntryPanel.kt:148-162`
/// (call, frequency, mode, reports, generic and contest exchange, which fields the operator touched)
/// and of the pure functions over it (`applyDefaultRst`, `applyContestRst`, `wipe`, `EntryPanel.kt:326-351`).
/// What lives outside the form — the typed callsign broadcast, ESM progress, spot origin, focus — is the
/// app model's business; unwipe (Alt+W twice) is handled elsewhere.
public struct EntryForm: Equatable, Sendable {

    public var call: String = ""
    /// Frequency field text in kHz (`FrequencyText.formatKHz` fills it, `FrequencyText.parseHz` reads it).
    public var freqKHz: String = ""
    public var mode: Mode = .ssb
    public var rstSent: String = Mode.ssb.defaultRst
    public var rstRcvd: String = Mode.ssb.defaultRst
    /// Generic exchange outside a contest.
    public var exch: String = ""
    /// Received contest fields by field id (Kotlin `cexch`).
    public var contestExchange = JavaLinkedMap<String>()
    /// Contest fields the operator edited by hand — a mode change does not overwrite them with the
    /// default report (otherwise a CAT poll over a segment boundary would turn a received "57" into "59").
    /// `nil` = a field without an id (Kotlin keeps a `null` key too).
    public var touchedFields: Set<String?> = []
    /// The operator edited the sent report.
    public var rstSentTouched: Bool = false

    public init() {}

    /// `parseFreqHz(freqKHz)`.
    public var freqHz: Int64 { FrequencyText.parseHz(freqKHz) }

    /// Ids of the active contest fields that hold a report (type `RST` or `RS`), in field order
    /// (`rstFields`, `EntryPanel.kt:267-269`).
    public static func rstFieldIds(_ fields: [ContestDefinition.ExchangeField]) -> [String?] {
        fields.filter { $0.type == .RST || $0.type == .RS }.map(\.id)
    }

    /// Both reports to the mode default (`applyDefaultRst`).
    public mutating func applyDefaultRst(_ mode: Mode) {
        rstSent = mode.defaultRst
        rstRcvd = mode.defaultRst
    }

    /// Prefills the contest report fields with the mode default; hand-edited values stay
    /// (`applyContestRst`). The received free-mode report `rstRcvd` is not touched.
    public mutating func applyContestRst(_ mode: Mode, rstFieldIds: [String?]) {
        let value = mode.defaultRst
        for id in rstFieldIds where !touchedFields.contains(id) {
            contestExchange.put(id, value)
        }
        if !rstSentTouched {
            rstSent = value
        }
    }

    /// The operator typed into the sent report (`EntryPanel.kt:1126`).
    public mutating func editRstSent(_ text: String) {
        rstSent = text
        rstSentTouched = true
    }

    /// The operator typed into a contest field (`EntryPanel.kt:1151`): Kotlin `uppercase()` (= Java
    /// `toUpperCase(Locale.ROOT)`, `ß` → `SS`) and the field is marked as touched.
    public mutating func editContestField(_ id: String?, _ text: String) {
        contestExchange.put(id, JavaText.toUpperCase(text))
        touchedFields.insert(id)
    }

    /// The form after `wipe()`: call, generic and contest exchange cleared, touch marks reset, reports
    /// to the mode default and — in a contest — the report fields prefilled again (without that the next
    /// QSO could not be saved, the report is a required field). Frequency and mode stay.
    ///
    /// `rstFieldIds` are the report fields of the composition that called `wipe` — i.e. for the callsign
    /// being wiped, as in Kotlin, where `rstFields` is captured before `call` is cleared.
    public func wiped(contestActive: Bool, rstFieldIds: [String?]) -> EntryForm {
        var form = self
        form.call = ""
        form.exch = ""
        form.contestExchange = JavaLinkedMap()
        form.touchedFields = []
        form.rstSentTouched = false
        form.applyDefaultRst(mode)
        if contestActive {
            form.applyContestRst(mode, rstFieldIds: rstFieldIds)
        }
        return form
    }
}
