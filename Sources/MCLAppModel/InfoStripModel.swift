import Foundation
import MCLCore
import Observation

/// The info strip next to Run/S&P (`EP:1271-1307`): TOUR (the contest's session, Kotlin `contest.tour`), the county
/// line or the rover QTH, the bonus stations, RPT, the rig and keyer items (● REC, ANT, RIT, LADĚNÍ) and
/// post-contest entry, the band note (📝) and the next sked (SKED). The clock and network items (HODINY, SNS, ZÁSOBNÍK)
/// come from `sources` when wired.
///
/// The states owned by other models come through `sources` (wired by the app); reading them inside `text` keeps
/// SwiftUI observation working.
@Observable @MainActor
public final class InfoStripModel {

    /// The inputs the contest and config models do not hold.
    public struct Sources {
        /// Kotlin `state.countyLine`.
        public var countyLine: @MainActor () -> [String] = { [] }
        /// Kotlin `state.cqRepeat`.
        public var cqRepeat: @MainActor () -> Bool = { false }
        /// Kotlin `state.postContest`.
        public var postContest: @MainActor () -> Bool = { false }
        /// Kotlin `state.contestRecording` (● REC); `nil` = not wired.
        public var recording: @MainActor () -> Bool? = { nil }
        /// Kotlin `state.currentAntenna?.name` (ANT).
        public var antennaName: @MainActor () -> String? = { nil }
        /// Kotlin `state.ritHz` (RIT, shown when not 0); `nil` = not wired.
        public var ritHz: @MainActor () -> Int? = { nil }
        /// Kotlin `state.tuning` (LADĚNÍ); `nil` = not wired.
        public var tuning: @MainActor () -> Bool? = { nil }
        /// Kotlin `state.clockOffsetMs` (HODINY, shown beyond ±1 s); `nil` = not measured.
        public var clockOffsetMs: @MainActor () -> Int64? = { nil }
        /// Kotlin `isSerialServer && stationNet != null && reservedSerial == null` (SNS); `nil` = not wired.
        public var snsWaiting: @MainActor () -> Bool? = { nil }
        /// Kotlin `state.stackedCalls` (ZÁSOBNÍK).
        public var stackedCalls: @MainActor () -> [String] = { [] }
        /// The band note nearest to the tuned frequency (📝); `nil` = none.
        public var bandNote: @MainActor () -> String? = { nil }
        /// The next sked within 10 minutes (SKED); `nil` = none.
        public var sked: @MainActor () -> InfoStripSked? = { nil }

        public init() {}
    }

    @ObservationIgnored public var sources = Sources()

    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(contest: ContestModel, config: ConfigModel, language: LanguageModel,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.contest = contest
        self.config = config
        self.language = language
        self.now = now
    }

    /// The core input: TOUR and bonus stations from the contest runtime (Kotlin keeps them after a deactivation too),
    /// the rover QTH and RPT seconds from the config, the rest from `sources`.
    public var input: InfoStripInput {
        // The runtime is not observable: the setup and the active contest change whenever its extras do.
        _ = contest.activeSetup
        _ = contest.activeId
        let station: StationConfig = config.config.station
        return InfoStripInput(
            tour: contest.runtime.tour, now: now(), countyLine: sources.countyLine(), roverQth: station.roverQth,
            usesRoverQth: contest.usesRoverQth, bonusStationCount: contest.runtime.bonusStations.count,
            cqRepeat: sources.cqRepeat(), repeatSeconds: config.config.runMode.repeatSeconds,
            recording: sources.recording(), antennaName: sources.antennaName(),
            clockOffsetMs: sources.clockOffsetMs(), bandNote: sources.bandNote(), ritHz: sources.ritHz(),
            tuning: sources.tuning(), postContest: sources.postContest(), snsWaiting: sources.snsWaiting(),
            stackedCalls: sources.stackedCalls(), sked: sources.sked())
    }

    /// The items in Kotlin order.
    public var items: [ContestMessage] {
        InfoStrip.extras(input)
    }

    /// `" " + extras.joinToString(" · ")` in the current language, `""` without items.
    public var text: String {
        InfoStrip.text(items, language.translator, decimalSeparator: language.decimalSeparator)
    }
}
