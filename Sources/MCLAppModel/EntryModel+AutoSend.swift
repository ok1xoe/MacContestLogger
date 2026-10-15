import Foundation
import MCLCore

/// N1MM „CW/PH AutoSend Threshold" (`AppConfig.autoSendThreshold`, Settings menu „Práh AutoSend (CW)…"): in Run and
/// CW the call goes out while it is typed once the threshold of characters after its last digit is reached; what is
/// typed on at its end follows. The ESM progress counts the call as sent, so the ESM Enter then sends only the
/// exchange (a call corrected meanwhile is resent by ESM as usual). Phone is not supported (the voice keyer cannot
/// speak a call letter by letter as it is typed).
extension EntryModel {

    /// The call typed now is the one AutoSend sent (the ESM Enter leaves the his-call key out).
    var autoSentCurrentCall: Bool {
        guard esmProgress.sentCall != nil, let sent = autoSentCall else { return false }
        return sent == Self.autoSendCall(form.call)
    }

    static func autoSendCall(_ call: String) -> String {
        KotlinStrings.uppercase(KotlinStrings.trim(call))
    }

    /// After the operator typed in the call field: sends the call or its new characters when AutoSend is due.
    func autoSendIfDue() {
        let threshold: Int = config.config.autoSendThreshold
        guard threshold > 0 else { return }
        let call: String = Self.autoSendCall(form.call)
        // A new QSO (the progress was reset) starts over.
        let sent: String? = esmProgress.sentCall != nil ? autoSentCall : nil
        if sent == nil {
            autoSentCall = nil
        }
        // 2BSIQ: typing here never interrupts the other radio's transmission.
        guard isRunHere, form.mode == .cw, isActivePanel, !operating.postContest, !otherRadioSending,
              config.config.cwKeyer.method != .none,
              let chunk = AutoSend.next(call: call, sent: sent, threshold: threshold) else { return }
        let message: CwMessage = CwMessageBuilder.build(chunk, functionKeyContext().cwBase)
        guard !message.isEmpty else { return }
        autoSentCall = call
        esmProgress = EsmProgress(exchangeSent: esmProgress.exchangeSent, myCallSent: esmProgress.myCallSent,
                                  sentCall: call)
        endCqRepeatOfOtherWindow()
        rig?.claimTx(vfo)
        if let status = ports.keyer.send(.cw(message, index: -1), settings: keyerSettings(opposite: false)) {
            show(status)
        }
    }
}
