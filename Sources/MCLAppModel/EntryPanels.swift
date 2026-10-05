import Foundation
import MCLCore

/// One entry window's models: the main window (`vfo` 0) or the VFO B / rig 2 window `entry-vfob` (`vfo` 1, Kotlin
/// `EntryPanel(state, vfo = 1)` in SO2V/SO2R). Kotlin keeps the fields, the suggestions and the CQ repeat loop per
/// panel; the rigs, the keyers, the log and the info strip are shared.
@MainActor
public struct EntryPanel {
    public let vfo: Int
    public let entry: EntryModel
    public let suggestions: SuggestionsModel
}

extension AppModel {

    /// The entry window of `vfo` (0 = main, 1 = `entry-vfob`).
    public func panel(vfo index: Int) -> EntryPanel {
        index == 1 ? vfoB : EntryPanel(vfo: 0, entry: entry, suggestions: suggestions)
    }

    /// The models of the VFO B window. They exist for the app's lifetime; the window (and so the panel) is shown
    /// only while `rig.vfo.twoEntryWindows` (Kotlin `if (state.twoEntryWindows) Window(…)`). While it is hidden
    /// (`EntryModel.isWindowShown` false) the panel is never the active one and its CQ repeat loop is idle.
    static func makeVfoB(_ dependencies: EntryModel.Dependencies, callData: CallDataModel, logbook: LogbookModel,
                         contest: ContestModel, clock: any RescoreClock) -> EntryPanel {
        var second: EntryModel.Dependencies = dependencies
        second.vfo = 1
        let entry = EntryModel(second)
        let suggestions = SuggestionsModel(callData: callData, logbook: logbook, contest: contest, clock: clock)
        suggestions.formSource = { [weak entry] in
            entry?.form ?? EntryForm()
        }
        suggestions.formSink = { [weak entry] form in
            entry?.applyCallHistoryPrefill(form)
        }
        entry.suggestionSource = EntryModel.SuggestionSource(
            list: { [weak suggestions] in suggestions?.suggestions ?? [] },
            pick: { [weak suggestions] in suggestions?.scpPick ?? -1 },
            setPick: { [weak suggestions] in suggestions?.setScpPick($0) })
        suggestions.observe()
        return EntryPanel(vfo: 1, entry: entry, suggestions: suggestions)
    }

    /// The VFO B window and the rigs (Kotlin: every panel follows `state.cat`, reacts to the footswitch when active
    /// and runs its own CQ repeat loop): `rig.attach`, the footswitch, the typed call of the active window, the
    /// contest activation, the input gate and the window's CQ repeat loop (only while the window is shown).
    static func wireVfoB(_ model: AppModel, radio: Radio, clock: any RescoreClock) -> CqRepeatRunner {
        let main: EntryModel = model.entry
        let second: EntryModel = model.vfoB.entry
        let rig: RigModel = radio.rig
        rig.attach(second)
        // Kotlin `state.typedCall` is written by the panel the operator types in; here: the active window's call.
        rig.typedCall = { [weak main, weak second, weak rig] in
            let typing: EntryModel? = rig?.vfo.twoEntryWindows == true && rig?.vfo.activeVfo == 1 ? second : main
            return typing?.form.call ?? ""
        }
        radio.peripherals.pressObservers.append { [weak second] in
            second?.footswitchPressed()
        }
        second.inputGate = { [weak model] in
            model?.acceptsEntryInput ?? false
        }
        let runner = CqRepeatRunner(entry: second, operating: model.operating, keyer: radio.keyer,
                                    config: model.config, status: model.status, clock: clock)
        runner.present = { [weak rig, weak second] in
            (rig?.vfo.twoEntryWindows ?? false) && (second?.isWindowShown ?? false)
        }
        return runner
    }

    /// The info strip's rig and keyer items (`EP:1282-1290`): ● REC, ANT, RIT and LADĚNÍ.
    static func wireInfoStrip(_ model: AppModel) {
        var next: InfoStripModel.Sources = model.infoStrip.sources
        next.recording = { [weak recording = model.recording] in
            recording?.isRecording ?? false
        }
        next.antennaName = { [weak rig = model.rig] in
            rig?.antenna.current?.name
        }
        next.ritHz = { [weak rig = model.rig] in
            rig?.rit.ritHz ?? 0
        }
        next.tuning = { [weak keyer = model.keyer] in
            keyer?.isTuning ?? false
        }
        model.infoStrip.sources = next
    }
}
