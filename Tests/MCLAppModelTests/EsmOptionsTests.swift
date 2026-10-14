import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM ESM key assignments, partial calls, the call / exchange separator, F-key stacking and the CQ repeat's maximum
/// duration, through the entry window and a fake Winkeyer.
@MainActor @Suite struct EsmOptionsTests {

    private static func make(_ configure: @escaping (inout AppConfig) -> Void = { _ in }) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            configure(&config)
        })
        try await app.app.startCqWwCw()
        app.entry.setMode(.cw)
        app.entry.setFrequency("14025")
        return app
    }

    private static func events(_ app: KeyingApp) -> [String] {
        (app.keying.lastKeyer?.events ?? []).filter { $0.hasPrefix("send ") || $0 == "abort" }
    }

    @Test func assignedKeysSeparatorAndPartialCall() async throws {
        let app = try await Self.make { config in
            config.esm.keyMap = [0, 1, 2, 3, 9, 5, 7]
            config.esm.callExchangeSeparator = " UR "
            config.esm.sendPartialCalls = true
            config.cwKeyer.runMessages[9] = FunctionKeyMessage(label: "Call", text: "!")
            config.cwKeyer.runMessages[1] = FunctionKeyMessage(label: "Exch", text: "5NN 15")
        }
        app.model.operating.applyEsm(true)
        app.model.operating.select(.run, freqHz: 14_025_000)
        app.entry.callChanged("DL1ABD")
        app.entry.handle(.enter(ctrl: false, step: .esm))
        await app.settle()
        #expect(Self.events(app).last == "send DL1ABD UR 5NN 15@28")
        // The call corrected, the exchange copied: only the changed suffix goes before TU.
        app.clock.advance(by: 60_000)
        await app.settle()
        app.entry.callChanged("DL1ABC")
        app.entry.editContestField("zone", "14")
        app.entry.handle(.enter(ctrl: false, step: .esm))
        await app.settle()
        #expect(Self.events(app).last?.hasPrefix("send ABC TU") == true)
    }

    /// With stacking a key pressed while a message is sent is queued: no abort, and its key lights afterwards.
    @Test func stackedKeysAreSentInOrder() async throws {
        let app = try await Self.make { config in
            config.cwKeyer.stackMessages = true
        }
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        app.entry.handle(.functionKey(7, shift: false, ctrlShift: false))
        await app.settle()
        #expect(!Self.events(app).contains("abort"))
        #expect(Self.events(app).count == 2)
        #expect(app.keyer.cwSendingKey == 0)
        app.clock.advance(by: 30_000)
        await app.settle()
        #expect(app.keyer.cwSendingKey == 7)
        app.clock.advance(by: 30_000)
        await app.settle()
        #expect(app.keyer.cwSendingKey == nil)
        // Esc drops the queue.
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        app.entry.handle(.functionKey(7, shift: false, ctrlShift: false))
        await app.settle()
        _ = app.entry.stopSending()
        app.clock.advance(by: 60_000)
        await app.settle()
        #expect(app.keyer.cwSendingKey == nil)
    }

    @Test func withoutStackingANewKeyInterrupts() async throws {
        let app = try await Self.make()
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        app.entry.handle(.functionKey(7, shift: false, ctrlShift: false))
        await app.settle()
        #expect(Self.events(app).contains("abort"))
        #expect(app.keyer.cwSendingKey == 7)
    }
}
