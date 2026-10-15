import Foundation
import MCLCore

/// N1MM's VHF-and-up helpers of the entry window: the grid square keys (Alt+= searches the typed call and grid in the
/// call history and shows the result in the Check window, Alt+- toggles the grid field through the call history's
/// grids) and the right-click on a band button (moves the last logged station to that band: a local spot there, or —
/// in a network with a call typed — a pass to the station working that band).
extension EntryModel {

    /// The id of the contest's grid (locator) field, `nil` when the contest has none.
    var gridFieldId: String? {
        guard contest.isActive else { return nil }
        return fields.first { $0.type == .LOCATOR }?.id
    }

    /// N1MM Alt+=: the Check window opens with the reverse call history lookup on, so the typed call and grid are
    /// searched in the call history and the log. Nothing typed, or a contest without a grid field, says so.
    func gridSearch() {
        guard let id = gridFieldId else {
            show(.tr(Self.noGridFieldKey))
            return
        }
        let grid: String = KotlinStrings.trim(form.contestExchange[id] ?? "")
        guard !KotlinStrings.isBlank(form.call) || !grid.isEmpty else {
            show(.tr(Self.gridSearchNothingKey))
            return
        }
        var settings = CheckSettings(config.config)
        if !settings.reverseEnabled || settings.hidden.contains(.reverse) {
            settings.reverseEnabled = true
            settings.hidden.remove(.reverse)
            settings.apply(to: &config.config)
            config.saveSilently()
            show(.tr(Self.gridSearchReverseOnKey))
        }
        windows.setOpen("check", true)
    }

    /// N1MM Alt+-: the grid field takes the next of the typed grid and the call history's grids of the typed call
    /// (three at most). Without a call history grid there is nothing to toggle.
    func toggleGrid() {
        guard let id = gridFieldId else {
            show(.tr(Self.noGridFieldKey))
            return
        }
        let call: String = CallStack.normalize(form.call)
        let history: [String] = GridToggle.historyGrids(call.isEmpty ? nil : callHistory?().lookup(call))
        guard !history.isEmpty else {
            show(.tr(Self.gridToggleNothingKey))
            return
        }
        let current: String = KotlinStrings.uppercase(KotlinStrings.trim(form.contestExchange[id] ?? ""))
        if gridToggleEntered?.call != call {
            gridToggleEntered = nil
        }
        if !current.isEmpty, !history.contains(current), gridToggleEntered?.grid != current {
            // A grid the operator typed: it stays in the cycle.
            gridToggleEntered = (call, current)
        }
        let candidates: [String] = GridToggle.candidates(entered: gridToggleEntered?.grid, history: history)
        guard let next = GridToggle.next(current: current, candidates: candidates, history: history) else { return }
        editContestField(id, next)
    }

    /// N1MM right-click on a band/mode button. In a network with a call typed, the call goes to the station working
    /// that band (`NetworkModel.passToBand`). Otherwise the rig goes to the band and mode (the last frequency used
    /// there, else the segment start `startKHz`) and the last logged call is stored in the band map there — a local
    /// spot, nothing is sent out.
    public func bandButtonSecondaryClick(band: Band, mode: Mode, startKHz: Double?) {
        if !KotlinStrings.isBlank(form.call), let network, network.passToBand(band, call: form.call) {
            return
        }
        let lastHz: Int64? = rig?.tuning.lastFrequency(on: band)
        let kHz: Double? = lastHz.map { Double($0) / 1000 } ?? startKHz
        guard let kHz else {
            unavailable()
            return
        }
        qsy(toKHz: kHz, mode: mode)
        guard let last = logbook.rows.last(where: { !$0.deleted && !KotlinStrings.isBlank($0.call) }),
              let spots = spotNavigation else { return }
        let hz: Int64 = BandStepping.qsyHz(kHz: kHz)
        guard hz > 0 else { return }
        spots.store(call: last.call, freqHz: hz)
        show(.tr(Self.bandButtonSpotKey, .string(KotlinStrings.uppercase(last.call)), .string(band.adif)))
    }

    static let noGridFieldKey = "Závod nemá pole lokátoru"
    static let gridSearchNothingKey = "Napiš volačku nebo lokátor, který se má hledat"
    static let gridSearchReverseOnKey = "Zpětné hledání v call history zapnuto (okno Check)"
    static let gridToggleNothingKey = "Call history nezná pro tuto volačku žádný lokátor"
    static let bandButtonSpotKey = "%s uložen do bandmapy na %s"
}
