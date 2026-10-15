import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The N1MM per-radio options in the app: the microphone muted during a voice message (opt-in), the band map's radio
/// problem alert after a lost connection and „Reset Radio", and the missing COM port marker. Every rig is a fake
/// `rigctld` on a loopback port; the audio output is a fake.
@MainActor @Suite(.disabled("probe")) struct RigOptionsModelTests {

    private static func voiceApp(_ fake: FakeRigctld, muteMic: Bool) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, dataDir in
            let wav: URL = dataDir.appendingPathComponent("wav")
            try FileManager.default.createDirectory(at: wav, withIntermediateDirectories: true)
            try Data([1]).write(to: wav.appendingPathComponent("cq.wav"))
            for set in [\VoiceKeyerConfig.runMessages, \VoiceKeyerConfig.spMessages] {
                var messages: [FunctionKeyMessage] = config.voiceKeyer[keyPath: set]
                messages[0] = FunctionKeyMessage(label: "CQ", text: "cq.wav")
                config.voiceKeyer[keyPath: set] = messages
            }
            config.voiceKeyer.outputDevice = "Fake Out"
            config.voiceKeyer.pttDelayMs = 0
            config.voiceKeyer.pttViaCat = true
            config.rig = fakeRigConfig(fake.port)
            config.rig.muteMicOnVoice = muteMic
        })
        app.entry.setMode(.ssb)
        await app.connectRig(fake)
        return app
    }

    /// With the option the gain is read and set to 0 before the PTT and restored after its release.
    @Test func voiceMessageMutesAndRestoresTheMic() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await Self.voiceApp(fake, muteMic: true)
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await eventually("released and restored") { fake.writes.last == "+L MICGAIN 0.300000" }
        #expect(fake.writes == ["+l MICGAIN", "+L MICGAIN 0", "T 1", "T 0", "+L MICGAIN 0.300000"])
        #expect(fake.micGain == "0.300000")
        #expect(app.keyer.voice.ptt.mutedRigCount == 0)
    }

    /// Off by default: only the PTT goes to the rig.
    @Test func micIsLeftAloneByDefault() async throws {
        let fake = try FakeRigctld(mode: "USB")
        let app = try await Self.voiceApp(fake, muteMic: false)
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await eventually("PTT off") { fake.writes == ["T 1", "T 0"] }
    }

    /// A lost connection shows the alert once the timeout has passed; „Reset Radio" connects again.
    @Test func lostRigRaisesTheAlertAndResetReconnects() async throws {
        let fake = try FakeRigctld()
        let app = try await RigApp.make(configure: { config, _ in
            config.rig = fakeRigConfig(fake.port)
            config.rig.timeoutSeconds = 15
        })
        defer { app.rig.dismissRadioProblem() }
        var now = Date(timeIntervalSince1970: 1_000_000)
        app.rig.clock = { now }
        fake.dropNextRead()
        app.rig.toggle(vfo: 0)
        await eventually("lost") { app.rig.cat1.lost }
        now = now.addingTimeInterval(5)
        app.rig.checkRadioProblem(0)
        #expect(app.rig.radioProblems.isEmpty)
        now = now.addingTimeInterval(20)
        app.rig.checkRadioProblem(0)
        #expect(app.rig.radioProblems == [0])
        app.rig.resetRadios()
        #expect(app.rig.radioProblems.isEmpty)
        await eventually("connected again") { app.rig.cat1.connected }
        #expect(fake.connectionCount == 2)
    }

    /// A timeout of 0 never raises the alert; a user disconnect never does either.
    @Test func noAlertWithZeroTimeoutOrUserDisconnect() async throws {
        let fake = try FakeRigctld()
        let app = try await RigApp.make(configure: { config, _ in
            config.rig = fakeRigConfig(fake.port)
            config.rig.timeoutSeconds = 0
        })
        var now = Date(timeIntervalSince1970: 1_000_000)
        app.rig.clock = { now }
        fake.dropNextRead()
        app.rig.toggle(vfo: 0)
        await eventually("lost") { app.rig.cat1.lost }
        now = now.addingTimeInterval(600)
        app.rig.checkRadioProblem(0)
        #expect(app.rig.radioProblems.isEmpty)
    }

    /// The missing port marker waits for the port list.
    @Test func missingPortMarkedOnlyAfterListing() async throws {
        let app = try await RigApp.make()
        let tools: SettingsToolsModel = app.model.settingsTools
        #expect(!tools.portMissing("/dev/cu.gone"))
        #expect(tools.portLabel("/dev/cu.gone") == "/dev/cu.gone")
        tools.loadSerialPorts()
        await eventually("listed") { tools.serialPortsListed }
        #expect(tools.portMissing("/dev/cu.gone") == !tools.serialPorts.contains("/dev/cu.gone"))
        #expect(!tools.portMissing(""))
    }
}
