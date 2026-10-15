import Foundation
import MCLCore

/// A request another window makes of the active entry window (Kotlin `EntryAction`, `AS:531`): the Digital Interface
/// window fires the messages from there while the focus stays in it.
public enum EntryWindowAction: Equatable, Sendable {
    /// F1–F12 (`index` 0…11); `opposite` = the other message set (Shift).
    case functionKey(Int, opposite: Bool)
    /// Enter: the ESM Enter, otherwise log the QSO.
    case enter
    /// Esc: `stopSending()`.
    case stopSending
    /// A Digital Interface message button (DI1…DI24, index from 0).
    case digitalButton(Int)
}

/// What the radio tool windows read from and hand to the entry windows (Kotlin `typedCall`, `prefillCall`,
/// `prefillExchange`, `currentExchange`, `entryAction` — `AS:525-540`), and the window models' factories.
extension AppModel {

    /// The active entry window (Kotlin `active`): the one whose panel is active, `nil` when none is (the VFO B
    /// window is active only while it is on screen).
    public var activeEntry: EntryModel? {
        if entry.isActivePanel {
            return entry
        }
        return vfoB.entry.isActivePanel ? vfoB.entry : nil
    }

    /// Kotlin `typedCall`: the call of the window the operator types in — here the active window's (the VFO B
    /// window only when it is the active one), as `rig.typedCall`.
    public var typedCall: String {
        let second: Bool = rig.vfo.twoEntryWindows && rig.vfo.activeVfo == 1
        return second ? vfoB.entry.form.call : entry.form.call
    }

    /// N1MM: typing in a window that takes no text (Statistics) goes on in the Entry window — the characters are
    /// added to the active window's call, which takes the focus with the caret at its end.
    public func typeIntoEntry(_ text: String) {
        let typed: String = text.filter { $0.isLetter || $0.isNumber || $0 == "/" }.uppercased()
        guard !typed.isEmpty else { return }
        let target: EntryModel = activeEntry ?? entry
        target.callChanged(target.form.call + typed)
        rig.focusCaretAtEnd = true
        rig.focusVfoRequest = target === entry ? 0 : 1
    }

    /// Kotlin `currentExchange`: the received contest exchange typed in the active window.
    public var currentExchange: JavaLinkedMap<String> {
        activeEntry?.form.contestExchange ?? JavaLinkedMap()
    }

    /// Kotlin `prefillCall = call` (`EP:205-211`): the active window takes the call as a call from a spot (a blank
    /// call does nothing) and the call field gets the focus. Kotlin keeps the request until a window is active; here
    /// it goes to the window active now (there always is one on screen).
    public func prefillCall(_ call: String) {
        activeEntry?.prefillCall(call)
    }

    /// Kotlin `prefillExchange = mapOf(id to value)` (`EP:214-219`): the non-blank values go into the active window's
    /// contest fields as they are (no touch mark), then the preview follows.
    public func prefillExchange(_ values: [(id: String?, value: String)]) {
        var map = JavaLinkedMap<String>()
        for item in values {
            map.put(item.id, item.value)
        }
        activeEntry?.prefillExchange(map)
    }

    /// Kotlin `entryAction = …` (`EP:839-850`): the active window runs it without taking the focus. Esc always
    /// stops: without an active window it runs the global `stopSending()` (a safety rule; Kotlin waits for an active
    /// panel).
    /// `perform` on a given entry window (the Digital Interface 2 works with the VFO B / rig 2 window); `nil` = the
    /// active one.
    public func perform(_ action: EntryWindowAction, on entry: EntryModel?) {
        guard let entry else {
            perform(action)
            return
        }
        run(action, on: entry)
    }

    public func perform(_ action: EntryWindowAction) {
        guard let target = activeEntry else {
            if action == .stopSending {
                _ = entry.stopSending()
            }
            return
        }
        run(action, on: target)
    }

    private func run(_ action: EntryWindowAction, on target: EntryModel) {
        switch action {
        case .functionKey(let index, let opposite):
            target.sendKeys([index], opposite: opposite, refocus: false)
        case .enter:
            if target.esmActive {
                target.esmEnter()
            } else {
                target.submit()
            }
        case .stopSending:
            _ = target.stopSending()
        case .digitalButton(let index):
            target.sendDigitalButton(index)
        }
    }

    // MARK: - window models

    /// The CW keyboard window's model (`cwkeyboard`).
    public func makeCwKeyboard() -> CwKeyboardModel {
        CwKeyboardModel(keyer: keyer, stop: { [weak self] in
            _ = self?.entry.stopSending()
        }, typedCall: { [weak self] in
            self?.typedCall ?? ""
        })
    }

    /// The CW reader window's model (`cwreader`).
    public func makeCwReader() -> CwReaderModel {
        CwReaderModel(audio: audio, config: config, clock: radioWindowClock, prefill: { [weak self] call in
            self?.prefillCall(call)
        })
    }

    /// The waterfall window's model (`waterfall`).
    public func makeWaterfall() -> WaterfallModel {
        let model = WaterfallModel(audio: audio, rig: rig, config: config, clock: radioWindowClock)
        // The Available window's speaker column reads the newest waterfall (nothing while it is closed).
        availMult.spectrum = { [weak model] in
            model?.spectrum()
        }
        // The spots over the spectrum, the `@frequency` spots of unknown signals and Shift+Up/Down.
        model.spotsProvider = { [weak self] lo, hi in
            self?.spectrumSpots(lowHz: lo, highHz: hi) ?? []
        }
        let buffer: SpotBuffer = dxCluster.spots
        let now: @Sendable () -> Date = dxCluster.now
        model.publishUnknown = { spots in
            Self.publishUnknownSpots(spots, buffer: buffer, now: now())
        }
        for panel in [panel(vfo: 0), vfoB] {
            panel.entry.spectrumJump = { [weak model] direction, fromHz in
                model?.jump(direction: direction, fromHz: fromHz) ?? false
            }
        }
        return model
    }

    /// The band map's spots between `lowHz` and `highHz` with their dupe and new-multiplier state (outside a
    /// contest neither) and the marks (Alt+M) as non-workable.
    func spectrumSpots(lowHz: Double, highHz: Double) -> [SpectrumSpot] {
        let inRange: [DxSpot] = bandmap.spots().filter { Double($0.freqHz) >= lowHz && Double($0.freqHz) <= highHz }
        guard !inRange.isEmpty else { return [] }
        let analyzer: SpotAnalyzer = bandmap.analyzer()
        let scored: Bool = contest.isActive
        return inRange.map { spot in
            let status: SpotStatus? = scored ? analyzer.spotStatus(spot) : nil
            return SpectrumSpot(call: spot.dxCall, freqHz: Double(spot.freqHz), dupe: status?.dupe ?? false,
                                mult: status?.newMult ?? false, nonWorkable: spot.spotter == SpotActions.markSpotter,
                                generated: spot.spotter == SpectrumSignals.unknownSpotter)
        }
    }

    /// The `@frequency` spots of the spectrum replace the previous ones in the buffer; each stays
    /// `SpectrumSignals.unknownSpotSeconds` unless seen again.
    nonisolated static func publishUnknownSpots(_ spots: [(call: String, freqHz: Int)], buffer: SpotBuffer, now: Date) {
        let calls: Set<String> = Set(spots.map(\.call))
        _ = buffer.removeAll { $0.spotter == SpectrumSignals.unknownSpotter && !calls.contains($0.dxCall) }
        for spot in spots {
            buffer.addUntil(DxSpot(spotter: SpectrumSignals.unknownSpotter, freqHz: spot.freqHz, dxCall: spot.call,
                                   comment: "", selfSpotted: true),
                            until: now.addingTimeInterval(SpectrumSignals.unknownSpotSeconds))
        }
    }

    /// The Digital Interface window's model (`digitalinterface`).
    public func makeDigitalInterface(index: Int = 0) -> DigitalInterfaceModel {
        DigitalInterfaceModel(DigitalInterfaceModel.Dependencies(
            index: index, config: config, contest: contest, digital: keyer.digital, lane: keyer.lane, clock: radioWindowClock,
            app: self))
    }
}
