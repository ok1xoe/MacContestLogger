import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// DTR/RTS keying and the sound-card monitor through the app's keyer: fake lines, an instant scheduler clock and a
/// recording monitor output — no serial port, no audio device.
@MainActor @Suite struct SerialCwKeyingTests {

    private static func serial(_ config: inout AppConfig, ptt: CwKeyingOptions.SerialLine = .rts) {
        config.cwKeyer.method = .cat
        config.cwKeyer.options.serialKeying = true
        config.cwKeyer.options.serialPort = "fake-serial"
        config.cwKeyer.options.serialKeyLine = .dtr
        config.cwKeyer.options.serialPttLine = ptt
    }

    @Test func messageIsKeyedOnTheLines() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in Self.serial(&config) })
        app.keyer.sendCwText("E")
        await app.settle()
        await eventually("keyed") { app.keying.events.contains("ptt off") }
        #expect(app.keying.events == ["key lines open fake-serial DTR RTS", "ptt on", "key down", "key up", "ptt off"])
        #expect(app.status.isEmpty || !app.status.hasPrefix("CW:"))
    }

    @Test func missingPortShowsItsText() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            Self.serial(&config)
            config.cwKeyer.options.serialPort = ""
        })
        app.keyer.sendCwText("E")
        await app.settle()
        #expect(app.status == "CW: Klíčování DTR/RTS: vyber port v Nastavení → CW klíč")
        #expect(app.keying.events.isEmpty)
    }

    @Test func anotherLineReopensTheKeyer() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in Self.serial(&config, ptt: .none) })
        app.keyer.sendCwText("E")
        await app.settle()
        await eventually("keyed") { app.keying.events.contains("key up") }
        app.model.config.config.cwKeyer.options.serialPttLine = .rts
        app.keyer.sendCwText("E")
        await app.settle()
        await eventually("reopened") { app.keying.events.contains("ptt off") }
        #expect(app.keying.events.contains("key lines close"))
        #expect(app.keying.events.filter { $0.hasPrefix("key lines open") }.count == 2)
    }

    @Test func catPttWithoutARigFailsBeforeKeying() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            Self.serial(&config, ptt: .none)
            config.cwKeyer.options.cwPttViaCat = true
        })
        app.keyer.sendCwText("E")
        await app.settle()
        await eventually("released") { app.keying.events.contains("key up") }
        #expect(!app.keying.events.contains("key down"))
        app.keyer.sendCwText("E")
        await app.settle()
        #expect(app.status == "CW: Klíčování DTR/RTS selhalo: CW přes CAT: TRX není připojený")
    }

    @Test func tuneUsesTheLinesNotCat() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in Self.serial(&config) })
        app.keyer.setTune(true)
        await app.settle()
        await eventually("keyed") { app.keying.events.contains("key down") }
        app.keyer.setTune(false)
        await app.settle()
        await eventually("released") { app.keying.events.contains("ptt off") }
        #expect(Array(app.keying.events.suffix(2)) == ["key up", "ptt off"])
    }

    @Test func monitorIsOffByDefault() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in Self.serial(&config) })
        app.keyer.sendCwText("E")
        await app.settle()
        await eventually("keyed") { app.keying.events.contains("ptt off") }
        #expect(!app.keying.events.contains { $0.hasPrefix("monitor") })
    }

    @Test func monitorPlaysTheMessageOnItsDevice() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.cwKeyer.options.monitorEnabled = true
            config.cwKeyer.options.monitorDevice = "Fake Out"
        })
        app.keyer.sendCwText("E")
        await app.settle()
        // E at 28 WPM: one dit of 1200/28 ms at 24 kHz, 16-bit.
        let expected: Int = Int((1200.0 / 28 * 24).rounded()) * 2
        #expect(app.keying.events.contains("monitor Fake Out \(expected) bytes"))
    }
}
