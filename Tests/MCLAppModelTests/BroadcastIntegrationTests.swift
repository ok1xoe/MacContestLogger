import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The N1MM broadcast and BCLOG: every target is a loopback socket of the test with an
/// OS-assigned port; the UDP ports are `loopbackUdpPorts` (receivers bind `127.0.0.1:0`).
@MainActor @Suite struct BroadcastIntegrationTests {

    static func enable(_ config: inout AppConfig, contacts: UdpSink? = nil, radio: UdpSink? = nil,
                       score: UdpSink? = nil, appInfo: UdpSink? = nil) {
        func targets(_ sink: UdpSink?) -> String {
            sink.map { "127.0.0.1:\($0.port)" } ?? ""
        }
        config.broadcast.contactsEnabled = contacts != nil
        config.broadcast.contactsTargets = targets(contacts)
        config.broadcast.radioEnabled = radio != nil
        config.broadcast.radioTargets = targets(radio)
        config.broadcast.scoreEnabled = score != nil
        config.broadcast.scoreTargets = targets(score)
        config.broadcast.appInfoEnabled = appInfo != nil
        config.broadcast.appInfoTargets = targets(appInfo)
    }

    @Test func nothingStartsWithoutTargets() async throws {
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.broadcast.contactsEnabled = true
            config.broadcast.radioEnabled = true
            config.broadcast.scoreEnabled = true
            config.broadcast.appInfoEnabled = true
        })
        await app.integrations.settle()
        #expect(!app.integrations.broadcastActive)
        #expect(app.udpCounts.broadcasters == 0)
        app.integrations.restartBroadcast()
        await app.integrations.settle()
        #expect(!app.integrations.broadcastActive)
        #expect(app.udpCounts.broadcasters == 0)
    }

    @Test func aLiveQsoIsBroadcastAsContactInfo() async throws {
        let sink = UdpSink()
        defer { sink.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            Self.enable(&config, contacts: sink)
        })
        await eventually("broadcast started") { app.integrations.broadcastActive }
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await sink.waitFor("<contactinfo>")
        let text: String = try #require(sink.texts.first { $0.contains("<contactinfo>") })
        #expect(text.contains("<call>OK1ABC</call>"))
        #expect(text.contains("<mycall>OK1XOE</mycall>"))
        #expect(text.contains("<app>MacContestLogger</app>"))
        // Only the contact type has a target: nothing else was sent to it.
        #expect(!sink.texts.contains { $0.contains("<RadioInfo>") })
    }

    /// The replace carries the original call as `oldcall` (a Kotlin bug that is fixed here).
    @Test func anEditIsAReplaceAndADeleteIsReported() async throws {
        let sink = UdpSink()
        defer { sink.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            Self.enable(&config, contacts: sink)
        })
        await eventually("broadcast started") { app.integrations.broadcastActive }
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await sink.waitFor("<contactinfo>")
        let row: Qso = try #require(app.model.logbook.rows.first)
        var edited: Qso = row
        edited.call = "OK1ABD"
        await app.model.logbook.update(LogbookMutations.Edit(old: row, new: edited))
        await sink.waitFor("<contactreplace>")
        let replace: String = try #require(sink.texts.first { $0.contains("<contactreplace>") })
        #expect(replace.contains("<call>OK1ABD</call>"))
        #expect(replace.contains("<oldcall>OK1ABC</oldcall>"))

        let stored: Qso = try #require(app.model.logbook.rows.first)
        await app.model.logbook.delete([stored])
        await sink.waitFor("<contactdelete>")
        #expect(sink.texts.contains { $0.contains("<contactdelete>") && $0.contains("<call>OK1ABD</call>") })
    }

    @Test func appInfoAndScoreGoToTheirTargets() async throws {
        let appInfo = UdpSink()
        let score = UdpSink()
        defer {
            appInfo.close()
            score.close()
        }
        let app = try await IntegrationApp.make(configure: { config, _ in
            Self.enable(&config, score: score, appInfo: appInfo)
        })
        try await app.app.startCqWwCw()
        app.integrations.restartBroadcast()
        await appInfo.waitFor("<AppInfo>")
        #expect(appInfo.texts.contains { $0.contains("<dbname>logbook.sqlite</dbname>") })
        await score.waitFor("<dynamicresults>")
        #expect(score.texts.contains { $0.contains("<call>OK1XOE</call>") })
    }

    @Test func theRadioIsBroadcastWhileCatRuns() async throws {
        let radio = UdpSink()
        defer { radio.close() }
        let hardware = FakeHardware()
        let fake = try FakeRigctld(freqHz: 14_025_000, mode: "CW")
        let app = try await IntegrationApp.make(configure: { config, _ in
            Self.enable(&config, radio: radio)
            config.rig = fakeRigConfig(fake.port, label: "Fake 1")
        }, adjust: { environment in
            environment.hardware = hardware.ports
        })
        await eventually("broadcast started") { app.integrations.broadcastActive }
        app.model.rig.toggle(vfo: 0)
        await eventually("rig connected") { app.model.rig.snapshot(vfo: 0).state != nil }
        app.integrations.refreshBroadcastSnapshot()
        app.integrations.restartBroadcast()
        await radio.waitFor("<RadioInfo>")
        let text: String = try #require(radio.texts.first { $0.contains("<RadioInfo>") })
        #expect(text.contains("<StationName>OK1XOE</StationName>"))
        #expect(text.contains("<IsRunning>False</IsRunning>"))
        #expect(text.contains("<Mode>CW</Mode>"))
    }

    @Test func bclogSendsTheWholeLogAndCountsIt() async throws {
        let sink = UdpSink()
        defer { sink.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            Self.enable(&config, contacts: sink)
        })
        await eventually("broadcast started") { app.integrations.broadcastActive }
        try await app.app.startCqWwCw()
        for call in ["OK1AAA", "OK1BBB", "OK1CCC"] {
            await app.app.logContestQso(call: call, zone: "15")
        }
        await sink.waitFor("<contactinfo>", count: 3)
        let entry: EntryModel = app.model.entry
        entry.callChanged("BCLOG")
        entry.submit()
        await entry.settle()
        #expect(app.model.status.message == "BCLOG: odesláno 3 QSO")
        await sink.waitFor("<contactinfo>", count: 6)
        #expect(sink.count(containing: "<contactinfo>") == 6)
    }

    @Test func bclogWithoutBroadcastSaysSo() async throws {
        let app = try await IntegrationApp.make()
        app.integrations.broadcastWholeLog()
        #expect(app.model.status.message == "BCLOG: UDP broadcast je vypnutý (Nastavení → Broadcast Data)")
        #expect(app.udpCounts.broadcasters == 0)
    }

    /// The Settings port of a saved change restarts the broadcast with the new targets.
    @Test func aSavedChangeRestartsTheBroadcast() async throws {
        let first = UdpSink()
        let second = UdpSink()
        defer {
            first.close()
            second.close()
        }
        let app = try await IntegrationApp.make(configure: { config, _ in
            Self.enable(&config, contacts: first)
        })
        await eventually("broadcast started") { app.integrations.broadcastActive }
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1AAA", zone: "15")
        await first.waitFor("<contactinfo>")

        app.model.config.config.broadcast.contactsTargets = "127.0.0.1:\(second.port)"
        app.model.settings.services.restartBroadcast()
        await app.integrations.settle()
        await app.app.logContestQso(call: "OK1BBB", zone: "15")
        await second.waitFor("<call>OK1BBB</call>")
        await app.integrations.settle()
        #expect(first.count(containing: "<call>OK1BBB</call>") == 0)
        #expect(app.udpCounts.broadcasters == 2)
    }
}
