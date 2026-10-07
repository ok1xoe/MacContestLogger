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

    @ObservationIgnored private let logbook: LogbookModel

    init(logbook: LogbookModel, now: Date) {
        self.logbook = logbook
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
        range.map { $0.filter(logbook.rows).count } ?? 0
    }

    public var canExport: Bool {
        qsoCount > 0
    }

    /// The save panel's suggested name.
    public var suggestedName: String {
        range?.fileName() ?? ExportNames.adifDefaultName
    }
}
