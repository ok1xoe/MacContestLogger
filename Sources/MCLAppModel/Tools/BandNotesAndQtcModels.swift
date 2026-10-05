import Foundation
import MCLCore
import Observation

/// The band notes (Kotlin `AppState.addBandNote`/`removeBandNote` and `BandNotesWindow.kt`): notes by frequency or by
/// band, stored in the config. The Bandmap reads the same `config.bandNotes`, so a change shows there at once; saved
/// with `saveSilently` like Kotlin's `runCatching { configStore.save(config) }`.
@Observable @MainActor
public final class BandNotesModel {

    /// Kotlin `bandNotesRevision`.
    public private(set) var revision = 0

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let rig: RigModel

    init(config: ConfigModel, status: StatusModel, language: LanguageModel, rig: RigModel) {
        self.config = config
        self.status = status
        self.language = language
        self.rig = rig
    }

    /// The notes sorted by band and frequency (`BandNotesEditing.sorted`).
    public var notes: [BandNote] {
        BandNotesEditing.sorted(config.config.bandNotes)
    }

    /// The frequency field as the form starts.
    public var defaultFrequencyText: String {
        BandNotesEditing.frequencyFieldText(tunedFreqHz: rig.tuning.tunedFreqHz)
    }

    public func rowText(_ note: BandNote) -> String {
        BandNotesEditing.rowText(note)
    }

    /// „Přidat": a number is a frequency in kHz, anything else a band name; an invalid form shows `invalidText`.
    @discardableResult
    public func add(freq: String, text: String) -> Bool {
        guard let note = BandNotesEditing.parse(freq: freq, text: text) else {
            status.showVerbatim(BandNotesEditing.invalidText(language.translator))
            return false
        }
        config.config.bandNotes = config.config.bandNotes + [note]
        config.saveSilently()
        revision += 1
        return true
    }

    /// „Smazat".
    public func remove(_ note: BandNote) {
        config.config.bandNotes = BandNotesEditing.removing(note, from: config.config.bandNotes)
        config.saveSilently()
        revision += 1
    }

    /// The 📝 item of the info strip: the note nearest to the tuned frequency within 2 kHz (`EP:1287`).
    public func stripNote() -> String? {
        _ = revision
        let hz: Int = Int(clamping: rig.tuning.tunedFreqHz)
        return BandNotes.near(config.config.bandNotes, freqHz: hz, toleranceHz: 2_000)?.text
    }
}

/// The QTC window (`QtcWindow.kt`, WAE DX Contest): the received and sent series stored in the database. Here QTC is
/// session and model state only — sending a series over CW belongs to the keyer.
///
/// The list is `ContestModel.qtcs`; a save or a delete runs on the logbook's queue, then the list is read again and the
/// QTC count goes into the score (`setQtcCount` and the recount).
@Observable @MainActor
public final class QtcModel {

    /// „Poslat QTC" (`true`) or „Přijmout QTC".
    public var sendMode = false
    /// The partner station (upper case).
    public var partner = ""
    /// The series number typed for a received series (`3/10`).
    public var group = ""
    /// The received lines, one per row.
    public var received = ""

    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let database: DatabaseModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let rig: RigModel
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Kotlin `state.typedCall` (wired by the app).
    @ObservationIgnored public var typedCall: @MainActor () -> String = { "" }
    /// Set by the quit: nothing writes the database after it started closing.
    @ObservationIgnored var isShuttingDown: () -> Bool = { false }

    struct Dependencies {
        let contest: ContestModel
        let logbook: LogbookModel
        let database: DatabaseModel
        let status: StatusModel
        let language: LanguageModel
        let rig: RigModel
        let now: @Sendable () -> Date
    }

    init(_ dependencies: Dependencies) {
        contest = dependencies.contest
        logbook = dependencies.logbook
        database = dependencies.database
        status = dependencies.status
        language = dependencies.language
        rig = dependencies.rig
        now = dependencies.now
    }

    private var translator: Translator {
        language.translator
    }

    /// The exchanged QTCs (Kotlin `state.qtcs`), oldest first.
    public var qtcs: [QtcRecord] {
        contest.qtcs
    }

    /// The contest's QTC rules; `nil` = the contest has no QTC („Aktivní závod QTC nemá").
    public var config: ContestDefinition.Qtc? {
        _ = contest.definition
        return contest.runtime.qtcConfig
    }

    /// The window opened: the partner is the typed call, else the last QSO's call.
    public func open() {
        let typed: String = typedCall()
        partner = KotlinStrings.isBlank(typed) ? (logbook.rows.last?.call ?? "") : typed
    }

    public func setPartner(_ text: String) {
        partner = text.uppercased()
    }

    /// `zbývá %s z %s QTC · celkem %s QTC`; `nil` without QTC rules.
    public var remainingText: String? {
        guard let config else { return nil }
        return QtcSession.remainingText(partner: partner, qtcs: qtcs, config: config, translate: translator)
    }

    /// The number of the next sent series.
    public var nextGroup: Int {
        QtcSession.nextGroup(qtcs: qtcs)
    }

    /// The lines of the next series to send: the QSOs not yet reported to the partner, within the limits.
    public var candidateLines: [QtcPlanner.Line] {
        guard let config else { return [] }
        let normalized: String = KotlinStrings.trim(partner)
        let picked: [Qso] = QtcPlanner.candidates(logbook.rows, normalized, qtcs, config.maxPerStationOrDefault,
                                                  config.groupSizeOrDefault)
        return picked.compactMap { QtcPlanner.toLine($0) }
    }

    /// `Série n/k:` above the lines.
    public func seriesTitle(count: Int) -> String {
        QtcSession.seriesTitle(groupNr: nextGroup, count: count, translate: translator)
    }

    /// The text „Odvysílat CW" would send for these lines (the keyer sends it, not this model).
    public func cwText(lines: [QtcPlanner.Line]) -> String {
        QtcSession.cwSendText(groupNr: nextGroup, lines: lines)
    }

    /// The CW lines shown under „Série n/k:" (`text.drop(1)`: the header is not shown), the text „Odvysílat CW" sends
    /// is `cwText(lines:)`.
    public func cwDisplayLines(lines: [QtcPlanner.Line]) -> [String] {
        Array(QtcPlanner.cwText(nextGroup, lines).dropFirst())
    }

    /// „Aktivní závod QTC nemá (WAE DX Contest)."
    public var noQtcText: String {
        language.tr("Aktivní závod QTC nemá (WAE DX Contest).")
    }

    /// The received lines parsed (`QtcSession.parseLines`).
    public var parsedReceived: QtcSession.Parsed {
        QtcSession.parseLines(received)
    }

    /// „Nečitelné řádky: …"; `nil` when every line reads.
    public var badLinesText: String? {
        parsedReceived.badText(translator)
    }

    public func rowText(_ record: QtcRecord) -> String {
        QtcSession.rowText(record)
    }

    /// Kotlin `saveQtcGroup`: checks the rules and the per-station limit, stores one record per line on the logbook's
    /// queue, reads the list again (the QTC count goes into the score) and shows the result. `false` = refused, with the
    /// status of the reason.
    @discardableResult
    public func save(sent: Bool, partner: String, group groupNr: Int, lines: [QtcPlanner.Line]) async -> Bool {
        if isShuttingDown() { return false }
        if let refusal = QtcSession.validate(partner: partner, lines: lines, qtcs: qtcs, config: config,
                                             translate: translator) {
            status.showVerbatim(refusal)
            return false
        }
        let contestId: String = logbook.activeContestId
        let records: [QtcRecord] = QtcSession.records(
            sent: sent, partner: partner, groupNr: groupNr, lines: lines,
            contestId: KotlinStrings.nilIfBlank(contestId), now: now(), freqHz: rig.tuning.tunedFreqHz,
            rigMode: rig.activeState?.mode?.rawValue)
        do {
            try await database.handle.run { access in
                for record in records {
                    _ = try access.repository.insertQtc(record)
                }
            }
        } catch {
            status.showVerbatim(ErrorText.message(error))
            await contest.reloadQtcs(contestId: contestId)
            return false
        }
        await contest.reloadQtcs(contestId: contestId)
        status.showVerbatim(QtcSession.savedText(sent: sent, groupNr: groupNr, count: lines.count, partner: partner,
                                                 total: qtcs.count, translate: translator))
        return true
    }

    /// „Uložit přijaté QTC": the typed series number and the parsed lines; the form is cleared after a save.
    @discardableResult
    public func saveReceived() async -> Bool {
        let parsed: QtcSession.Parsed = parsedReceived
        guard parsed.canSave else { return false }
        let saved: Bool = await save(sent: false, partner: partner, group: QtcSession.receivedGroupNr(group),
                                     lines: parsed.lines)
        if saved {
            received = ""
            group = ""
        }
        return saved
    }

    /// „Potvrzeno — uložit": the next series as sent.
    @discardableResult
    public func saveSent() async -> Bool {
        await save(sent: true, partner: partner, group: nextGroup, lines: candidateLines)
    }

    /// „Smazat": the record leaves the database, the list is read again.
    public func delete(_ id: Int64) async {
        if isShuttingDown() { return }
        let contestId: String = logbook.activeContestId
        do {
            try await database.handle.run { access in
                try access.repository.deleteQtc(id: id)
            }
        } catch {
            status.showVerbatim(ErrorText.message(error))
        }
        await contest.reloadQtcs(contestId: contestId)
    }
}

/// The propagation forecast window (`PropagationWindow.kt`): 24 hours × bands on the path to a callsign. The SFI comes
/// from the last WWV message of the DX cluster at first and can be overwritten; no data is fetched.
@Observable @MainActor
public final class PropagationWindowModel {

    /// The callsign or prefix typed in the window (upper case); blank = the typed call of the entry window.
    public private(set) var target = ""
    /// The SFI field (three digits at most).
    public private(set) var sfiText = "120"

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let dxCluster: DxClusterModel
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var cache: (key: String, view: PropagationRows.View)?
    /// Kotlin `state.typedCall` (wired by the app).
    @ObservationIgnored public var typedCall: @MainActor () -> String = { "" }

    init(config: ConfigModel, contest: ContestModel, language: LanguageModel, dxCluster: DxClusterModel,
         now: @escaping @Sendable () -> Date) {
        self.config = config
        self.contest = contest
        self.language = language
        self.dxCluster = dxCluster
        self.now = now
    }

    /// The window opened: the target is the typed call, the SFI that of the last WWV (`120` without one).
    public func open() {
        target = typedCall()
        sfiText = PropagationRows.defaultSfiText(wwv: dxCluster.lastWwv)
        cache = nil
    }

    public func setTarget(_ text: String) {
        target = text.uppercased()
    }

    public func setSfi(_ text: String) {
        sfiText = PropagationRows.filterSfi(text)
    }

    /// The text of the target field (`target.ifBlank { typedCall }`).
    public var shownTarget: String {
        KotlinStrings.isBlank(target) ? typedCall() : target
    }

    /// The table or the message above it, for the current hour.
    public var view: PropagationRows.View {
        let date: Date = now()
        let hour: Int64 = Int64(date.timeIntervalSince1970 / 3_600)
        let call: String = PropagationRows.call(target: target, typedCall: typedCall())
        let grid: String = config.config.station.gridSquare
        let key: String = [call, sfiText, String(hour), grid, language.code].joined(separator: "\u{1F}")
        if let cache, cache.key == key {
            return cache.view
        }
        let computed: PropagationRows.View = PropagationRows.view(
            target: target, typedCall: typedCall(), sfiText: sfiText, myGrid: grid, lookup: contest.runtime.dxccLookup,
            now: date, translate: language.translator)
        cache = (key, computed)
        return computed
    }

    public var footnote: String {
        PropagationRows.footnote(language.translator)
    }
}
