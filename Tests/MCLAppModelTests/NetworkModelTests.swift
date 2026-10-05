import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Chat, PASS and the call stack between stations, NETON and NETOFF, the serial server's reservation, shared spots
/// and the Settings port. Stations talk over a shared in-memory hub; nothing reaches a socket.
@MainActor @Suite struct NetworkModelTests {

    /// Two stations on one hub, both active.
    private static func pair() async throws -> (a: NetStation, b: NetStation, now: TestNow) {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        try await a.activate()
        try await b.activate()
        await eventually("A sees B") { a.cluster.peers.first?.online == true }
        return (a, b, now)
    }

    // MARK: - chat

    @Test func chatReachesTheOtherStationAndOnlyItsAddressee() async throws {
        let (a, b, _) = try await Self.pair()
        a.network.sendChat(to: "", text: "  hello  ")
        await eventually("B got it") { b.network.chat.lines.last?.text == "hello" }
        #expect(b.network.chat.unread == 1)
        #expect(b.network.chat.lines.last?.own == false)
        #expect(b.network.chat.lines.last?.from.hasPrefix("OP1") == true)
        #expect(b.status == "Chat OP1: hello")
        await eventually("own line") { a.network.chat.lines.last?.own == true }
        #expect(a.network.chat.lines.last?.text == "hello")
        #expect(a.network.chat.unread == 0)

        // To a third station: not for B.
        a.network.sendChat(to: "OP3", text: "private")
        await eventually("own private line") { a.network.chat.lines.count == 2 }
        await a.settle()
        await b.settle()
        #expect(b.network.chat.lines.count == 1)

        b.network.markChatRead()
        #expect(b.network.chat.unread == 0)
        a.network.sendChat(to: "", text: "   ")
        await a.settle()
        #expect(a.network.chat.lines.count == 2)
    }

    @Test func withoutTheNetworkTheChatSaysSo() async throws {
        let hub = InMemorySyncTransport()
        let c = try await NetStation.make(id: "OP3", hub: hub, enabled: false)
        c.network.sendChat(to: "", text: "x")
        #expect(c.status == "Chat: síťový deník není připojený")
        c.model.entry.callChanged("DL1ABC")
        c.network.startPass()
        #expect(c.status == "Pass: síťový deník není připojený")
        c.network.stackCall(to: "OP1", call: "DL1ABC")
        #expect(c.status == "Partner: síťový deník není připojený")
        #expect(c.network.chat.lines.isEmpty)
    }

    // MARK: - PASS

    @Test func passGoesToTheOnlyOnlineStationWithItsFrequencyIntoTheBandMap() async throws {
        let (a, b, _) = try await Self.pair()
        b.model.rig.qsy(14_025_000)
        b.clusterClock.advance(by: 1_000)
        await eventually("A sees B's frequency") { a.cluster.peers.first?.status.freqHz == 14_025_000 }

        a.network.startPass()
        #expect(a.status == "Pass: napiš volačku, kterou chceš předat")
        a.model.entry.callChanged("dl1abc")
        a.network.startPass()
        await eventually("B has the spot") {
            b.model.dxCluster.spots.snapshot().contains { $0.spotter == "PASS-OP1" && $0.dxCall == "DL1ABC" }
        }
        let spot: DxSpot? = b.model.dxCluster.spots.snapshot().first { $0.dxCall == "DL1ABC" }
        #expect(spot?.freqHz == 14_025_000)
        #expect(spot?.comment == "pass")
        await eventually("A's status") { a.status == "Pass: DL1ABC předáno stanici OP2" }
        #expect(a.network.chat.lines.last?.text == "PASS DL1ABC")
        #expect(a.network.chat.lines.last?.own == true)
        await eventually("B's status") { b.status == "Pass od OP1: DL1ABC na 14025.0 kHz (v bandmapě)" }
        #expect(b.network.chat.unread == 1)
        #expect(b.network.chat.lines.last?.text == "PASS DL1ABC → 14025.0")
    }

    @Test func withTwoOnlineStationsPassWaitsForTheChoice() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        let c = try await NetStation.make(id: "OP3", hub: hub, now: now)
        for station in [a, b, c] {
            try await station.activate()
        }
        await eventually("A sees both") { a.cluster.peers.filter(\.online).count == 2 }

        a.model.entry.callChanged("DL1ABC")
        a.network.startPass()
        #expect(a.network.passPending == "DL1ABC")
        #expect(a.status == "Pass DL1ABC: vyber stanici v okně Stav sítě")
        #expect(a.model.windows.isOpen("netstatus"))

        a.network.passCall(to: "OP3")
        await eventually("C has the line") { c.network.chat.lines.last?.text.hasPrefix("PASS DL1ABC") == true }
        await eventually("pending cleared") { a.network.passPending == "" }
        await b.settle()
        #expect(b.network.chat.lines.isEmpty)
    }

    // MARK: - the partner's stack

    @Test func theStackFillsOldestFirstIntoTheCallField() async throws {
        let (a, b, _) = try await Self.pair()
        a.network.stackCall(to: "OP2", call: " dl1abc ")
        await eventually("B stacked") { b.network.chat.stack == ["DL1ABC"] }
        #expect(b.status == "Zásobník od OP1: DL1ABC (Ctrl+Alt+K vloží)")
        await eventually("A's status") { a.status == "Partner: DL1ABC → zásobník OP2" }
        a.network.stackCall(to: "OP2", call: "dl1abc")
        a.network.stackCall(to: "OP2", call: "ok2xyz")
        await eventually("B has two") { b.network.chat.stack == ["DL1ABC", "OK2XYZ"] }
        #expect(b.model.infoStrip.text.contains("ZÁSOBNÍK DL1ABC OK2XYZ (Ctrl+Alt+K)"))

        b.model.entry.runShortcut(.popStack)
        #expect(b.model.entry.form.call == "DL1ABC")
        #expect(b.network.chat.stack == ["OK2XYZ"])
        b.model.entry.runShortcut(.popStack)
        b.model.entry.runShortcut(.popStack)
        #expect(b.status == "Zásobník volaček je prázdný")
    }

    // MARK: - NETON and NETOFF

    @Test func netOnAndNetOffStartAndStopTheSession() async throws {
        let hub = InMemorySyncTransport()
        let unconfigured = try await NetStation.make(id: "OP1", hub: hub, enabled: false,
                                                     configure: { $0.cluster.brokerHost = "" })
        unconfigured.model.entry.runCommand(.networkOn)
        #expect(unconfigured.status == "Síť není nastavená — vyplň Nastavení → Cluster")
        #expect(!unconfigured.model.config.config.cluster.enabled)

        let a = try await NetStation.make(id: "OP2", hub: hub, enabled: false)
        try await a.app.startCqWwCw()
        await a.settle()
        #expect(a.made.count == 0)
        a.model.entry.runCommand(.networkOn)
        #expect(a.model.config.config.cluster.enabled)
        await eventually("started") { a.cluster.isRunning && a.cluster.connected }
        #expect(await a.app.savedConfigFlushed().cluster.enabled)
        a.model.entry.runCommand(.networkOn)
        #expect(a.status == "Síťová synchronizace už běží")

        a.model.entry.runCommand(.networkOff)
        #expect(!a.cluster.isRunning)
        #expect(!a.model.config.config.cluster.enabled)
        #expect(a.status == "Síťová synchronizace vypnuta — loguji lokálně")
        #expect(!(await a.app.savedConfigFlushed().cluster.enabled))
        await a.settle()
        #expect(a.transport.isClosed)
        a.model.entry.runCommand(.networkOff)
        #expect(a.status == "Síťová synchronizace vypnuta — loguji lokálně")
    }

    // MARK: - the serial server

    @Test func theServerNumberIsUsedConsumedAndRequestedAgain() async throws {
        let hub = InMemorySyncTransport()
        let link = LinkedTransport(hub: hub)
        link.dropSerialRequests = true
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now, link: link,
                                          configure: { $0.cluster.serialServer = true })
        try await a.activate()
        await a.settle()
        #expect(link.serialRequests.count == 1)
        #expect(a.cluster.reservedSerial == nil)
        #expect(a.model.infoStrip.text.contains("SNS: čekám na číslo"))
        let first: String? = link.serialRequests.first?.requestId
        #expect(first != nil)

        // No reply: the request is repeated after 3 s, not before.
        now.advance(seconds: 2)
        a.clusterClock.advance(by: 1_000)
        await a.settle()
        #expect(link.serialRequests.count == 1)
        now.advance(seconds: 1.5)
        a.clusterClock.advance(by: 1_000)
        await a.settle()
        #expect(link.serialRequests.count == 2)
        let second: String = try #require(link.serialRequests.last?.requestId)
        #expect(second != first)

        // A reply to another request is not ours, the right one is.
        try link.deliver(SerialReply(stationId: "OP1", requestId: first, serial: 99))
        await runMainQueue()
        #expect(a.cluster.reservedSerial == nil)
        try link.deliver(SerialReply(stationId: "OP1", requestId: second, serial: 7))
        await eventually("reserved") { a.cluster.reservedSerial == 7 }
        #expect(a.model.logbook.nextSerial == 7)
        #expect(a.cluster.nextSerial() == 7)
        #expect(!a.model.infoStrip.text.contains("SNS"))

        // The QSO carries it; it is used up and the next one is asked for at once.
        await a.log("DL1ABC")
        let row: Qso = try #require(a.model.logbook.rows.first)
        #expect(row.serialSent == 7)
        #expect(row.stationId == "OP1")
        #expect(a.cluster.reservedSerial == nil)
        #expect(link.serialRequests.count == 3)
        #expect(a.model.logbook.nextSerial == 2)
    }

    /// A QSO the outward gate refuses (a simulated one) does not use up the server's number.
    @Test func aGatedQsoKeepsTheReservedServerNumber() async throws {
        let hub = InMemorySyncTransport()
        let link = LinkedTransport(hub: hub)
        link.dropSerialRequests = true
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now, link: link,
                                          configure: { $0.cluster.serialServer = true })
        try await a.activate()
        await a.settle()
        let request: String = try #require(link.serialRequests.last?.requestId)
        try link.deliver(SerialReply(stationId: "OP1", requestId: request, serial: 7))
        await eventually("reserved") { a.cluster.reservedSerial == 7 }
        a.model.logbook.outwardGate = { _ in false }
        await a.log("DL1ABC")
        #expect(a.model.logbook.rows.count == 1)
        #expect(a.cluster.reservedSerial == 7)
    }

    /// The hub answers like the authority: `1 + max(serials in the log, last issued)`.
    @Test func theAuthorityNumbersFollowTheNetworkLog() async throws {
        let (a, b, _) = try await Self.pair()
        a.model.config.config.cluster.serialServer = true
        b.model.config.config.cluster.serialServer = true
        a.clusterClock.advance(by: 1_000)
        await eventually("A reserved") { a.cluster.reservedSerial == 1 }
        b.clusterClock.advance(by: 1_000)
        await eventually("B reserved") { b.cluster.reservedSerial == 2 }
        await a.log("DL1ABC")
        #expect(a.model.logbook.rows.first?.serialSent == 1)
        await eventually("A asks again") { a.cluster.reservedSerial == 3 }
    }

    // MARK: - shared spots

    @Test func spotsAreSharedBothWaysAndNeverSharedAgain() async throws {
        let (a, b, _) = try await Self.pair()
        a.model.dxCluster.spotShare(DxSpot(spotter: "OK1ABC", freqHz: 14_030_000, dxCall: "OH2AS", comment: "CQ"))
        await eventually("B has it") { b.model.dxCluster.spots.snapshot().map(\.dxCall) == ["OH2AS"] }
        #expect(b.model.dxCluster.spots.snapshot().first?.spotter == "OK1ABC")
        #expect(a.model.dxCluster.spots.snapshot().isEmpty)
        #expect(b.transport.spotPublishes.isEmpty)

        b.model.dxCluster.spotShare(DxSpot(spotter: "DL1XX", freqHz: 7_010_000, dxCall: "DL5ZZ", comment: ""))
        await eventually("A has it") { a.model.dxCluster.spots.snapshot().map(\.dxCall) == ["DL5ZZ"] }
        #expect(a.transport.spotPublishes.count == 1)
        #expect(b.transport.spotPublishes.count == 1)
    }

    @Test func sharingFollowsTheSettingOnBothSides() async throws {
        let (a, b, _) = try await Self.pair()
        a.model.config.config.cluster.shareSpots = false
        a.model.dxCluster.spotShare(DxSpot(spotter: "OK1ABC", freqHz: 14_030_000, dxCall: "OH2AS", comment: ""))
        await a.settle()
        await b.settle()
        #expect(a.transport.spotPublishes.isEmpty)
        #expect(b.model.dxCluster.spots.snapshot().isEmpty)

        a.model.config.config.cluster.shareSpots = true
        b.model.config.config.cluster.shareSpots = false
        a.model.dxCluster.spotShare(DxSpot(spotter: "OK1ABC", freqHz: 14_030_000, dxCall: "OH2AS", comment: ""))
        await eventually("sent") { a.transport.spotPublishes.count == 1 }
        await b.settle()
        #expect(b.model.dxCluster.spots.snapshot().isEmpty)
    }

    /// A broker that does not answer cannot grow the queue: the newest shared spots are dropped at the cap.
    @Test func theSpotQueueIsCapped() async throws {
        let hub = InMemorySyncTransport()
        let link = LinkedTransport(hub: hub)
        let a = try await NetStation.make(id: "OP1", hub: hub, link: link)
        try await a.activate()
        await a.settle()
        let gate = DispatchSemaphore(value: 0)
        defer { for _ in 0..<400 { gate.signal() } }
        link.spotGate = gate
        for index in 0..<300 {
            a.cluster.shareSpot(DxSpot(spotter: "OK1ABC", freqHz: 14_000_000 + index, dxCall: "DX\(index)", comment: ""))
        }
        #expect(a.cluster.lane.spotsWaiting <= SyncLane.spotCap)
        for _ in 0..<400 { gate.signal() }
        await a.settle()
        // The capacity plus the one the lane had already taken.
        #expect((SyncLane.spotCap...(SyncLane.spotCap + 1)).contains(link.spotPublishes.count))
        #expect(link.spotPublishes.first?.dxCall == "DX0")
    }

    // MARK: - the Settings port

    @Test func aSavedClusterChangeRestartsTheSession() async throws {
        let recorder = EffectRecorder()
        let hub = InMemorySyncTransport()
        var holder: AppModel?
        let a = try await NetStation.make(id: "OP1", hub: hub, adjust: { environment in
            environment.settingsServices = recorder.services { holder }
        })
        holder = a.model
        try await a.activate()
        #expect(a.made.count == 1)

        let settings: SettingsModel = a.model.settings
        settings.open()
        await settings.settle()
        var draft: ConfigurerDraft = try #require(settings.draft)
        draft.stationId = "OP9"
        settings.draft = draft
        #expect(await settings.confirm())
        #expect(recorder.effects.contains(.restartCluster))
        #expect(recorder.calls.contains("restartCluster"))
        await eventually("restarted") { a.made.count == 2 && a.cluster.isRunning && a.cluster.connected }
        #expect(a.made.all.last?.stationId == "OP9")
        #expect(a.cluster.stationId == "OP9")
        #expect(a.made.made.first?.closings == 1)
    }
}
