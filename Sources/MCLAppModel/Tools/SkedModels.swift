import Foundation
import MCLCore
import Observation

/// The skeds of the active contest (Kotlin `SkedWindow.kt`, `AppState` `addSked`/`removeSked`/`tuneToSked`): arranged
/// contacts stored in the contest's setup (`ContestModel.updateSetup`).
///
/// Clicking a sked tunes the rig (`RigModel.qsy`: the frequency, the mode and the call into the entry field); nothing
/// transmits, and the watchers only report.
@Observable @MainActor
public final class SkedModel {

    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let rig: RigModel
    @ObservationIgnored private let now: @Sendable () -> Date

    struct Dependencies {
        let contest: ContestModel
        let status: StatusModel
        let language: LanguageModel
        let rig: RigModel
        let now: @Sendable () -> Date
    }

    init(_ dependencies: Dependencies) {
        contest = dependencies.contest
        status = dependencies.status
        language = dependencies.language
        rig = dependencies.rig
        now = dependencies.now
    }

    /// Kotlin `skeds()`: the active contest's skeds in time order (`SkedPlanner.sorted`); none without a contest.
    public var skeds: [SkedEntry] {
        SkedPlanner.sorted(contest.activeSetup?.skeds ?? [])
    }

    /// The unsorted list, as the watchers read it.
    var storedSkeds: [SkedEntry] {
        contest.activeSetup?.skeds ?? []
    }

    /// Kotlin `state.contest.isActive`: without a contest the window says „Skedy patří k závodu — otevři závod".
    public var contestActive: Bool {
        contest.isActive
    }

    /// The text of an empty list.
    public var emptyText: String {
        language.tr(contest.isActive ? "Žádné skedy" : "Skedy patří k závodu — otevři závod")
    }

    /// The tuned frequency in kHz as the form starts (`%.1f`, US).
    public var defaultFrequencyText: String {
        BandNotesEditing.frequencyFieldText(tunedFreqHz: rig.tuning.tunedFreqHz)
    }

    /// The radio's mode, `CW` without a rig state.
    public var defaultMode: String {
        rig.activeState?.mode?.rawValue ?? "CW"
    }

    /// `HHmm` UTC of a sked, `?` when unparseable (`AppState.skedTime`).
    public func skedTime(_ sked: SkedEntry) -> String {
        SkedEditing.skedTime(sked)
    }

    /// Whether the sked is due now (a minute before to five minutes after) or past; the window refreshes it every 15 s.
    public func state(of sked: SkedEntry) -> (due: Bool, past: Bool) {
        let at = JavaInstant(date: now())
        let due: Bool = (try? SkedPlanner.isDue(sked, now: at)) ?? false
        let past: Bool = (try? SkedPlanner.isPast(sked, now: at)) ?? false
        return (due, past)
    }

    /// „Přidat": validates in Kotlin's order (call, time, frequency), stores the sked in the contest's setup and shows
    /// `Sked <call> v <HHmm> UTC na <kHz>`; a failure shows its text. `freqText` is the kHz field.
    @discardableResult
    public func add(call: String, freqText: String, mode: String, timeText: String, note: String) async -> Bool {
        let hz: Int = BulkEdit.parseFrequencyKHz(freqText) ?? 0
        let result = SkedEditing.add(call: call, freqHz: hz, mode: mode, timeText: timeText, note: note,
                                     now: JavaInstant(date: now()))
        switch result {
        case .failure(let error):
            status.showVerbatim(error.text(language.translator))
            return false
        case .success(let entry):
            let stored: Bool = await contest.updateSetup { $0.skeds.append(entry) }
            guard stored else { return false }
            status.showVerbatim(SkedEditing.addedText(entry))
            return true
        }
    }

    /// „Smazat": the sked leaves the setup.
    public func remove(_ id: String) async {
        _ = await contest.updateSetup { setup in
            setup.skeds = setup.skeds.filter { $0.id != id }
        }
    }

    /// A click on a sked: QSY to its frequency and mode, the call into the entry field (`tuneToSked`).
    public func tune(_ sked: SkedEntry) {
        rig.qsy(Int64(sked.freqHz), mode: Mode.from(adif: sked.mode), call: sked.call)
    }

    /// The SKED item of the info strip: the next sked that starts within ten minutes (`EP:1295-1299`).
    public func stripSked() -> InfoStripSked? {
        let at = JavaInstant(date: now())
        guard let next = (try? SkedPlanner.next(storedSkeds, now: at)) ?? nil,
              let when = SkedPlanner.at(next),
              let limit = JavaInstant.ofEpochSecond(at.epochSecond + 600, Int64(at.nano)),
              when < limit else {
            return nil
        }
        return InfoStripSked(time: SkedEditing.skedTime(next), call: next.call)
    }
}

/// The reminders of the skeds (Kotlin `startSkedWatch`, `AS:2625-2642`): every 15 s, from the start of the app, also
/// with the window closed. Each sked is announced once (the set lives in memory only); the status line gets `⏰ text`,
/// the message log the text. It only reports.
@MainActor
public final class SkedWatcher {

    /// Kotlin `delay(15_000)`.
    public static let periodMilliseconds = 15_000

    @ObservationIgnored private var watch = SkedWatch()
    private let skeds: SkedModel
    private let status: StatusModel
    private let messages: MessagesModel
    private let now: @Sendable () -> Date
    private var tick: RepeatingTick?

    init(skeds: SkedModel, status: StatusModel, messages: MessagesModel, clock: any RescoreClock,
         now: @escaping @Sendable () -> Date) {
        self.skeds = skeds
        self.status = status
        self.messages = messages
        self.now = now
        tick = RepeatingTick(clock: clock, milliseconds: Self.periodMilliseconds) { [weak self] in
            self?.check()
        }
    }

    public var isRunning: Bool {
        tick?.isRunning ?? false
    }

    /// The ids announced so far.
    public var reminded: Set<String> {
        watch.reminded
    }

    /// The first check at once (Kotlin's loop checks before its first delay), then every 15 s.
    public func start() {
        guard let tick, !tick.isRunning else { return }
        check()
        tick.start()
    }

    public func stop() {
        tick?.stop()
    }

    /// One check.
    func check() {
        let date: Date = now()
        let due: [String] = watch.due(skeds: skeds.storedSkeds, now: JavaInstant(date: date))
        for text in due {
            status.showVerbatim(SkedWatch.statusLine(text))
            messages.add(text, at: date)
        }
    }
}

/// The announcement of a new TOUR session (Kotlin `startTourWatch`, `AS:2606-2622`): every 5 s, from the start of the
/// app. The first check only remembers the session; a change while a contest is active is announced (status `⏱ text`,
/// message log).
@MainActor
public final class TourWatcher {

    /// Kotlin `delay(5_000)`.
    public static let periodMilliseconds = 5_000

    @ObservationIgnored private var watch = TourWatch()
    private let contest: ContestModel
    private let language: LanguageModel
    private let status: StatusModel
    private let messages: MessagesModel
    private let now: @Sendable () -> Date
    private var tick: RepeatingTick?

    init(contest: ContestModel, language: LanguageModel, status: StatusModel, messages: MessagesModel,
         clock: any RescoreClock, now: @escaping @Sendable () -> Date) {
        self.contest = contest
        self.language = language
        self.status = status
        self.messages = messages
        self.now = now
        tick = RepeatingTick(clock: clock, milliseconds: Self.periodMilliseconds) { [weak self] in
            self?.check()
        }
    }

    public var isRunning: Bool {
        tick?.isRunning ?? false
    }

    public func start() {
        guard let tick, !tick.isRunning else { return }
        check()
        tick.start()
    }

    public func stop() {
        tick?.stop()
    }

    /// One check.
    func check() {
        let date: Date = now()
        guard let text = watch.tick(tour: contest.tour, now: date, active: contest.isActive,
                                    translate: language.translator) else { return }
        status.showVerbatim(TourWatch.statusLine(text))
        messages.add(text, at: date)
    }
}
