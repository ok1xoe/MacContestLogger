import Foundation
import MCLCore
import Observation

/// The „Export ADIF podle data" window: the UTC days to export, with a preview of how many QSOs of the active
/// contest (or of free logging) fall into them.
@Observable @MainActor
public final class AdifRangeModel {

    /// First and last day (any instant of the day; only the UTC day counts).
    public var first: Date
    public var last: Date
    /// N1MM „ADIF by date from ALL contests": every contest of the database (and free logging), not just the open one.
    public var allContests: Bool = false {
        didSet {
            if allContests && allRows == nil {
                loadAllRows()
            }
        }
    }
    /// N1MM „Export ADIF by multi-user station name": only the QSOs logged by this station of the network log
    /// (`Qso.stationId`); `""` = every station.
    public var station: String = ""
    /// The database's QSOs of every contest (read when `allContests` is first switched on; `nil` until then).
    public private(set) var allRows: [Qso]?

    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let loadAll: @MainActor () async -> [Qso]
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?

    init(logbook: LogbookModel, now: Date, loadAll: @escaping @MainActor () async -> [Qso] = { [] }) {
        self.logbook = logbook
        self.loadAll = loadAll
        let times: [Date] = logbook.rows.compactMap(\.timestampUtc)
        first = times.min() ?? now
        last = times.max() ?? now
    }

    /// The chosen period; `nil` when the last day is before the first.
    public var range: AdifDateRange? {
        AdifDateRange(firstDay: first, lastDay: last)
    }

    /// QSOs of the open log in the period (the preview).
    public var qsoCount: Int {
        range.map { Self.byStation($0.filter(rows), station).count } ?? 0
    }

    /// The station ids of the network log found in the QSOs (sorted), for the station picker.
    public var stations: [String] {
        Set(rows.map(\.stationId).filter { !$0.isEmpty }).sorted()
    }

    /// The QSOs of one station (`""` = all).
    public nonisolated static func byStation(_ qsos: [Qso], _ station: String) -> [Qso] {
        station.isEmpty ? qsos : qsos.filter { $0.stationId == station }
    }

    /// The QSOs the window counts: the open log, or every contest's once read.
    private var rows: [Qso] {
        allContests ? (allRows ?? []) : logbook.rows
    }

    private func loadAllRows() {
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let all: [Qso] = await self.loadAll()
            self.allRows = all
            self.loadTask = nil
        }
    }

    /// Waits for the read of every contest's QSOs (tests).
    func settle() async {
        await loadTask?.value
    }

    public var canExport: Bool {
        qsoCount > 0
    }

    /// The save panel's suggested name.
    public var suggestedName: String {
        let base: String = (allContests ? "maccontestlogger-all" : "maccontestlogger")
            + (station.isEmpty ? "" : "-" + station.filter { $0.isLetter || $0.isNumber })
        return range?.fileName(base: base) ?? ExportNames.adifDefaultName
    }
}
