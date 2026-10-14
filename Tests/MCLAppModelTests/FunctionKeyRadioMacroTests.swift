import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// `{END}` and the rig macros through the entry window, against a fake Winkeyer and a fake `rigctld` on the loopback
/// (no real rig is ever touched).
@MainActor @Suite struct FunctionKeyRadioMacroTests {

    private static func setKey(_ config: inout AppConfig, _ index: Int, _ text: String) {
        config.cwKeyer.spMessages[index] = FunctionKeyMessage(label: "K", text: text)
        config.cwKeyer.runMessages[index] = FunctionKeyMessage(label: "K", text: text)
    }

    private static func press(_ entry: EntryModel, _ index: Int) {
        entry.handle(.functionKey(index, shift: false, ctrlShift: false))
    }

    // MARK: - {END}

    /// `TU {END}{PGDN}`: the QSY waits for the message to finish; Esc drops it.
    @Test func endRunsAfterTheMessage() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            Self.setKey(&config, 2, "TU {END}{PGDN}")
            config.macroQsyStepKHz = 2
        })
        app.entry.setMode(.cw)
        app.entry.setFrequency("14025")
        Self.press(app.entry, 2)
        await app.settle()
        #expect(app.keyer.cwSendingKey == 2)
        #expect(app.entry.form.freqHz == 14_025_000)
        app.clock.advance(by: 60_000)
        await app.settle()
        await runMainQueue()
        #expect(app.keyer.cwSendingKey == nil)
        #expect(app.entry.form.freqHz == 14_027_000)

        // Esc while it sends: the deferred QSY never runs.
        Self.press(app.entry, 2)
        await app.settle()
        _ = app.entry.stopSending()
        app.clock.advance(by: 60_000)
        await app.settle()
        await runMainQueue()
        #expect(app.entry.form.freqHz == 14_027_000)
    }

    /// `{PGUP}` moves down and `{PGDN}` up (N1MM), by the configured step.
    @Test func pageMacrosStepTheFrequency() async throws {
        let rigApp = try await RigApp.make { config, _ in
            Self.setKey(&config, 9, "{PGUP}")
            Self.setKey(&config, 10, "{FREQUP}{FREQUP}")
            config.macroQsyStepKHz = 3
        }
        rigApp.entry.setMode(.cw)
        rigApp.entry.setFrequency("7020")
        Self.press(rigApp.entry, 9)
        #expect(rigApp.entry.form.freqHz == 7_017_000)
        Self.press(rigApp.entry, 10)
        #expect(rigApp.entry.form.freqHz == 7_023_000)
    }

    // MARK: - CAT, antennas, PTT

    /// Raw CAT macros go to the fake `rigctld` as `w` commands; `{ANTRXnTOGGLE}` selects the port, then toggles its
    /// RX antenna; `{AUXANTSEL}` applies the antenna table's entry.
    @Test func catAndAntennaMacros() async throws {
        let fake = try FakeRigctld(freqHz: 14_025_000)
        defer { fake.stop() }
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port)
            Self.setKey(&config, 8, "{CAT1ASC PB1;\\PB2;}{CAT1HEX FE FD}{CATI2ASC XX;}")
            Self.setKey(&config, 9, "{ANTRX2TOGGLE}")
            Self.setKey(&config, 10, "{AUXANTSEL 3}")
            config.antennaViaRig = true
            config.antennas = [AntennaEntry(code: 3, name: "Yagi", bands: "40m", sector: "")]
        }
        await rigApp.connect()
        rigApp.entry.setMode(.cw)
        Self.press(rigApp.entry, 8)
        Self.press(rigApp.entry, 9)
        Self.press(rigApp.entry, 9)
        Self.press(rigApp.entry, 10)
        await rigApp.settle()
        let sent: [String] = fake.commands.filter { $0.hasPrefix("+w") || $0.hasPrefix("+Y") || $0.hasPrefix("Y") }
        #expect(sent == ["+w PB1;", "+w PB2;", "+w \\0xFE\\0xFD", "+Y 2 0", "+Y 2 1", "Y 3 0"])
        #expect(rigApp.rig.auxAntenna?.name == "Yagi")
    }

    /// `{TX}` alone keys the active rig's PTT; Esc releases it.
    @Test func manualPttUntilEsc() async throws {
        let fake = try FakeRigctld(freqHz: 14_025_000)
        defer { fake.stop() }
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.rig = fakeRigConfig(fake.port)
            Self.setKey(&config, 11, "{TX}")
        })
        await app.connectRig(fake)
        app.entry.setMode(.cw)
        Self.press(app.entry, 11)
        await app.model.rig.settle()
        await app.settle()
        #expect(app.keyer.isTuning)
        #expect(fake.commands.contains("T 1"))
        _ = app.entry.stopSending()
        await app.model.rig.settle()
        await app.settle()
        #expect(!app.keyer.isTuning)
        #expect(fake.commands.last { $0.hasPrefix("T ") } == "T 0")
    }

    // MARK: - Telnet and wav directory

    @Test func telnetWithoutAClusterAndSetWavDir() async throws {
        let rigApp = try await RigApp.make { config, _ in
            Self.setKey(&config, 9, "{TELNET sh/dx}")
            Self.setKey(&config, 10, "{SETWAVDIR {OPERATOR}_2}")
            config.station.call = "OK1XOE"
        }
        rigApp.entry.setMode(.cw)
        var sentToCluster: [String] = []
        rigApp.entry.clusterCommand = { command in
            sentToCluster.append(command)
            return true
        }
        Self.press(rigApp.entry, 9)
        #expect(sentToCluster == ["sh/dx"])
        rigApp.entry.clusterCommand = { _ in false }
        Self.press(rigApp.entry, 9)
        #expect(rigApp.status.contains("{TELNET}"))
        Self.press(rigApp.entry, 10)
        #expect(rigApp.model.operating.wavDirName == "OK1XOE_2")
        rigApp.model.operating.operatorCall = "OK1ABC"
        #expect(rigApp.model.operating.wavDirName == nil)
    }
}
