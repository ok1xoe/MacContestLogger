import Foundation
import MCLCore

/// Builds the `SpotFilterContext` the spot filter's call history, worked and busted-spot options ask: the call
/// history lookup, the calls of the log (cached per log revision) and the busted calls of the buffer (cached per spot
/// feed revision and filter). Nothing is computed for an option that is off.
@MainActor
final class SpotFilterContextSource {

    private let buffer: SpotBuffer
    private let config: ConfigModel
    private let analysis: SpotAnalysisModel
    private let logbook: LogbookModel
    private let callData: CallDataModel
    private let revision: @MainActor () -> Int
    private var worked: (revision: Int64, calls: Set<String>)?
    private var busted: (revision: Int, twoChars: Bool, calls: Set<String>)?

    init(buffer: SpotBuffer, config: ConfigModel, analysis: SpotAnalysisModel, logbook: LogbookModel,
         callData: CallDataModel, revision: @escaping @MainActor () -> Int) {
        self.buffer = buffer
        self.config = config
        self.analysis = analysis
        self.logbook = logbook
        self.callData = callData
        self.revision = revision
    }

    func context(_ filter: SpotFilter) -> SpotFilterContext {
        var context = SpotFilterContext()
        if filter.onlyCallHistory {
            let history: CallHistory = callData.callHistory
            context.inCallHistory = { history.lookup($0) != nil }
        }
        if filter.onlyWorked {
            let calls: Set<String> = workedCalls()
            context.worked = { calls.contains(KotlinStrings.trim($0).uppercased()) }
        }
        if filter.removeBusted {
            context.busted = bustedCalls(twoChars: filter.bustedTwoChars)
        }
        return context
    }

    private func workedCalls() -> Set<String> {
        if let worked, worked.revision == logbook.revision {
            return worked.calls
        }
        let calls = Set(logbook.rows.map { KotlinStrings.trim($0.call).uppercased() })
        worked = (logbook.revision, calls)
        return calls
    }

    private func bustedCalls(twoChars: Bool) -> Set<String> {
        let now: Int = revision()
        if let busted, busted.revision == now, busted.twoChars == twoChars {
            return busted.calls
        }
        let spots: [DxSpot] = buffer.snapshot()
        let counts: [String: Int] = buffer.spotCounts()
        let buffer: SpotBuffer = self.buffer
        let analyzer: SpotAnalyzer = analysis.current()
        let dx: DxClusterConfig = config.config.dxCluster
        let calls: Set<String> = BustedSpots.busted(
            spots, reports: { call in Swift.max(counts[call] ?? 1, buffer.skimmerCount(call)) },
            toleranceHz: { spot in dx.tuningToleranceHz(Self.mode(analyzer.spotModeCategory(spot))) },
            twoCharacters: twoChars)
        busted = (now, twoChars, calls)
        return calls
    }

    /// The tuning tolerance's mode of a spot's category (an unknown one uses CW's).
    static func mode(_ category: String?) -> Mode {
        switch category {
        case SpotModeCategory.phone: .ssb
        case SpotModeCategory.digi: .rtty
        default: .cw
        }
    }
}
