import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM „Spots", „Lookup" and „All QSOs" over loopback sinks with OS-assigned ports.
@MainActor @Suite struct BroadcastSpotLookupIntegrationTests {

    @Test func aSpotIsSentAsAddThenDelete() async throws {
        let sink = UdpSink()
        defer { sink.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.broadcast.spotsEnabled = true
            config.broadcast.spotsTargets = "127.0.0.1:\(sink.port)"
        })
        await eventually("broadcast started") { app.integrations.broadcastActive }
        let spot = DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "W1AW", comment: "CQ")
        app.model.spotFeed.buffer.add(spot)
        await sink.waitFor("<action>add</action>")
        let add: String = try #require(sink.texts.first { $0.contains("<spot>") })
        #expect(add.contains("<dxcall>W1AW</dxcall>"))
        #expect(add.contains("<frequency>14025.0</frequency>"))
        #expect(add.contains("<spottercall>OK1ABC</spottercall>"))
        app.integrations.spotsChanged([])
        await sink.waitFor("<action>delete</action>")
    }

    @Test func spaceInTheCallFieldSendsALookup() async throws {
        let sink = UdpSink()
        defer { sink.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.broadcast.lookupEnabled = true
            config.broadcast.lookupTargets = "127.0.0.1:\(sink.port)"
        })
        await eventually("broadcast started") { app.integrations.broadcastActive }
        try await app.app.startCqWwCw()
        let entry: EntryModel = app.model.entry
        entry.setFrequency("14025")
        entry.callChanged("DL1ABC")
        entry.jumpToExchange()
        await sink.waitFor("<lookupinfo>")
        let text: String = try #require(sink.texts.first { $0.contains("<lookupinfo>") })
        #expect(text.contains("<call>DL1ABC</call>"))
        #expect(text.contains("<wpxprefix>DL1</wpxprefix>"))
        #expect(app.model.logbook.rows.isEmpty)
    }

    @Test func aReceivedN1mmContactIsForwardedWithAllQsos() async throws {
        let sender = UdpSink()
        let sink = UdpSink()
        defer {
            sender.close()
            sink.close()
        }
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.n1mmRecv.receiveEnabled = true
            config.n1mmRecv.receiveBind = "127.0.0.1:45004"
            config.broadcast.contactsEnabled = true
            config.broadcast.contactsTargets = "127.0.0.1:\(sink.port)"
            config.broadcast.allQsosEnabled = true
        })
        try await app.app.startCqWwCw()
        await eventually("listening") { app.integrations.n1mmPort != nil }
        await eventually("broadcast started") { app.integrations.broadcastActive }
        let port: Int = try #require(app.integrations.n1mmPort)
        sender.send(ReceiveIntegrationTests.n1mm(call: "DL1ABC"), toPort: port)
        await sink.waitFor("<IsOriginal>False</IsOriginal>")
        #expect(sink.texts.contains { $0.contains("<call>DL1ABC</call>") && $0.contains("<IsOriginal>False</IsOriginal>") })
    }

    @Test func aSharedN1mmPortStillReceives() async throws {
        let sender = UdpSink()
        defer { sender.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.n1mmRecv.receiveEnabled = true
            config.n1mmRecv.receiveBind = "127.0.0.1:45004"
            config.n1mmRecv.sharePort = true
        })
        try await app.app.startCqWwCw()
        await eventually("listening") { app.integrations.n1mmPort != nil }
        let port: Int = try #require(app.integrations.n1mmPort)
        sender.send(ReceiveIntegrationTests.n1mm(call: "DL4ABC"), toPort: port)
        await eventually("ingested") { app.model.logbook.rows.map(\.call) == ["DL4ABC"] }
    }
}
