import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// fldigi's tuning from the Digital Interface (N1MM): AFC / NET / Rev / Lock read and set, Align (the rig retuned on
/// a fake rigctld, the cursor moved), AFC with CQ, NET with the Run change and Shift Frequency Compensation. Fake
/// fldigi and rigctld on loopback only.
@MainActor @Suite struct FldigiTuningModelTests {

    nonisolated private static func answer(_ method: String) -> (status: Int, value: String) {
        switch method {
        case "text.get_rx_length": (200, "0")
        case "modem.get_name": (200, "RTTY")
        case "main.get_trx_state": (200, "RX")
        case "modem.get_carrier": (200, "2300")
        case "main.get_afc": (200, "<boolean>1</boolean>")
        case "main.get_lock", "main.get_reverse": (200, "<boolean>0</boolean>")
        default: (200, "")
        }
    }

    private static func make(rawMode: String, configure: @escaping (inout AppConfig) -> Void = { _ in }) async throws
        -> (KeyingApp, FakeFldigiServer, FakeRigctld, DigitalInterfaceModel) {
        let server = try FakeFldigiServer()
        server.respond { answer($0) }
        let rig = try FakeRigctld(freqHz: 14_080_000, mode: rawMode)
        let app = try await KeyingApp.make(configure: { config, _ in
            config.digital.engine = .fldigi
            config.digital.fldigiHost = "127.0.0.1"
            config.digital.fldigiPort = server.port
            config.dataMode = "RTTY"
            config.rig = fakeRigConfig(rig.port)
            winkeyerConfig(&config)
            configure(&config)
        }, setUp: { keying in
            keying.fldigiPort = server.port
        })
        await app.connectRig(rig)
        await eventually("entry follows the rig") { app.entry.form.freqHz == 14_080_000 }
        app.entry.setMode(.rtty)
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        return (app, server, rig, digital)
    }

    @Test func switchesAreReadAndSet() async throws {
        let (app, server, rig, digital) = try await Self.make(rawMode: "PKTUSB")
        #expect(digital.isOn(.afc) == true)
        #expect(digital.isOn(.lock) == false)
        #expect(digital.net == true)
        digital.toggle(.afc)
        await app.settle()
        #expect(digital.isOn(.afc) == false)
        #expect(server.requests.contains { $0.contains("main.set_afc") && $0.contains("<boolean>0</boolean>") })
        digital.toggle(.lock)
        await app.settle()
        #expect(digital.net == false)
        digital.close()
        _ = rig
    }

    @Test func alignRetunesTheRigAndMovesTheCursor() async throws {
        let (app, server, rig, digital) = try await Self.make(rawMode: "PKTUSB")
        digital.align()
        await app.settle()
        await eventually("rig retuned") { rig.commands.contains { $0.hasPrefix("F 14080090") } }
        #expect(server.requests.contains { $0.contains("modem.set_carrier") && $0.contains("2210") })
        digital.close()
    }

    @Test func afcWithCqAndNetWithRunChange() async throws {
        let (app, server, rig, digital) = try await Self.make(rawMode: "PKTUSB") { config in
            config.digital.afcOnCq = true
            config.digital.netWithRunChange = true
            config.digital.runMessages[0] = FunctionKeyMessage(label: "CQ", text: "CQ TEST")
        }
        app.model.operating.select(.run, freqHz: 14_080_000)
        await runMainQueue()
        await app.settle()
        #expect(server.requests.contains { $0.contains("main.set_lock") && $0.contains("<boolean>1</boolean>") },
                "Run: NET off = Lock on")
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        #expect(server.requests.contains { $0.contains("main.set_afc") && $0.contains("<boolean>1</boolean>") })
        app.model.operating.select(.searchAndPounce, freqHz: 14_085_000)
        await runMainQueue()
        await app.settle()
        #expect(server.requests.last { $0.contains("main.set_lock") }?.contains("<boolean>0</boolean>") == true)
        digital.close()
        _ = rig
    }

    @Test func shiftCompensationInFsk() async throws {
        let (app, _, rig, digital) = try await Self.make(rawMode: "RTTY") { config in
            config.digital.shiftCompEnabled = true
            config.digital.shiftCompHz = 170
        }
        #expect(app.entry.loggedFreqHz == 14_080_170)
        digital.close()
        _ = rig
    }
}
