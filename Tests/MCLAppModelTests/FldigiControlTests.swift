import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// fldigi control from the logger (N1MM): AutoTRXUpdate (the logged frequency is the dial ± fldigi's audio while
/// the Digital Interface polls it), the caption's frequency, the Op Mode menu (`modem.set_by_name`), typing RTTY / PSK
/// switching fldigi's modem, and `{LDIGFQ}`. Fake fldigi XML-RPC and a fake rigctld on loopback only.
@MainActor @Suite struct FldigiControlTests {

    nonisolated private static func answer(_ method: String) -> (status: Int, value: String) {
        switch method {
        case "text.get_rx_length": (200, "0")
        case "modem.get_name": (200, "RTTY")
        case "main.get_trx_state": (200, "RX")
        case "modem.get_carrier": (200, "2125")
        case "modem.get_names":
            (200, "<array><data><value>RTTY</value><value>BPSK31</value><value>OLIVIA</value></data></array>")
        default: (200, "")
        }
    }

    private static func make(_ server: FakeFldigiServer, rig: FakeRigctld,
                             autoTrxUpdate: Bool = true) async throws -> KeyingApp {
        server.respond { answer($0) }
        let app = try await KeyingApp.make(configure: { config, _ in
            config.digital.engine = .fldigi
            config.digital.fldigiHost = "127.0.0.1"
            config.digital.fldigiPort = server.port
            config.digital.autoTrxUpdate = autoTrxUpdate
            config.dataMode = "RTTY"
            config.rig = fakeRigConfig(rig.port)
            winkeyerConfig(&config)
        }, setUp: { keying in
            keying.fldigiPort = server.port
        })
        await app.connectRig(rig)
        await eventually("entry follows the rig") { app.entry.form.mode == .rtty && app.entry.form.freqHz == 14_080_000 }
        return app
    }

    @Test func autoTrxUpdateLogsTheTransmittedFrequency() async throws {
        let server = try FakeFldigiServer()
        let rig = try FakeRigctld(freqHz: 14_080_000, mode: "PKTUSB")
        let app = try await Self.make(server, rig: rig)
        // Without the Digital Interface open there is no audio frequency: the dial is logged.
        #expect(app.entry.loggedFreqHz == 14_080_000)
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        #expect(app.keyer.digital.carrierHz == 2_125)
        #expect(app.entry.loggedFreqHz == 14_082_125)
        #expect(digital.frequencyCaption == "14082.13 kHz · 2125 Hz")
        #expect(app.entry.digitalFrequencyText(vfo: 0) == "14082.1")
        app.entry.callChanged("DL1ABC")
        app.entry.submit()
        await app.entry.settle()
        await app.model.logbook.settle()
        // The QSO carries the frequency at the field's precision (10 Hz).
        #expect(app.model.logbook.rows.last?.freqHz == 14_082_130)
        // Closing the window ends AutoTRXUpdate (N1MM applies it only while the window is open).
        digital.close()
        #expect(app.keyer.digital.carrierHz == nil)
        #expect(app.entry.loggedFreqHz == 14_080_000)
    }

    @Test func autoTrxUpdateOffOrFskKeepsTheDial() async throws {
        let server = try FakeFldigiServer()
        let rig = try FakeRigctld(freqHz: 14_080_000, mode: "PKTUSB")
        let app = try await Self.make(server, rig: rig, autoTrxUpdate: false)
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        #expect(app.entry.loggedFreqHz == 14_080_000)
        digital.setAutoTrxUpdate(true)
        #expect(app.entry.loggedFreqHz == 14_082_125)
        // A typed frequency other than the dial is logged as typed.
        app.entry.setFrequency("14085")
        #expect(app.entry.loggedFreqHz == 14_085_000)
        digital.close()
    }

    @Test func opModeSwitchesFldigiAndTheEntryMode() async throws {
        let server = try FakeFldigiServer()
        let rig = try FakeRigctld(freqHz: 14_080_000, mode: "PKTUSB")
        let app = try await Self.make(server, rig: rig)
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        #expect(digital.opModes.common == ["RTTY", "BPSK31"])
        #expect(digital.opModes.other == ["OLIVIA"])
        digital.selectModem("BPSK31")
        await app.settle()
        #expect(server.requests.contains { $0.contains("modem.set_by_name") && $0.contains("BPSK31") })
        #expect(app.keyer.digital.modem == "BPSK31")
        #expect(app.status == "fldigi: mód BPSK31")
        digital.close()
    }

    /// N1MM: typing RTTY or PSK in the call field switches the digital engine's mode too.
    @Test func typingPskSwitchesFldigi() async throws {
        let server = try FakeFldigiServer()
        let rig = try FakeRigctld(freqHz: 14_080_000, mode: "PKTUSB")
        let app = try await Self.make(server, rig: rig)
        app.model.config.config.digital.pskModem = "BPSK63"
        app.entry.runCommand(.changeMode(mode: .psk))
        await app.settle()
        #expect(server.requests.contains { $0.contains("modem.set_by_name") && $0.contains("BPSK63") })
        app.entry.runCommand(.changeMode(mode: .cw))
        await app.settle()
        #expect(server.requests.filter { $0.contains("modem.set_by_name") }.count == 1, "CW leaves fldigi alone")
    }
}
