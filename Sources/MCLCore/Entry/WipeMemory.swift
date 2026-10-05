/// The fields cleared by Alt+W (Kotlin `WipedEntry`, `EP:1384`).
public struct WipedEntry: Equatable, Sendable {
    public let call: String
    public let exch: String
    public let contestExchange: JavaLinkedMap<String>
    public let rstRcvd: String

    public init(call: String, exch: String, contestExchange: JavaLinkedMap<String>, rstRcvd: String) {
        self.call = call
        self.exch = exch
        self.contestExchange = contestExchange
        self.rstRcvd = rstRcvd
    }
}

/// N1MM "unwipe": what Alt+W cleared, so that a second Alt+W into empty fields brings it back (Kotlin `lastWiped`,
/// `EP:338-339, 569-589`).
///
/// Who changes the memory (v1.1.1):
/// - Alt+W (`wipeReversible`) saves the call/exchange when either is non-blank, or restores into an effectively
///   empty form;
/// - Ctrl+W (`ShortcutAction.WIPE`, `EP:886`) and every logged QSO (`EP:546, 565`) forget it (`clear()`);
/// - Esc (`EP:992`), the ESM/macro `{WIPE}`, a jump to the CQ frequency and the wipe after logging do **not** touch it.
public struct WipeMemory: Equatable, Sendable {

    public private(set) var lastWiped: WipedEntry?

    public init(lastWiped: WipedEntry? = nil) {
        self.lastWiped = lastWiped
    }

    /// Forgets the wiped fields.
    public mutating func clear() {
        lastWiped = nil
    }

    /// The outcome of Alt+W.
    public struct Outcome: Equatable, Sendable {
        /// The form afterwards.
        public let form: EntryForm
        /// The memory afterwards.
        public let memory: WipeMemory
        /// `"Obnoveno <call>"` after a restore (not translated in Kotlin); `nil` after a wipe.
        public let status: EntryStatus?
        /// `true` = the fields were wiped (the app also does the rest of Kotlin `wipe()`: typed call, ESM progress,
        /// spot origin, focus); `false` = restored (the app sets the typed call to the restored call and focuses
        /// the call field, `EP:575, 582`).
        public let wiped: Bool
    }

    /// Kotlin `wipeReversible()`. The form is "effectively empty" when the call and the generic exchange are blank
    /// and every contest value is blank or equal to the sent report (the prefilled RST fields). Restoring brings back
    /// call, generic and contest exchange (in the saved order) and the received report; the touch marks and the sent
    /// report stay as they are. Otherwise the call/exchange are saved — only when one of them is non-blank (a form
    /// with contest values alone keeps the previous memory) — and the form is wiped.
    ///
    /// - Parameter rstFieldIds: the report fields of the current composition (`EntryForm.wiped`).
    public func wipeReversible(form: EntryForm, contestActive: Bool, rstFieldIds: [String?]) -> Outcome {
        let empty: Bool = KotlinStrings.isBlank(form.call) && KotlinStrings.isBlank(form.exch)
            && form.contestExchange.entries.allSatisfy { entry in
                guard let value = entry.value else { return true }
                return KotlinStrings.isBlank(value) || JavaText.equals(value, form.rstSent)
            }
        if empty, let saved = lastWiped {
            var restored = form
            restored.call = saved.call
            restored.exch = saved.exch
            restored.contestExchange = saved.contestExchange
            restored.rstRcvd = saved.rstRcvd
            return Outcome(form: restored, memory: WipeMemory(), status: .verbatim("Obnoveno " + saved.call),
                           wiped: false)
        }
        var memory = self
        if !KotlinStrings.isBlank(form.call) || !KotlinStrings.isBlank(form.exch) {
            memory.lastWiped = WipedEntry(call: form.call, exch: form.exch, contestExchange: form.contestExchange,
                                          rstRcvd: form.rstRcvd)
        }
        return Outcome(form: form.wiped(contestActive: contestActive, rstFieldIds: rstFieldIds), memory: memory,
                       status: nil, wiped: true)
    }
}
