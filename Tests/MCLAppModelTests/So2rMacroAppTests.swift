import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The N1MM two-radio, OTRSP, contest swap and needed-QSO macros through the entry window (fake keyer, fake OTRSP).
@MainActor @Suite struct So2rMacroAppTests {

    private static func setKey(_ config: inout AppConfig, _ index: Int, _ text: String) {
        config.cwKeyer.spMessages[index] = FunctionKeyMessage(label: "K", text: text)
        config.cwKeyer.runMessages[index] = FunctionKeyMessage(label: "K", text: text)
    }

    private static func press(_ entry: EntryModel, _ index: Int) {
        entry.handle(.functionKey(index, shift: false, ctrlShift: false))
    }

    /// SO2V: `{JUMPRXTX}` makes the other window active; `{CTRLF2}` sends the other window's F2 on its VFO and,
    /// with a call typed here, the focus comes back once it has been sent.
    @Test func jumpAndSendOnTheOtherRadio() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.radioMode = "SO2V"
            Self.setKey(&config, 9, "{JUMPRXTX}")
            Self.setKey(&config, 10, "{CTRLF2}")
            Self.setKey(&config, 1, "OTHER {OTHERFREQROUND}")
        })
        let second: EntryModel = app.model.vfoB.entry
        second.isWindowShown = true
        for entry in [app.entry, second] {
            entry.setMode(.cw)
        }
        app.entry.setFrequency("14025")
        second.setFrequency("7010")
        Self.press(app.entry, 9)
        await runMainQueue()
        #expect(app.model.rig.vfo.activeVfo == 1)
        app.model.rig.activateVfo(0)
        await runMainQueue()
        app.entry.callChanged("DL1ABC")
        Self.press(app.entry, 10)
        await app.settle()
        #expect(app.model.rig.vfo.activeVfo == 1)
        #expect((app.keying.lastKeyer?.events ?? []).last == "send OTHER 14025@28")
        app.clock.advance(by: 60_000)
        await app.settle()
        await runMainQueue()
        #expect(app.model.rig.vfo.activeVfo == 0)
    }

    @Test func otrspAndStereo() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2R"
            config.otrspPort = "/dev/fake-otrsp"
            Self.setKey(&config, 9, "{OTRSP AUX15}{OTRSPOTHER RX}{STEREOON}")
        }
        await rigApp.settle()
        await rigApp.model.peripherals.settle()
        await runMainQueue()
        #expect(rigApp.model.peripherals.otrspOpen)
        rigApp.entry.setMode(.cw)
        Self.press(rigApp.entry, 9)
        await rigApp.model.peripherals.settle()
        #expect(rigApp.hardware.events.filter { $0.hasPrefix("otrsp ") && !$0.hasPrefix("otrsp open") }
            .suffix(3) == ["otrsp AUX15", "otrsp RX2", "otrsp RX1S"])
        #expect(rigApp.model.rig.vfo.stereo)
    }

    /// `{ACTIVEAUDIOTOGGLE}` mutes the active rig over CAT (hamlib MUTE), again unmutes it; the inactive rig needs
    /// SO2R.
    @Test func audioMute() async throws {
        let fake = try FakeRigctld(freqHz: 14_025_000)
        defer { fake.stop() }
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port)
            Self.setKey(&config, 9, "{ACTIVEAUDIOTOGGLE}")
            Self.setKey(&config, 10, "{INACTIVEAUDIOOFF}")
        }
        await rigApp.connect()
        rigApp.entry.setMode(.cw)
        Self.press(rigApp.entry, 9)
        Self.press(rigApp.entry, 9)
        await rigApp.settle()
        #expect(fake.commands.filter { $0.contains("MUTE") } == ["+U MUTE 1", "+U MUTE 0"])
        Self.press(rigApp.entry, 10)
        #expect(rigApp.status.contains("SO2R"))
    }

    @Test func otrspWithoutADevice() async throws {
        let rigApp = try await RigApp.make { config, _ in
            Self.setKey(&config, 9, "{OTRSP RX1}")
            Self.setKey(&config, 10, "{STEREOON}")
        }
        rigApp.entry.setMode(.cw)
        Self.press(rigApp.entry, 9)
        #expect(rigApp.status.contains("OTRSP"))
        Self.press(rigApp.entry, 10)
        #expect(rigApp.status.contains("SO2R"))
    }

    /// `{POPNEXTNEEDEDQ}`: the stations worked on 20 m but not yet on 40 m, in log order, with their zone.
    @Test func neededStationsOnThisBand() async throws {
        let app = try await TestApp.make { config, _ in
            Self.setKey(&config, 9, "{POPNEXTNEEDEDQ}")
            Self.setKey(&config, 10, "{POPPREVNEEDEDQ}")
        }
        try await app.startCqWwCw()
        let entry: EntryModel = app.model.entry
        entry.setMode(.cw)
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")
        await app.logContestQso(call: "DL1ABC", zone: "14", freqKHz: "7025")
        entry.wipe()
        entry.setFrequency("7025")
        Self.press(entry, 9)
        #expect(entry.form.call == "W1AW")
        #expect(entry.form.contestExchange["zone"] == "5")
        Self.press(entry, 9)
        #expect(entry.form.call == "W1AW")
        entry.setFrequency("21025")
        Self.press(entry, 10)
        #expect(entry.form.call == "DL1ABC")
        Self.press(entry, 10)
        #expect(entry.form.call == "W1AW")
    }

    /// `{SWAPCONTESTS}` opens the previous contest and the call typed moves along.
    @Test func swapContests() async throws {
        let app = try await TestApp.make { config, _ in
            Self.setKey(&config, 9, "{SWAPCONTESTS}")
        }
        try await app.startCqWwCw()
        let first: String? = app.model.contest.activeId
        var setup = ContestSetup()
        setup.sentExchange = ["zone": "15"]
        #expect(await app.model.contest.createAndStart(definitionId: "cq-ww-cw", setup: setup))
        await app.model.contest.refreshRecent()
        let second: String? = app.model.contest.activeId
        #expect(first != second)
        let entry: EntryModel = app.model.entry
        entry.setMode(.cw)
        entry.callChanged("OK2ABC")
        Self.press(entry, 9)
        await app.model.contest.recentOpenTask?.value
        await runMainQueue()
        await app.model.contest.settleActivations()
        await runMainQueue()
        #expect(app.model.contest.activeId == first)
        #expect(entry.form.call == "OK2ABC")
    }
}
