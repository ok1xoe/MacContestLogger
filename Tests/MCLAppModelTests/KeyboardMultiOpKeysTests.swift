import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM multi-op keys: Ctrl+Alt+M switches the station type Run ↔ Mult, Alt+Z announces the pass frequency to the other
/// stations (in-memory network only).
@MainActor @Suite struct KeyboardMultiOpKeysTests {

    @Test func runMultToggleIsSaved() async throws {
        let app = try await TestApp.make()
        #expect(app.model.config.config.cluster.stationType == .none)
        app.model.entry.runShortcut(.toggleStationType)
        #expect(app.model.config.config.cluster.stationType == .run)
        #expect(app.model.status.message == "Typ stanice: RUN")
        app.model.entry.runShortcut(.toggleStationType)
        #expect(app.model.config.config.cluster.stationType == .mult)
        #expect(await app.savedConfigFlushed().cluster.stationType == .mult)
        app.model.entry.runShortcut(.toggleStationType)
        #expect(app.model.config.config.cluster.stationType == .run)
    }

    @Test func passFrequencyNeedsTheNetwork() async throws {
        let app = try await TestApp.make()
        app.model.entry.runShortcut(.passFrequency)
        app.model.dialogs.submitPrompt("14040")
        #expect(app.model.status.message == "Pass frekvence: síťový deník není připojený")
    }

    @Test func passFrequencyReachesTheOtherStation() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        try await a.activate()
        try await b.activate()
        a.model.entry.runShortcut(.passFrequency)
        a.model.dialogs.submitPrompt("14040")
        await eventually("B knows the pass frequency") { b.network.chat.passFrequencies["OP1"] == 14_040_000 }
        await eventually("A says so") { a.network.ownPassFrequencyHz == 14_040_000 }
        #expect(a.status == "Pass frekvence 14040.0 kHz oznámena ostatním stanicím")
        #expect(b.status == "Pass frekvence OP1: 14040.0 kHz")
        a.model.entry.runShortcut(.passFrequency)
        a.model.dialogs.submitPrompt("")
        await eventually("B forgot it") { b.network.chat.passFrequencies["OP1"] == nil }
    }
}
