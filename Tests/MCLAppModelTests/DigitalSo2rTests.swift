import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Two Digital Interfaces (N1MM SO2V/SO2R): DI2 reads the second fldigi and works with the VFO B window, the F-keys of
/// the active VFO B window transmit through the second fldigi, the DI switch shortcuts open the windows, and the
/// additional RX windows feed the Grab window. Two fake fldigi servers on loopback.
@MainActor @Suite struct DigitalSo2rTests {

    typealias Fldigi = DigitalInterfaceRxTests.Fldigi

    private static func make(_ one: FakeFldigiServer, _ two: FakeFldigiServer,
                             configure: @escaping (inout AppConfig) -> Void = { _ in }) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            config.digital.engine = .fldigi
            config.digital.fldigiHost = "127.0.0.1"
            config.digital.fldigiPort = one.port
            config.digital.fldigi2Host = "127.0.0.1"
            config.digital.fldigi2Port = two.port
            config.radioMode = "SO2V"
            winkeyerConfig(&config)
            configure(&config)
        }, setUp: { keying in
            keying.fldigiPort = one.port
            keying.allowedFldigiPorts = [one.port, two.port]
        })
        for entry in [app.entry, app.model.vfoB.entry] {
            entry.setMode(.rtty)
            entry.setFrequency("14080")
        }
        app.model.vfoB.entry.isWindowShown = true
        return app
    }

    @Test func di2ReadsTheSecondFldigiAndFillsVfoB() async throws {
        let first = Fldigi()
        let second = Fldigi()
        let one = try FakeFldigiServer()
        let two = try FakeFldigiServer()
        one.respond { first.answer($0) }
        two.respond { second.answer($0) }
        let app = try await Self.make(one, two)
        first.receive("CQ DE DL1ABC ")
        second.receive("CQ DE JA1XYZ ")
        let di2: DigitalInterfaceModel = app.model.makeDigitalInterface(index: 1)
        di2.open()
        await app.settle()
        #expect(di2.text == "CQ DE JA1XYZ ")
        #expect(one.methods.isEmpty, "DI2 never asks the first fldigi")
        di2.tap(offset: 7)
        #expect(app.model.vfoB.entry.form.call == "JA1XYZ")
        #expect(app.entry.form.call.isEmpty)
        di2.close()
    }

    @Test func vfoBTransmitsThroughTheSecondFldigi() async throws {
        let first = Fldigi()
        let second = Fldigi()
        let one = try FakeFldigiServer()
        let two = try FakeFldigiServer()
        one.respond { first.answer($0) }
        two.respond { second.answer($0) }
        let app = try await Self.make(one, two)
        app.model.rig.activateVfo(1)
        await runMainQueue()
        #expect(app.keyer.digital.current == 1)
        app.model.vfoB.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        #expect(two.methods.contains("text.add_tx"))
        #expect(!one.methods.contains("text.add_tx"))
        #expect(app.entry.stopSending() || true)
        app.model.vfoB.entry.runShortcut(.digitalLeft)
        #expect(app.model.windows.isOpen("digitalinterface"))
        app.entry.runShortcut(.digitalRight)
        #expect(app.model.windows.isOpen("digitalinterface2"))
    }

    @Test func additionalRxWindowsFeedTheGrabWindow() async throws {
        let first = Fldigi()
        let extra = Fldigi()
        let one = try FakeFldigiServer()
        let two = try FakeFldigiServer()
        one.respond { first.answer($0) }
        two.respond { extra.answer($0) }
        let app = try await Self.make(one, two) { config in
            config.digital.fldigi2Port = 0
            config.digital.extraRx = "127.0.0.1:\(two.port)"
        }
        first.receive("CQ DE DL1ABC ")
        extra.receive("CQ DE OK2XYZ ")
        let di1: DigitalInterfaceModel = app.model.makeDigitalInterface()
        di1.open()
        await app.settle()
        #expect(di1.extraTexts == ["CQ DE OK2XYZ "])
        #expect(di1.recentCalls.contains("OK2XYZ"))
        #expect(di1.recentCalls.contains("DL1ABC"))
        di1.close()
    }
}
