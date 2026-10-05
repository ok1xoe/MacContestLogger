import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// The shared program messages of the Info window (Kotlin `MessageLog(200)` + `messageRevision`).
@MainActor @Suite struct MessagesModelTests {

    static let at = Date(timeIntervalSince1970: 1_764_417_600)

    @Test func batchesShareOneRevisionAndTheCapDropsTheOldest() throws {
        let messages = MessagesModel()
        messages.add([], at: Self.at)
        #expect(messages.revision == 0)
        messages.add(["Cabrillo: a", "   ", " Cabrillo: b "], at: Self.at)
        #expect(messages.revision == 1)
        #expect(messages.lines.map(\.text) == ["Cabrillo: a", "Cabrillo: b"])
        #expect(messages.lines.first?.at == JavaInstant(date: Self.at))
        #expect(try messages.asText() == "1200Z  Cabrillo: a\n1200Z  Cabrillo: b")

        for index in 0..<MessagesModel.capacity {
            messages.add("m" + String(index), at: Self.at)
        }
        #expect(messages.lines.count == 200)
        #expect(messages.lines.first?.text == "m0")
        #expect(messages.lines.last?.text == "m199")
        #expect(messages.revision == 201)
        messages.clear()
        #expect(messages.lines.isEmpty)
    }

    /// The Cabrillo warnings land in the app's shared messages with the app's clock.
    @Test func cabrilloWarningsGoToTheSharedMessages() async throws {
        let app = try await TestApp.make(fixedNow: Self.at) { config, _ in
            config.station.call = ""
        }
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.model.exports.exportCabrillo(to: app.dir.child("x.log"))
        let lines: [MessageLog.Entry] = app.model.messages.lines
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.text.hasPrefix("Cabrillo: ") && $0.at == JavaInstant(date: Self.at) })
        #expect(app.model.messages.revision == 1)
    }
}
