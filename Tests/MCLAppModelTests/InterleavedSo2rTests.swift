import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM 2BSIQ (two band split interleaved QSOs) in SO2R: independent ESM sequences and last keys in the two entry
/// windows, typing in one window never interrupts the other radio's transmission, and a CQ repeat ends when a message
/// is sent on the other radio. Fake Winkeyer and a manual keyer clock; nothing real is keyed.
@MainActor @Suite struct InterleavedSo2rTests {

    private static func make(_ configure: @escaping (inout AppConfig) -> Void = { _ in }) async throws
        -> (KeyingApp, EntryModel) {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.radioMode = "SO2R"
            config.esm.enabled = true
            configure(&config)
        })
        let second: EntryModel = app.model.vfoB.entry
        second.isWindowShown = true
        for entry in [app.entry, second] {
            entry.setMode(.cw)
        }
        app.entry.setFrequency("14025")
        second.setFrequency("7010")
        app.model.operating.setRunMode(.run, window: 0)
        app.model.operating.setRunMode(.run, window: 1)
        return (app, second)
    }

    private static func events(_ app: KeyingApp) -> [String] {
        app.keying.lastKeyer?.events ?? []
    }

    private static func sends(_ app: KeyingApp) -> Int {
        events(app).filter { $0.hasPrefix("send ") }.count
    }

    private static func type(_ entry: EntryModel, _ call: String) {
        var text = ""
        for character in call {
            text.append(character)
            entry.callChanged(text)
        }
    }

    @Test func cqRepeatEndsWhenTheOtherRadioTransmits() async throws {
        let (app, second) = try await Self.make()
        let operating: OperatingModel = app.model.operating
        app.entry.runShortcut(.cqRepeat)
        #expect(operating.cqRepeat)
        #expect(operating.cqRepeatWindow == 0)
        await app.settle()
        // The repeat's own window keeps it.
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        #expect(operating.cqRepeat)
        // Typing on the other radio does not end it ...
        second.callChanged("W1AW")
        #expect(operating.cqRepeat)
        // ... a message sent there does.
        second.handle(.functionKey(3, shift: false, ctrlShift: false))
        await app.settle()
        #expect(!operating.cqRepeat)
        #expect(app.model.rig.vfo.txVfo == 1)
    }

    @Test func cqRepeatOfOneWindowOnlyEndsInSo2r() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.radioMode = "SO2V"
        })
        let second: EntryModel = app.model.vfoB.entry
        second.isWindowShown = true
        app.entry.setMode(.cw)
        second.setMode(.cw)
        app.model.operating.cqRepeatWindow = 1
        app.model.operating.applyCqRepeat(true)
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        #expect(app.model.operating.cqRepeat)
    }

    @Test func typingDoesNotInterruptTheOtherRadio() async throws {
        let (app, second) = try await Self.make { config in
            config.autoSendThreshold = 1
        }
        let rig: MCLAppModel.RigModel = app.model.rig
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        #expect(app.keyer.isSending)
        #expect(Self.sends(app) == 1)
        // The entry focus moves to rig 2 (the second keyboard, `\`, a click); AutoSend would send the call there.
        rig.activateVfo(1, rxOnly: true)
        Self.type(second, "W1AW")
        await app.settle()
        #expect(Self.sends(app) == 1)
        #expect(!Self.events(app).contains("abort"))
        #expect(rig.vfo.txVfo == 0)
        #expect(app.keyer.isSending)
        // Once rig 1 has finished, the ESM Enter sends the whole call on rig 2.
        for _ in 0..<600 where app.keyer.isSending {
            app.clock.advance(by: 100)
            await app.settle()
        }
        #expect(!app.keyer.isSending)
        second.esmEnter()
        await app.settle()
        #expect(Self.sends(app) == 2)
        #expect(rig.vfo.txVfo == 1)
        #expect(second.esmProgress.sentCall == "W1AW")
    }

    @Test func autoSendStillWorksWithOneRadioSending() async throws {
        let (app, second) = try await Self.make { config in
            config.autoSendThreshold = 1
        }
        app.model.rig.activateVfo(1, rxOnly: true)
        Self.type(second, "W1AW")
        await app.settle()
        #expect(Self.sends(app) >= 1)
        #expect(app.model.rig.vfo.txVfo == 1)
    }

    @Test func eachWindowKeepsItsOwnEsmProgressAndLastKeys() async throws {
        let (app, second) = try await Self.make()
        let operating: OperatingModel = app.model.operating
        app.entry.callChanged("DL1ABC")
        app.entry.esmEnter()
        await app.settle()
        let first: EsmProgress = app.entry.esmProgress
        #expect(first.sentCall == "DL1ABC")
        #expect(second.esmProgress == .empty)
        // Rig 2 starts its own QSO meanwhile; rig 1's progress stays.
        second.callChanged("W1AW")
        second.esmEnter()
        await app.settle()
        #expect(second.esmProgress.sentCall == "W1AW")
        #expect(app.entry.esmProgress == first)
        // `=` repeats the window's own last message.
        let firstKeys: [Int] = operating.lastSentKeys(window: 0)
        let secondKeys: [Int] = operating.lastSentKeys(window: 1)
        #expect(!firstKeys.isEmpty && !secondKeys.isEmpty)
        second.handle(.functionKey(6, shift: false, ctrlShift: false))
        await app.settle()
        #expect(operating.lastSentKeys(window: 1) == [6])
        #expect(operating.lastSentKeys(window: 0) == firstKeys)
        #expect(operating.lastSentKeys == firstKeys)
    }
}
