import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Control macros in SSB F-key messages: executed in message order with a fake audio output (no real audio, rig or
/// network), never looked up as wav files.
@MainActor @Suite struct VoiceMacroModelTests {

    private static func make(f1: String, f2: String = "tu.wav") async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, dataDir in
            let wav: URL = dataDir.appendingPathComponent("wav")
            try FileManager.default.createDirectory(at: wav, withIntermediateDirectories: true)
            try Data([1]).write(to: wav.appendingPathComponent("cq.wav"))
            try Data([1]).write(to: wav.appendingPathComponent("tu.wav"))
            for set in [\VoiceKeyerConfig.runMessages, \VoiceKeyerConfig.spMessages] {
                var messages: [FunctionKeyMessage] = config.voiceKeyer[keyPath: set]
                messages[0] = FunctionKeyMessage(label: "A", text: f1)
                messages[1] = FunctionKeyMessage(label: "B", text: f2)
                config.voiceKeyer[keyPath: set] = messages
            }
            config.voiceKeyer.outputDevice = "Fake Out"
            config.voiceKeyer.pttDelayMs = 0
            config.voiceKeyer.pttViaCat = false
        })
        app.entry.setMode(.ssb)
        return app
    }

    /// Records the actions in the fake audio's event log, so the order against playback is visible.
    private static func record(_ app: KeyingApp) {
        let keying = app.keying
        app.keyer.voice.performAction = { action in keying.record("action \(action.rawValue)") }
    }

    private static func pressF(_ app: KeyingApp, _ index: Int) {
        app.entry.handle(.functionKey(index, shift: false, ctrlShift: false))
    }

    @Test func actionsRunInMessageOrderAroundTheAudio() async throws {
        let app = try await Self.make(f1: "{WIPE},cq.wav,{LOG},tu.wav,{RUN}")
        Self.record(app)
        Self.pressF(app, 0)
        await eventually("done") { app.keying.events.count == 5 && app.keyer.voice.playingKey == nil }
        #expect(app.keying.events == ["action WIPE", "play cq.wav on Fake Out", "action LOG", "play tu.wav on Fake Out",
                                      "action RUN"])
        #expect(app.keyer.sendFailures == 0)
    }

    @Test func unknownMacroWarnsAndIsNotPlayed() async throws {
        let app = try await Self.make(f1: "cq.wav,{NOPE}")
        Self.record(app)
        Self.pressF(app, 0)
        await eventually("planned") { !app.keyer.voice.planning }
        #expect(app.status == "F1: makra {NOPE} zatím neumím — vynechána")
        await eventually("played") { app.keying.events == ["play cq.wav on Fake Out"] }
    }

    @Test func actionOnlyMessageKeysNothing() async throws {
        let app = try await Self.make(f1: "{S&P}")
        Self.pressF(app, 0)
        await eventually("planned") { !app.keyer.voice.planning }
        #expect(app.model.operating.runMode == .searchAndPounce)
        #expect(app.keyer.sendFailures == 0)
        #expect(app.keyer.voice.playingKey == nil)
        await app.settle()
        #expect(app.keying.events.isEmpty)
    }

    @Test func functionKeyChainingExpandsTheOtherKey() async throws {
        let app = try await Self.make(f1: "cq.wav,{F2}", f2: "tu.wav,{LOG}")
        Self.record(app)
        Self.pressF(app, 0)
        await eventually("done") { app.keying.events.count == 3 && app.keyer.voice.playingKey == nil }
        #expect(app.keying.events == ["play cq.wav on Fake Out", "play tu.wav on Fake Out", "action LOG"])
    }

    @Test func escapeMidMessageDoesNotRunTheTrailingLog() async throws {
        let app = try await Self.make(f1: "cq.wav,{LOG}")
        Self.record(app)
        app.keying.holdPlayback()
        Self.pressF(app, 0)
        await eventually("playing") { app.keying.events == ["play cq.wav on Fake Out"] }
        #expect(app.entry.stopSending())
        app.keying.releasePlayback()
        await eventually("over") { !app.keyer.voice.isOnAir }
        await app.settle()
        #expect(app.keying.events == ["play cq.wav on Fake Out"])
    }
}
