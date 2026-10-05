import Foundation
import MCLCore

/// "Odvysílat CW" of the QTC window (Kotlin `QtcWindow.kt:83-85`): the series header and the lines go out as free CW
/// text addressed to the partner, through `KeyerModel.sendCwText` — so the simulator takes it while one runs and the TX
/// gate applies otherwise. Only the button calls it; nothing is sent by itself.
@MainActor
public struct QtcSending {
    let keyer: KeyerModel

    /// Sends series `groupNr` with `lines` to `partner`; nothing for an empty series (the button is disabled then).
    public func send(groupNr: Int, lines: [QtcPlanner.Line], partner: String) {
        guard !lines.isEmpty else { return }
        keyer.sendCwText(QtcSession.cwSendText(groupNr: groupNr, lines: lines), call: KotlinStrings.trim(partner))
    }
}
