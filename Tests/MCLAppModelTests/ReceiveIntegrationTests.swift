import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// WSJT-X, N1MM `contactinfo` and bare ADIF receive. Datagrams come from loopback
/// sockets of the test; the receivers bind `127.0.0.1:0` (`loopbackUdpPorts`), never a well-known port.
@MainActor @Suite struct ReceiveIntegrationTests {

    static let ownAdif = "<call:6>OK1ZZZ <qso_date:8>20261003 <time_on:6>100000 <band:3>20m <mode:2>CW "
        + "<rst_sent:3>599 <rst_rcvd:3>599 <freq:8>14.02500 <eor>"

    static func n1mm(call: String, mode: String = "CW", station: String = "OK1ZZZ", app: String = "N1MM",
                     timestamp: String = "2026-10-03 10:00:00") -> String {
        "<contactinfo><app>\(app)</app><call>\(call)</call><mode>\(mode)</mode><txfreq>1402500</txfreq>"
            + "<timestamp>\(timestamp)</timestamp><StationName>\(station)</StationName></contactinfo>"
    }

    static func enableWsjtx(_ config: inout AppConfig) {
        config.wsjtx.receiveEnabled = true
        config.wsjtx.receiveBind = "127.0.0.1:45002"
    }

    /// Counts the ingests that ran (a dropped datagram leaves no other trace).
    static func countIngests(_ app: IntegrationApp) -> Counter {
        let counter = Counter()
        app.integrations.afterIngest = { counter.value += 1 }
        return counter
    }

    @MainActor final class Counter {
        var value = 0
    }

    // MARK: - WSJT-X

    @Test func decodesBecomeRowsAndTheStatusSuppliesTheFrequency() async throws {
        let sender = UdpSink()
        defer { sender.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in Self.enableWsjtx(&config) })
        try await app.app.startCqWwCw()
        await eventually("listening") { app.integrations.wsjtxPort != nil }
        let port: Int = try #require(app.integrations.wsjtxPort)

        sender.send(WsjtxPackets.status(dialHz: 14_074_000, mode: "FT8"), toPort: port)
        await eventually("status") { app.integrations.wsjtxStatus?.dialFrequencyHz == 14_074_000 }
        sender.send(WsjtxPackets.decode("CQ DX OK1ABC JO70"), toPort: port)
        await eventually("decode row") { app.integrations.wsjtxDecodes.rows.count == 1 }
        let row: WsjtxDecodes.Row = try #require(app.integrations.wsjtxDecodes.rows.first)
        #expect(row.freqHz == 14_075_000)
        #expect(row.parsed.caller == "OK1ABC")
        #expect(!row.dupe)
        let text: WsjtxDecodes.RowText = WsjtxDecodes.rowText(row)
        #expect(text.message == "CQ DX OK1ABC JO70")
        #expect(WsjtxDecodes.statusText(status: app.integrations.wsjtxStatus).czech == "FT8  14074.000 kHz")
    }

    /// The row's colour: a call already worked on the band is `dupe` (also outside the contest's own dupe rule).
    @Test func aWorkedCallIsMarkedDupe() async throws {
        let sender = UdpSink()
        defer { sender.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in Self.enableWsjtx(&config) })
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15", freqKHz: "14025")
        await eventually("listening") { app.integrations.wsjtxPort != nil }
        let port: Int = try #require(app.integrations.wsjtxPort)
        sender.send(WsjtxPackets.status(dialHz: 14_074_000, mode: "FT8"), toPort: port)
        await eventually("status") { app.integrations.wsjtxStatus != nil }
        sender.send(WsjtxPackets.decode("CQ OK1ABC JO70"), toPort: port)
        await eventually("decode row") { app.integrations.wsjtxDecodes.rows.count == 1 }
        let row: WsjtxDecodes.Row = try #require(app.integrations.wsjtxDecodes.rows.first)
        #expect(row.dupe)
        #expect(WsjtxDecodes.rowText(row).label == "dupe")
    }

    @Test func clearEmptiesTheList() async throws {
        let sender = UdpSink()
        defer { sender.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in Self.enableWsjtx(&config) })
        await eventually("listening") { app.integrations.wsjtxPort != nil }
        let port: Int = try #require(app.integrations.wsjtxPort)
        sender.send(WsjtxPackets.decode("CQ OK1ABC JO70"), toPort: port)
        await eventually("row") { app.integrations.wsjtxDecodes.rows.count == 1 }
        sender.send(WsjtxPackets.clear(), toPort: port)
        await eventually("cleared") { app.integrations.wsjtxDecodes.rows.isEmpty }
    }

    @Test func replyGoesToTheSenderOfTheDecodeOnly() async throws {
        let wsjtx = UdpSink()
        let bystander = UdpSink()
        defer {
            wsjtx.close()
            bystander.close()
        }
        let app = try await IntegrationApp.make(configure: { config, _ in Self.enableWsjtx(&config) })
        await eventually("listening") { app.integrations.wsjtxPort != nil }
        let port: Int = try #require(app.integrations.wsjtxPort)
        wsjtx.send(WsjtxPackets.decode("CQ OK1ABC JO70"), toPort: port)
        await eventually("row") { app.integrations.wsjtxDecodes.rows.count == 1 }
        let row: WsjtxDecodes.Row = try #require(app.integrations.wsjtxDecodes.rows.first)
        #expect(row.from.port == wsjtx.port)

        app.integrations.reply(to: row)
        #expect(app.model.status.message == "WSJT-X: volám OK1ABC")
        await eventually("reply arrived") { !wsjtx.bytes.isEmpty }
        let reply: [UInt8] = try #require(wsjtx.bytes.first)
        var input = WsjtxDataInput(reply)
        #expect(try input.readInt() == WsjtxProtocol.magic)
        _ = try input.readInt()
        #expect(try input.readInt() == WsjtxProtocol.reply)
        await app.integrations.settle()
        #expect(bystander.bytes.isEmpty)
    }

    @Test func replyWithoutReceiveSaysSo() async throws {
        let app = try await IntegrationApp.make()
        let row = WsjtxDecodes.Row(
            decode: WsjtxMessages.Decode(id: "WSJT-X", isNew: true, timeMs: 0, snr: 0, deltaTime: 0,
                                         deltaFrequency: 0, mode: "~", message: "CQ OK1ABC", lowConfidence: false,
                                         offAir: false),
            from: try UdpEndpoint.resolve(host: "127.0.0.1", port: 45003), parsed: Ft8Message.parse("CQ OK1ABC"),
            freqHz: 0, dupe: false, newMultCount: 0)
        app.integrations.reply(to: row)
        #expect(app.model.status.message == "WSJT-X: příjem není zapnutý (Nastavení → WSJT-X)")
    }

    @Test func aLoggedAdifBecomesAQsoWithoutAnyLiveEffect() async throws {
        let sender = UdpSink()
        let contacts = UdpSink()
        defer {
            sender.close()
            contacts.close()
        }
        let app = try await IntegrationApp.make(configure: { config, _ in
            Self.enableWsjtx(&config)
            BroadcastIntegrationTests.enable(&config, contacts: contacts)
            config.clubLog.enabled = true
            config.clubLog.email = "user@example.test"
            config.clubLog.appPassword = "secret"
            config.clubLog.callsign = "OK1XOE"
            config.clubLog.apiKey = "apikey"
        })
        try await app.app.startCqWwCw()
        await eventually("listening") { app.integrations.wsjtxPort != nil && app.integrations.broadcastActive }
        let port: Int = try #require(app.integrations.wsjtxPort)
        let ingests = Self.countIngests(app)
        sender.send(WsjtxPackets.loggedAdif(Self.ownAdif), toPort: port)
        await eventually("ingested") { ingests.value == 1 }
        #expect(app.model.logbook.rows.map(\.call) == ["OK1ZZZ"])
        #expect(app.model.logbook.rows.first?.imported == true)
        #expect(app.model.status.message == "WSJT-X: importováno QSO OK1ZZZ")
        await app.integrations.settle()
        await app.services.settle()
        // An import is not a live QSO: no contact info, no Club Log upload.
        #expect(contacts.count(containing: "<contactinfo>") == 0)
        #expect(app.online.uploads.isEmpty)
    }

    /// The same datagram twice in a row logs one QSO: the second is taken only after the first was logged, so the
    /// dedup (120 s) sees it.
    @Test func aRepeatedDatagramIsLoggedOnce() async throws {
        let sender = UdpSink()
        defer { sender.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in Self.enableWsjtx(&config) })
        try await app.app.startCqWwCw()
        await eventually("listening") { app.integrations.wsjtxPort != nil }
        let port: Int = try #require(app.integrations.wsjtxPort)
        let ingests = Self.countIngests(app)
        for _ in 0..<3 {
            sender.send(WsjtxPackets.loggedAdif(Self.ownAdif), toPort: port)
        }
        await eventually("all three taken") { ingests.value == 3 }
        #expect(app.model.logbook.rows.count == 1)
    }

    // MARK: - N1MM

    @Test func anN1mmContactIsImported() async throws {
        let sender = UdpSink()
        defer { sender.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.n1mmRecv.receiveEnabled = true
            config.n1mmRecv.receiveBind = "127.0.0.1:45004"
        })
        try await app.app.startCqWwCw()
        await eventually("listening") { app.integrations.n1mmPort != nil }
        let port: Int = try #require(app.integrations.n1mmPort)
        let ingests = Self.countIngests(app)
        sender.send(Self.n1mm(call: "DL1ABC"), toPort: port)
        await eventually("ingested") { ingests.value == 1 }
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(app.model.status.message == "N1MM: importováno QSO DL1ABC")

        // The own echo (our own broadcast looping back, or the own station name) is dropped without a trace.
        sender.send(Self.n1mm(call: "DL2XYZ", station: "OK1XOE"), toPort: port)
        sender.send(Self.n1mm(call: "DL3XYZ", app: "MacContestLogger"), toPort: port)
        await eventually("echoes taken") { ingests.value == 3 }
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
    }

    @Test func anN1mmContactWithoutAContestIsNotSaved() async throws {
        let sender = UdpSink()
        defer { sender.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.n1mmRecv.receiveEnabled = true
            config.n1mmRecv.receiveBind = "127.0.0.1:45004"
        })
        await eventually("listening") { app.integrations.n1mmPort != nil }
        let port: Int = try #require(app.integrations.n1mmPort)
        let ingests = Self.countIngests(app)
        sender.send(Self.n1mm(call: "DL1ABC"), toPort: port)
        await eventually("ingested") { ingests.value == 1 }
        #expect(app.model.status.message == "N1MM: přijato QSO DL1ABC, ale není aktivní závod — neuloženo")
        #expect(app.model.logbook.rows.isEmpty)
    }

    @Test func aModeTheContestDoesNotHaveIsStoredButNotScored() async throws {
        let sender = UdpSink()
        defer { sender.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.n1mmRecv.receiveEnabled = true
            config.n1mmRecv.receiveBind = "127.0.0.1:45004"
        })
        try await app.app.startCqWwCw()
        await eventually("listening") { app.integrations.n1mmPort != nil }
        let port: Int = try #require(app.integrations.n1mmPort)
        let ingests = Self.countIngests(app)
        sender.send(Self.n1mm(call: "DL1ABC", mode: "SSB"), toPort: port)
        await eventually("ingested") { ingests.value == 1 }
        #expect(app.model.status.message == "N1MM: QSO DL1ABC v módu SSB — závod ho nemá, do skóre se nepočítá")
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
    }

    // MARK: - ADIF over UDP

    @Test func anAdifRecordWithoutACallIsIgnored() async throws {
        let sender = UdpSink()
        defer { sender.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.adifUdp.receiveEnabled = true
            config.adifUdp.receiveBind = "127.0.0.1:45005"
        })
        try await app.app.startCqWwCw()
        await eventually("listening") { app.integrations.adifPort != nil }
        let port: Int = try #require(app.integrations.adifPort)
        let ingests = Self.countIngests(app)
        sender.send("<call:0> <band:3>20m <mode:2>CW <eor>", toPort: port)
        await eventually("ingested") { ingests.value == 1 }
        #expect(app.model.status.message == "ADIF: přijatý ADIF bez volačky, ignoruji")
        #expect(app.model.logbook.rows.isEmpty)
        sender.send(Self.ownAdif, toPort: port)
        await eventually("second ingested") { ingests.value == 2 }
        #expect(app.model.logbook.rows.map(\.call) == ["OK1ZZZ"])
        #expect(app.model.status.message == "ADIF: importováno QSO OK1ZZZ")
    }

    /// A logging that throws (the database is closed) is the status `"<source>: import selhal (…)"`, not a crash.
    @Test func aFailedLoggingShowsTheFailureStatus() async throws {
        let sender = UdpSink()
        defer { sender.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.adifUdp.receiveEnabled = true
            config.adifUdp.receiveBind = "127.0.0.1:45005"
        })
        try await app.app.startCqWwCw()
        await eventually("listening") { app.integrations.adifPort != nil }
        let port: Int = try #require(app.integrations.adifPort)
        await app.model.database.close(revision: app.model.logbook.revision)
        let ingests = Self.countIngests(app)
        sender.send(Self.ownAdif, toPort: port)
        await eventually("ingested") { ingests.value == 1 }
        #expect(app.model.status.message.hasPrefix("ADIF: import selhal ("))
    }

    // MARK: - lifecycle

    /// The start texts (before a contest's own status can overwrite them): the configured address, not the bound one.
    @Test func eachReceiverAnnouncesItsAddress() async throws {
        let wsjtx = try await IntegrationApp.make(configure: { config, _ in Self.enableWsjtx(&config) })
        await eventually("wsjtx text") { wsjtx.model.status.message == "WSJT-X: poslouchám na 127.0.0.1:45002" }
        let n1mm = try await IntegrationApp.make(configure: { config, _ in
            config.n1mmRecv.receiveEnabled = true
            config.n1mmRecv.receiveBind = "127.0.0.1:45004"
        })
        await eventually("n1mm text") { n1mm.model.status.message == "N1MM příjem: poslouchám na 127.0.0.1:45004" }
        let adif = try await IntegrationApp.make(configure: { config, _ in
            config.adifUdp.receiveEnabled = true
            config.adifUdp.receiveBind = "127.0.0.1:45005"
        })
        await eventually("adif text") { adif.model.status.message == "ADIF příjem: poslouchám na 127.0.0.1:45005" }
    }

    @Test func anInvalidBindIsReportedAndNothingIsBound() async throws {
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.n1mmRecv.receiveEnabled = true
            config.n1mmRecv.receiveBind = "nonsense"
        })
        await app.integrations.settle()
        #expect(app.model.status.message == "N1MM příjem se nespustil (neplatný bind: nonsense)")
        #expect(app.udpCounts.listeners == 0)
    }

    @Test func aRestartAfterTheSettingsRebindsOnlyThatService() async throws {
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.n1mmRecv.receiveEnabled = true
            config.n1mmRecv.receiveBind = "127.0.0.1:45004"
        })
        await eventually("listening") { app.integrations.n1mmPort != nil }
        let first: Int? = app.integrations.n1mmPort
        app.model.settings.services.restartN1mm()
        await eventually("rebound") { app.integrations.n1mmPort != nil && app.integrations.n1mmPort != first }
        #expect(app.udpCounts.listeners == 2)
        app.model.config.config.n1mmRecv.receiveEnabled = false
        app.model.settings.services.restartN1mm()
        await app.integrations.settle()
        #expect(app.integrations.n1mmPort == nil)
    }

    @Test func theQuitClosesTheReceiversAndTheBroadcast() async throws {
        let contacts = UdpSink()
        defer { contacts.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            Self.enableWsjtx(&config)
            config.n1mmRecv.receiveEnabled = true
            config.n1mmRecv.receiveBind = "127.0.0.1:45004"
            config.adifUdp.receiveEnabled = true
            config.adifUdp.receiveBind = "127.0.0.1:45005"
            BroadcastIntegrationTests.enable(&config, contacts: contacts)
        })
        await eventually("all running") {
            app.integrations.wsjtxPort != nil && app.integrations.n1mmPort != nil && app.integrations.adifPort != nil
                && app.integrations.broadcastActive
        }
        await app.model.shutdown()
        #expect(app.integrations.wsjtxPort == nil)
        #expect(app.integrations.n1mmPort == nil)
        #expect(app.integrations.adifPort == nil)
        #expect(!app.integrations.broadcastActive)
        // After the quit nothing starts again.
        app.integrations.startN1mmIfEnabled()
        app.integrations.startBroadcastIfEnabled()
        await app.integrations.settle()
        #expect(app.integrations.n1mmPort == nil)
        #expect(!app.integrations.broadcastActive)
    }

    /// The cluster, then the integrations, then the database.
    @Test func theIntegrationsCloseAfterTheClusterAndBeforeTheDatabase() async throws {
        let app = try await IntegrationApp.make()
        var order: [String] = []
        let cluster = app.model.shutdownServices.cluster
        app.model.shutdownServices.cluster = {
            order.append("cluster")
            await cluster()
        }
        let integrations = app.model.shutdownServices.integrations
        var databaseWasClosing = true
        app.model.shutdownServices.integrations = {
            order.append("integrations")
            databaseWasClosing = app.model.writingFinalBackup
            await integrations()
        }
        var milestones = 0
        app.model.onQuitMilestone = {
            milestones += 1
            if milestones == 2 {
                order.append("database closed")
            }
        }
        await app.model.shutdown()
        #expect(order == ["cluster", "integrations", "database closed"])
        #expect(!databaseWasClosing)
    }

    /// A job stuck on the lane (a bind or a send waiting in DNS) does not hold the quit: after the 3 s bound of the
    /// injected clock it goes on to the database.
    @Test func aStuckLaneDoesNotHoldTheQuit() async throws {
        let app = try await IntegrationApp.make()
        let release = DispatchSemaphore(value: 0)
        app.integrations.lane.submit {
            release.wait()
        }
        var finished = false
        let quit = Task { @MainActor in
            await app.model.shutdown()
            finished = true
        }
        // The quit waits for the lane until the injected clock passes the bound: moving it is the only way out.
        for _ in 0..<5_000 where !finished {
            app.integrationClock.advance(by: IntegrationsModel.closeBoundMs)
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(finished)
        release.signal()
        await quit.value
    }

    /// A broadcast or sender start that finishes after the quit closes itself: nothing keeps sending.
    @Test func aStartFinishingAfterTheQuitIsClosedAtOnce() async throws {
        let sink = UdpSink()
        defer { sink.close() }
        let app = try await IntegrationApp.make()
        BroadcastIntegrationTests.enable(&app.model.config.config, contacts: sink, appInfo: sink)
        app.model.config.config.wsjtx.sendEnabled = true
        app.model.config.config.wsjtx.sendTargets = "127.0.0.1:\(sink.port)"
        let release = DispatchSemaphore(value: 0)
        app.integrations.lane.submit { release.wait() }
        app.integrations.startBroadcastIfEnabled()
        app.integrations.startWsjtxIfEnabled()
        var finished = false
        let quit = Task { @MainActor in
            await app.model.shutdown()
            finished = true
        }
        for _ in 0..<5_000 where !finished {
            app.integrationClock.advance(by: IntegrationsModel.closeBoundMs)
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(finished)
        release.signal()
        await quit.value
        // The starts run now (the lane refuses jobs after the quit, so they do not): nothing is sent either way.
        await app.integrations.settle()
        #expect(!app.integrations.broadcastActive && !app.integrations.wsjtxSendActive)
        #expect(sink.texts.isEmpty)
    }
}
