import Foundation
import MCLCore
import os

/// What the broadcast providers read: a `Sendable` copy of the application state that the main actor refreshes
/// (`IntegrationsModel.refreshBroadcastSnapshot`) and the broadcast threads read under a lock. Kotlin's providers
/// read the live state from the broadcast threads (a data race); the Swift ones never touch a model.
struct BroadcastSnapshot: Sendable {
    var stationCall: String = ""
    var operatorCall: String = ""
    var runMode: RunMode = .searchAndPounce
    var catConnected: Bool = false
    var rig: RigState?
    var isContestActive: Bool = false
    var score: ScoreState?
    var activeName: String?
    var activeId: String?
    /// The stable session number of N1MM `contestnr`.
    var contestNr: Int32 = 0
}

/// The lock around the snapshot.
final class BroadcastSnapshotBox: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: BroadcastSnapshot())

    var value: BroadcastSnapshot {
        state.withLock { $0 }
    }

    func store(_ snapshot: BroadcastSnapshot) {
        state.withLock { $0 = snapshot }
    }

    /// `AppState.radioData()` over the snapshot.
    func radioData() -> BroadcastXml.RadioData? {
        let s: BroadcastSnapshot = value
        return BroadcastMapping.radioData(stationCall: s.stationCall, catConnected: s.catConnected, rig: s.rig,
                                          operatorCall: s.operatorCall, runMode: s.runMode)
    }

    /// `AppState.scoreData()` over the snapshot.
    func scoreData(now: Date) -> BroadcastXml.ScoreData? {
        let s: BroadcastSnapshot = value
        return BroadcastMapping.scoreData(isContestActive: s.isContestActive, score: s.score, activeName: s.activeName,
                                          activeId: s.activeId, stationCall: s.stationCall,
                                          operatorCall: s.operatorCall, now: now)
    }

    /// `AppState.appInfoData()` over the snapshot.
    func appInfoData() -> BroadcastXml.AppInfoData {
        let s: BroadcastSnapshot = value
        return BroadcastMapping.appInfoData(contestNr: s.contestNr, contestName: s.activeName, stationCall: s.stationCall)
    }
}
