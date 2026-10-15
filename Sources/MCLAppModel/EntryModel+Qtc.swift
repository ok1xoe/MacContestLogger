import Foundation
import MCLCore

extension QtcModel {
    /// The id of the QTC window in `WindowsModel`.
    public static let windowId = "qtc"
}

/// WAE QTC from the entry window (N1MM): Ctrl+Z toggles the QTC mode, `{DIGQTCR}` / `{DIGQTCS}` open the QTC window,
/// and the window's messages go out through this window's keyer — only on a key or a button, never by themselves.
extension EntryModel {

    /// N1MM Ctrl+Z: the QTC window closes when it is open; otherwise it opens to receive (a European station) or to
    /// send (elsewhere). A station outside Europe has the QSO in the window logged first (N1MM: „If you've forgotten to
    /// log the QSO first, Ctrl+Z will do it for you"); a European station in Run and CW may send the ask message
    /// first (Config → WAE, off by default).
    func toggleQtcMode() {
        guard let qtc else {
            unavailable()
            return
        }
        if windows.isOpen(QtcModel.windowId) {
            windows.setOpen(QtcModel.windowId, false)
            return
        }
        guard qtc.config != nil else {
            status.show("Aktivní závod QTC nemá (WAE DX Contest).")
            return
        }
        let role: QtcRules.Role = qtc.stationRole
        let call: String = KotlinStrings.trim(form.call)
        if role == .send, !call.isEmpty, exchangeValid, !isDupe, !operating.postContest {
            submit()
        }
        qtc.begin(send: role == .send, partner: call.isEmpty ? nil : call)
        windows.setOpen(QtcModel.windowId, true)
        if role == .receive, operating.isRun, form.mode == .cw, qtc.setup.flag(.ctrlZSendsAsk) {
            qtc.press(.ask)
        }
    }

    /// `{DIGQTCR}` / `{DIGQTCS}`: the QTC window opens to receive / send (WAE only).
    func openQtcWindow(send sending: Bool) {
        guard let qtc else {
            unavailable()
            return
        }
        guard qtc.config != nil else {
            status.show("Aktivní závod QTC nemá (WAE DX Contest).")
            return
        }
        let call: String = KotlinStrings.trim(form.call)
        qtc.begin(send: sending, partner: call.isEmpty ? nil : call)
        windows.setOpen(QtcModel.windowId, true)
    }

    /// A QTC window message: CW and a ready digital mode send it like an F-key message (`{QTC}` is the series
    /// header), phone plays it through the voice keyer (wav names, `[text]`), an unset TU sends the TU key (F3).
    public func sendQtc(_ outgoing: QtcMessages.Outgoing) {
        switch outgoing {
        case .tuKey:
            sendKeys([config.config.esm.keys.end], refocus: false)
        case .message(let text):
            if EsmFlow.isPhone(form.mode) {
                if operating.postContest {
                    show(.tr("Dodatečné zadání — nic se nevysílá (NOPOSTCONTEST ukončí)"))
                    return
                }
                if let message = ports.keyer.playVoiceText(text, hisCall: KotlinStrings.trim(form.call),
                                                           freqHz: form.freqHz) {
                    show(message)
                }
                return
            }
            let outcome: FunctionKeyOutcome = FunctionKeyRouter.sendQtcTemplate(text, context: functionKeyContext())
            applyTemplateOutcome(outcome)
        }
    }
}
