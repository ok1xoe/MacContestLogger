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
    /// N1MM `{AUXANTSEL}`: the antenna the macro selected.
    var auxAntenna: AntennaEntry?
    /// The full N1MM `RadioInfo`: the second rig (SO2R), focus, stereo, transmitting, the antenna and rig names.
    var rig2Connected: Bool = false
    var rig2: RigState?
    var so2r: Bool = false
    var activeRadioNr: Int = 1
    var stereo: Bool = false
    var transmitting: Bool = false
    var antennaCode: Int?
    var radioNames: [String] = ["", ""]
    /// The full N1MM score packet's class, club, QTH and breakdown (`nil` = not computed yet).
    var scoreExtras: BroadcastXml.ScoreExtras?
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
    /// The full N1MM packet of radio 1 (in SO2R the first rig, otherwise the active one).
    func radioData() -> BroadcastXml.RadioData? {
        let s: BroadcastSnapshot = value
        return Self.radio(s, nr: 1)
    }

    /// The second rig's packet, only in SO2R.
    func radio2Data() -> BroadcastXml.RadioData? {
        let s: BroadcastSnapshot = value
        guard s.so2r else { return nil }
        return Self.radio(s, nr: 2)
    }

    private static func radio(_ s: BroadcastSnapshot, nr: Int) -> BroadcastXml.RadioData? {
        let connected: Bool = nr == 2 ? s.rig2Connected : s.catConnected
        let rig: RigState? = nr == 2 ? s.rig2 : s.rig
        let isActive: Bool = nr == s.activeRadioNr
        guard var data = BroadcastMapping.radioData(
            stationCall: s.stationCall, catConnected: connected, rig: rig, operatorCall: s.operatorCall,
            runMode: s.runMode, auxAntenna: isActive ? s.auxAntenna : nil), let rig else { return nil }
        data.extras = BroadcastMapping.radioExtras(
            radioNr: nr, rig: rig, stationCall: s.stationCall, antenna: isActive ? s.antennaCode : nil,
            focusRadioNr: s.activeRadioNr, activeRadioNr: s.activeRadioNr, isStereo: s.stereo,
            isTransmitting: isActive && s.transmitting, radioName: s.radioNames[nr == 2 ? 1 : 0])
        return data
    }

    /// `AppState.scoreData()` over the snapshot.
    func scoreData(now: Date) -> BroadcastXml.ScoreData? {
        let s: BroadcastSnapshot = value
        var data: BroadcastXml.ScoreData? = BroadcastMapping.scoreData(
            isContestActive: s.isContestActive, score: s.score, activeName: s.activeName, activeId: s.activeId,
            stationCall: s.stationCall, operatorCall: s.operatorCall, now: now)
        data?.extras = s.scoreExtras
        return data
    }

    /// `AppState.appInfoData()` over the snapshot.
    func appInfoData() -> BroadcastXml.AppInfoData {
        let s: BroadcastSnapshot = value
        return BroadcastMapping.appInfoData(contestNr: s.contestNr, contestName: s.activeName, stationCall: s.stationCall)
    }
}
