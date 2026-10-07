import Foundation
import MCLCore
import Observation

/// The spot actions of the entry windows and the call-field commands (Kotlin `AppState`: `jumpToNextSpot`,
/// `removeSpotOf`, `markFrequency`, `promptSpotWithComment` `AS:840-905`, `selfSpot` `AS:1015-1027`, `loadBeacons`
/// `AS:2117-2128`, `spotToCluster`/`spotMe` `AS:3944-3976`, `spotForCall` `AS:578-581`). The texts and the spots are
/// built by the core (`SpotActions`); this model applies them to the shared buffer, the main cluster connection and
/// the status line.
///
/// Safety: nothing here keys a transmitter. Tuning goes through `RigModel.tuneToSpot` (CAT frequency, mode and split
/// only); a spot reaches the cluster only from an explicit user action (Spot It, Ctrl+P, SPOTME) through
/// `DxClusterModel.send` — the model's own connection, inert without the network.
@MainActor
public final class SpotNavigation {

    private let dxCluster: DxClusterModel
    private let feed: SpotFeed
    private let analysis: SpotAnalysisModel
    private let blacklist: BlacklistModel
    private let rig: RigModel
    private let status: StatusModel
    private let config: ConfigModel
    private let language: LanguageModel
    private let dialogs: DialogsModel
    private let now: @Sendable () -> Date
    /// The beacon file loads in flight (tests wait for them).
    private var beaconTasks: [Int: Task<Void, Never>] = [:]
    private var nextBeaconTask = 0

    struct Dependencies {
        let dxCluster: DxClusterModel
        let feed: SpotFeed
        let analysis: SpotAnalysisModel
        let blacklist: BlacklistModel
        let rig: RigModel
        let status: StatusModel
        let config: ConfigModel
        let language: LanguageModel
        let dialogs: DialogsModel
        let now: @Sendable () -> Date
    }

    init(_ dependencies: Dependencies) {
        dxCluster = dependencies.dxCluster
        feed = dependencies.feed
        analysis = dependencies.analysis
        blacklist = dependencies.blacklist
        rig = dependencies.rig
        status = dependencies.status
        config = dependencies.config
        language = dependencies.language
        dialogs = dependencies.dialogs
        now = dependencies.now
    }

    /// The shared spot buffer.
    var buffer: SpotBuffer {
        dxCluster.spots
    }

    // MARK: - navigation

    /// Kotlin `jumpToNextSpot(direction, onlyMult, onlySelf)` (Ctrl/Alt+↑↓): the nearest spot on the band beyond the
    /// tuned frequency that is not a dupe (`onlyMult`: a new multiplier, `onlySelf`: an own spot, dupe or not) is
    /// tuned to; without one, one of six whole sentences.
    public func jump(direction: Int, onlyMult: Bool = false, onlySelf: Bool = false) {
        let analyzer: SpotAnalyzer = analysis.current()
        let tuned = Int(truncatingIfNeeded: rig.tuning.tunedFreqHz)
        let found: DxSpot? = SpotNavigator.next(feed.filteredSnapshot(), freqHz: tuned, direction: direction) { spot in
            let state: SpotStatus = analyzer.spotStatus(spot)
            return SpotActions.navigable(selfSpotted: spot.selfSpotted, dupe: state.dupe, newMult: state.newMult,
                                         onlyMult: onlyMult, onlySelf: onlySelf)
        }
        guard let found else {
            status.show(ContestMessage(SpotActions.noSpotText(direction: direction, onlyMult: onlyMult,
                                                              onlySelf: onlySelf)))
            return
        }
        rig.tuneToSpot(found)
    }

    /// Kotlin `spotForCall(call)`: the first spot of the call in the buffer (Kotlin `equals(call.trim(), ignoreCase)`).
    public func spotForCall(_ call: String) -> DxSpot? {
        rig.spotForCall(call)
    }

    // MARK: - remove, mark, store

    /// Kotlin `removeSpotOf(call, blacklist)` (Alt+D / Alt+Shift+D): the call of the field, or the nearest spot within
    /// 200 Hz of the tuned frequency; every spot of that call leaves the buffer, optionally onto the blacklist.
    public func removeSpotOf(call: String, blacklist toBlacklist: Bool) {
        let buffer: SpotBuffer = self.buffer
        guard let target = SpotActions.removeTarget(call: call, tunedFreqHz: rig.tuning.tunedFreqHz,
                                                    nearest: { buffer.nearestWithin($0, toleranceHz: $1) }) else {
            status.show(ContestMessage(SpotActions.removeNoSpot))
            return
        }
        buffer.remove(target)
        if toBlacklist {
            blacklist.blacklistCall(target)
        }
        show(SpotActions.removed(target, blacklist: toBlacklist))
    }

    /// Kotlin `markFrequency(freqHz)` (Alt+M, the Mark button): a `MARK` spot on the frequency; ≤ 0 adds nothing and
    /// the status says that a frequency is missing (Kotlin stayed silent).
    public func mark(freqHz: Int64) {
        guard let spot = SpotActions.markSpot(freqHz: freqHz) else {
            show(.tr(SpotActions.noFrequency))
            return
        }
        buffer.add(spot)
        show(SpotActions.markStatus(freqHz: freqHz, translator: language.translator))
    }

    /// Kotlin `selfSpot(call, freqHz)`: the call into the band map as an own spot of my station (Store, the
    /// self-spot after tuning away); a blank call does nothing.
    public func store(call: String, freqHz: Int64) {
        guard let spot = SpotActions.storeSpot(myCall: config.config.station.call, call: call, freqHz: freqHz) else {
            return
        }
        buffer.add(spot)
    }

    // MARK: - spots to the cluster

    /// Kotlin `spotToCluster(dxCall, freqHz, comment)`: `DX <kHz> <CALL> <comment>` over the **main** connection
    /// (parallel connections do not count). `false` = not sent (the status says why).
    @discardableResult
    public func spotToCluster(call: String, freqHz: Int64, comment: String) -> Bool {
        switch SpotActions.clusterCommand(call: call, freqHz: freqHz, comment: comment,
                                          connected: dxCluster.connected) {
        case .rejected(let message):
            show(message)
            return false
        case .accepted(let command):
            dxCluster.send(command)
            show(SpotActions.sent(command))
            return true
        }
    }

    /// Kotlin `spotMe(freqHz, comment)` (SPOTME): my own call, the comment `CQ` when blank, and the reminder that
    /// self-spots are often forbidden.
    public func spotMe(freqHz: Int64, comment: String) {
        switch SpotActions.clusterCommand(call: config.config.station.call, freqHz: freqHz,
                                          comment: SpotActions.spotMeComment(comment),
                                          connected: dxCluster.connected) {
        case .rejected(let message):
            show(message)
        case .accepted(let command):
            dxCluster.send(command)
            show(SpotActions.spotMeSent(command))
        }
    }

    /// Spot It (Alt+P, the button, `EP:806-812`): the call of the field at its frequency, otherwise the last logged
    /// QSO.
    public func spotIt(call: String, isCommand: Bool, fieldFreqHz: Int64, lastQso: Qso?) {
        let last: (call: String?, freqHz: Int64)? = lastQso.map { (call: $0.call, freqHz: Int64($0.freqHz)) }
        switch SpotActions.spotItTarget(call: call, isCommand: isCommand, fieldFreqHz: fieldFreqHz, lastQso: last) {
        case .rejected(let message):
            show(message)
        case .accepted(let target):
            spotToCluster(call: target.call, freqHz: target.freqHz, comment: "")
        }
    }

    /// Kotlin `promptSpotWithComment(call, freqHz)` (Ctrl+P): the prompt `"Spot <call>"` (not translated); OK sends.
    public func spotWithComment(call: String, freqHz: Int64) {
        guard let title = SpotActions.commentTitle(call: call) else {
            status.show(ContestMessage(SpotActions.commentNoCall))
            return
        }
        guard freqHz > 0 else {
            show(.tr(SpotActions.noFrequency))
            return
        }
        dialogs.prompt(title: .verbatim(title), hint: ContestMessage(SpotActions.commentHint), initial: "") {
            [weak self] comment in
            self?.spotToCluster(call: call, freqHz: freqHz, comment: comment)
        }
    }

    // MARK: - beacons

    /// Kotlin `loadBeacons(path)` (BEACONS, the file chosen in the open panel): the file is read off the main thread,
    /// the beacons stay in the band map for the hours of its header (from now), and the status counts them.
    public func loadBeacons(url: URL) {
        let id: Int = nextBeaconTask
        nextBeaconTask += 1
        beaconTasks[id] = Task { [weak self] in
            let content: String? = try? await BlockingQueue.run {
                try String(contentsOf: url, encoding: .utf8)
            }
            self?.beaconsRead(content, url: url)
            self?.beaconTasks[id] = nil
        }
    }

    private func beaconsRead(_ content: String?, url: URL) {
        guard let content else {
            show(SpotActions.beaconsUnreadable(fileName: url.lastPathComponent))
            return
        }
        let parsed: BeaconFile.Beacons = BeaconFile.parse(content)
        let until: Date = SpotActions.beaconsUntil(now: now(), hours: parsed.hours)
        for beacon in parsed.beacons {
            buffer.addUntil(beacon, until: until)
        }
        show(SpotActions.beaconsLoaded(parsed))
    }

    /// Waits for the beacon loads in flight (tests).
    func settle() async {
        while let task = beaconTasks.values.first {
            await task.value
        }
    }

    private func show(_ message: EntryStatus) {
        status.showJoined(message.parts, separator: "")
    }
}
