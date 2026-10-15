import Foundation
import MCLCore
import Observation

/// The state of N1MM's Network Status Messages / Actions tabs: the message trace, the other stations' setups and the
/// master's time. Kept by `NetworkModel`.
public struct NetworkToolsState: Sendable {
    /// Sent and received messages, oldest first (N1MM Messages tab).
    public var trace: [NetTraceLine] = []
    /// The setup each station announced (`HELLO`), by station id.
    public var profiles: [String: StationProfile] = [:]
    /// The setup this station announced last (`nil` = not yet in this session).
    var announced: StationProfile?
    /// The mismatch warnings already shown in the status line.
    var shownWarnings: [EntryStatus] = []
    /// The offset applied from the master station's clock (ms), `nil` = not synchronised.
    public var masterOffsetMs: Int64?
    /// The master station the offset came from.
    public var masterStation: String = ""
    /// A time request in flight: its id and this clock's send moment (ms).
    var pendingTime: (id: String, sentAtMs: Int64)?
    /// This clock's moment of the last answered request (ms).
    var lastTimeSyncMs: Int64?
}

extension NetworkModel {

    // MARK: - inputs

    private var nowMs: Int64 {
        Int64((now().timeIntervalSince1970 * 1000).rounded(.down))
    }

    private var stationId: String {
        config.config.cluster.stationId
    }

    // MARK: - receiving

    /// The messages of the network tools; `true` = handled (not a chat line).
    func receiveTool(_ message: NetMessageWire) -> Bool {
        let from: String = message.fromStation ?? ""
        switch message.type {
        case NetMessageWire.help:
            alert()
            show(.tr(NetworkTools.helpFromKey, .string(NetMessages.sender(message))))
            return true
        case NetMessageWire.hello:
            let (profile, request) = StationProfile.decode(message.text ?? "")
            tools.profiles[from] = profile
            if request {
                sendHello(to: from, request: false)
            }
            reportMismatches()
            return true
        case NetMessageWire.serialReset:
            let floor: Int = message.freqHz
            guard floor > 0 else { return true }
            logbook.raiseSerialFloor(floor)
            show(.tr(NetworkTools.serialResetFromKey, .string(from), .int(logbook.nextSerial)))
            return true
        case NetMessageWire.timeRequest:
            answerTime(to: from, requestId: message.text ?? "")
            return true
        case NetMessageWire.time:
            timeAnswered(message, from: from)
            return true
        default:
            return false
        }
    }

    func traceReceived(_ message: NetMessageWire) {
        trace(NetTraceLine(time: NetworkTools.traceTime(now()), outgoing: false, type: message.type ?? "",
                           peer: message.fromStation ?? "", text: NetworkTools.traceText(message)))
    }

    func traceSent(_ message: NetMessageWire) {
        trace(NetTraceLine(time: NetworkTools.traceTime(now()), outgoing: true, type: message.type ?? "",
                           peer: message.toStation ?? "", text: NetworkTools.traceText(message)))
    }

    private func trace(_ line: NetTraceLine) {
        tools.trace = NetworkTools.appending(tools.trace, line)
    }

    /// Clears the Messages tab.
    public func clearTrace() {
        tools.trace = []
    }

    // MARK: - the setup check (HELLO)

    /// The session connected: this station's setup to all, asking for theirs.
    func connected() {
        tools.profiles = [:]
        tools.shownWarnings = []
        tools.announced = nil
        sendHello(to: "", request: true)
    }

    /// Every second: a changed setup (another contest opened, the master switch) goes to all; the master's time is
    /// asked for when due.
    func tick() {
        let own: StationProfile = ownProfile()
        if let announced = tools.announced, announced != own {
            sendHello(to: "", request: false)
            reportMismatches()
        }
        requestMasterTimeIfDue()
    }

    private func sendHello(to: String, request: Bool) {
        let own: StationProfile = ownProfile()
        tools.announced = own
        cluster.send(type: NetMessageWire.hello, to: to, text: own.encoded(request: request), call: nil, freqHz: 0,
                     mode: nil) { _ in }
    }

    /// The differences between this station's setup and the online stations' (N1MM's red flag on the Messages tab).
    public var mismatchWarnings: [EntryStatus] {
        let own: StationProfile = ownProfile()
        let online: Set<String> = Set(cluster.peers.filter(\.online).compactMap { $0.status.stationId })
        var out: [EntryStatus] = []
        for station in tools.profiles.keys.sorted() where online.contains(station) {
            if let profile = tools.profiles[station] {
                out += own.mismatches(with: profile, station: station)
            }
        }
        return out
    }

    /// A new mismatch is shown in the status line once.
    private func reportMismatches() {
        let current: [EntryStatus] = mismatchWarnings
        if let fresh = current.first(where: { !tools.shownWarnings.contains($0) }) {
            show(EntryStatus.verbatim("⚠ ").appending(fresh))
        }
        tools.shownWarnings = current
    }

    // MARK: - actions

    /// N1MM Call for Help: an alert at `to` (`""` = every station).
    public func callForHelp(to: String) {
        guard cluster.isRunning else {
            show(.tr(NetworkTools.notConnectedKey))
            return
        }
        cluster.send(type: NetMessageWire.help, to: to, text: "", call: nil, freqHz: 0, mode: nil) {
            [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                let target: String = to.isEmpty ? self.language.tr(NetworkTools.everyoneKey) : to
                self.show(.tr(NetworkTools.helpSentKey, .string(target)))
            case .failure(let error):
                self.show(NetMessages.failure("Help", message: ErrorText.message(error)))
            }
        }
    }

    /// N1MM „reset serial numbers at all stations": every station (this one too) continues after the highest serial
    /// sent in the log.
    public func resetSerialsEverywhere() {
        guard cluster.isRunning else {
            show(.tr(NetworkTools.notConnectedKey))
            return
        }
        let highest: Int = NetworkTools.maxSentSerial(logbook.rows)
        logbook.raiseSerialFloor(highest)
        cluster.send(type: NetMessageWire.serialReset, to: "", text: "", call: nil, freqHz: highest, mode: nil) {
            [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.show(.tr(NetworkTools.serialResetSentKey, .int(self.logbook.nextSerial)))
            case .failure(let error):
                self.show(NetMessages.failure("Serial", message: ErrorText.message(error)))
            }
        }
    }

    // MARK: - the master's time

    /// The online master station (another one), `nil` = none.
    public var masterStation: String? {
        let online: Set<String> = Set(cluster.peers.filter(\.online).compactMap { $0.status.stationId })
        return tools.profiles.keys.sorted().first { online.contains($0) && tools.profiles[$0]?.master == true }
    }

    /// Asks the master for its time now (the Actions tab) — only with „time from the master" on.
    public func syncTimeFromMaster() {
        guard config.config.cluster.timeFromMaster, !config.config.cluster.master else { return }
        guard let master = masterStation else {
            show(.tr(NetworkTools.masterTimeNoMasterKey))
            return
        }
        requestTime(from: master)
    }

    private func requestMasterTimeIfDue() {
        guard config.config.cluster.timeFromMaster, !config.config.cluster.master,
              let master = masterStation else { return }
        let nowMs: Int64 = self.nowMs
        if let pending = tools.pendingTime, nowMs - pending.sentAtMs < NetworkTools.masterTimeTimeoutMs {
            return
        }
        if let last = tools.lastTimeSyncMs, nowMs - last < NetworkTools.masterTimeIntervalMs {
            return
        }
        requestTime(from: master)
    }

    private func requestTime(from master: String) {
        let id: String = UUID().uuidString.lowercased()
        tools.pendingTime = (id, nowMs)
        cluster.send(type: NetMessageWire.timeRequest, to: master, text: id, call: nil, freqHz: 0, mode: nil) { _ in }
    }

    /// The master answers with its clock (corrected by its own NTP check when that is on).
    private func answerTime(to requester: String, requestId: String) {
        guard config.config.cluster.master, !requester.isEmpty, !requestId.isEmpty else { return }
        let masterMs: Int64 = nowMs + ownClockOffsetMs()
        cluster.send(type: NetMessageWire.time, to: requester,
                     text: NetworkTools.timeAnswer(requestId: requestId, masterMs: masterMs), call: nil, freqHz: 0,
                     mode: nil) { _ in }
    }

    private func timeAnswered(_ message: NetMessageWire, from: String) {
        guard let (id, masterMs) = NetworkTools.parseTimeAnswer(message.text ?? ""),
              let pending = tools.pendingTime, pending.id == id else { return }
        tools.pendingTime = nil
        let receivedMs: Int64 = nowMs
        guard receivedMs - pending.sentAtMs <= NetworkTools.masterTimeTimeoutMs,
              config.config.cluster.timeFromMaster else { return }
        tools.lastTimeSyncMs = receivedMs
        let offset: Int64 = NetworkTools.masterOffsetMs(sentAtMs: pending.sentAtMs, masterMs: masterMs,
                                                        receivedAtMs: receivedMs)
        let previous: Int64? = tools.masterOffsetMs
        tools.masterOffsetMs = offset
        tools.masterStation = from
        let logbook: LogbookModel = self.logbook
        Task { @MainActor in
            await logbook.setClockOffset(milliseconds: offset)
        }
        if previous == nil || abs((previous ?? 0) - offset) > 1_000 {
            show(.tr(NetworkTools.masterTimeKey, .string(from), .string(NetworkTools.seconds(offset))))
        }
    }
}
