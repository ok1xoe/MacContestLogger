import Foundation
import MCLCore
import Observation

/// The Move Multipliers window (Kotlin `MoveMultipliersWindow.kt`, `AppState.requestMove`/`moveFrequencyHz`,
/// `AS:1621-1642`): the stations of the latest QSOs that would be a new multiplier on another band, the "QSY?" request
/// and the "→" retune.
///
/// Both actions run only when the operator presses a button: "QSY?" sends `PSE QSY <kHz>` through
/// `KeyerModel.sendCwText` — so the simulator and the TX gate apply — for a CW QSO and only shows a hint otherwise;
/// "→" retunes the rig (a fake in tests). Nothing is sent or tuned by itself.
@Observable @MainActor
public final class MoveMultsModel {

    /// One station of the list with its candidate bands.
    public struct Row: Identifiable {
        public let qso: Qso
        public let candidates: [MoveMultipliers.Candidate]

        public var id: String {
            qso.uuid.isEmpty ? String(qso.id ?? 0) : qso.uuid
        }
    }

    struct Dependencies {
        let contest: ContestModel
        let logbook: LogbookModel
        let operating: OperatingModel
        let rig: RigModel
        let keyer: KeyerModel
        let status: StatusModel
        let language: LanguageModel
        let now: @Sendable () -> Date
    }

    @ObservationIgnored private let deps: Dependencies

    init(_ dependencies: Dependencies) {
        deps = dependencies
    }

    /// Kotlin `state.contest.isActive`: outside a contest the window only says so.
    public var isContestActive: Bool {
        deps.contest.isActive
    }

    /// The window's rows: the latest 25 QSOs first, with at least one candidate band (reads the log and the score, so a
    /// view that reads it follows both).
    public var rows: [Row] {
        guard deps.contest.isActive else { return [] }
        _ = deps.contest.score
        let runtime: ContestRuntime = deps.contest.runtime
        let now: Date = deps.now()
        let candidates: (Qso) -> [MoveMultipliers.Candidate] = { qso in
            runtime.moveCandidates(qso, at: now)
        }
        let qsos: [Qso] = deps.logbook.rows
        let found = MoveRequest.rows(qsos: qsos, candidates: candidates)
        var rows: [Row] = []
        for entry in found {
            rows.append(Row(qso: entry.qso, candidates: entry.candidates))
        }
        return rows
    }

    /// Kotlin `moveFrequencyHz(band)`: my CQ frequency on the band, otherwise the last frequency used on it.
    public func frequencyHz(_ band: Band) -> Int64? {
        MoveRequest.frequencyHz(band: band, cq: deps.operating.cqFrequency(band: band),
                                last: deps.rig.tuning.lastFrequency(on: band))
    }

    /// "QSY?" (Kotlin `requestMove(qso, bandAdif)`): CW sends `PSE QSY <kHz>` to the station, any other mode only
    /// hints what to say; the status follows either way.
    public func request(_ qso: Qso, band bandAdif: String) {
        guard let band = Band.from(adif: bandAdif),
              let request = MoveRequest.request(qso: qso, bandAdif: bandAdif, hz: frequencyHz(band),
                                                translate: deps.language.translator) else { return }
        if let text = request.cwText {
            deps.keyer.sendCwText(text, call: request.hisCall)
        }
        deps.status.showVerbatim(request.status)
    }

    /// "→": retunes the rig to the band's frequency, or says there is none yet.
    public func tune(band bandAdif: String) {
        if let band = Band.from(adif: bandAdif), let hz = frequencyHz(band) {
            deps.rig.tuneTo(hz)
        } else {
            deps.status.showVerbatim(MoveRequest.noFrequencyText(band: bandAdif, translate: deps.language.translator))
        }
    }
}
