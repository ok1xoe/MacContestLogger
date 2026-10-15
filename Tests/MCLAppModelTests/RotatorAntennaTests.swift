import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The N1MM rotor parity over fake rotators (a loopback `rotctld`, the recorded UDP message, a loopback broadcast):
/// the antenna's rotors / offset / bidirectional flag, a heading typed in the call field, named rotors with limits,
/// the presets, the network rotors, the grid bearing and the antenna chosen again by bearing when a call is entered.
@MainActor @Suite struct RotatorAntennaTests {

    private static func udpMessage(_ rotor: String, _ azimuth: String, offset: Int = 0, bidirectional: Int = 0,
                                   band: Int = 14) -> String {
        "udp 127.0.0.1:12040 <N1MMRotor><rotor>\(rotor)</rotor><goazi>\(azimuth)</goazi><offset>\(offset)</offset>"
            + "<bidirectional>\(bidirectional)</bidirectional><freqband>\(band)</freqband></N1MMRotor>"
    }

    /// The tuned antenna's offset is taken off the bearing.
    @Test func theAntennaOffset() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.rotatorHost = "127.0.0.1"
            config.rotatorPort = fake.port
            config.antennas = [AntennaEntry(code: 1, name: "Yagi", bands: "20m", sector: "", offset: 30)]
        }
        let rotator: RotatorModel = rigApp.rig.rotator
        await eventually("first poll") { rotator.azimuth != nil }
        rigApp.entry.setFrequency("14025")
        #expect(rigApp.rig.antenna.current?.name == "Yagi")
        rotator.turnTo(90)
        await rigApp.settle()
        #expect(rigApp.status == "Rotátor → 90°")
        #expect(fake.writes == ["P 60.0 0"])
    }

    /// A bidirectional antenna turns to the nearer end: the rotor reads 123°, so 300° is reached by the back end at
    /// 120°; another band's antenna does not apply.
    @Test func aBidirectionalAntenna() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.rotatorHost = "127.0.0.1"
            config.rotatorPort = fake.port
            config.antennas = [AntennaEntry(code: 1, name: "SteppIR", bands: "20m", sector: "", bidirectional: true)]
        }
        let rotator: RotatorModel = rigApp.rig.rotator
        await eventually("first poll") { rotator.azimuth != nil }
        rigApp.entry.setFrequency("14025")
        rotator.turnTo(300)
        await rigApp.settle()
        rigApp.entry.setFrequency("7025")
        rotator.turnTo(300)
        await rigApp.settle()
        #expect(fake.writes == ["P 120.0 0", "P 300.0 0"])
    }

    /// N1MM: a heading typed in the call field and Alt+J (Ctrl+Alt+J the opposite direction).
    @Test func aHeadingTypedInTheCallField() async throws {
        let rigApp = try await RotatorModelTests.app(rotctld: nil, udp: true)
        rigApp.entry.setFrequency("14025")
        rigApp.entry.callChanged("270")
        rigApp.entry.runShortcut(.rotorTurn)
        #expect(rigApp.status == "Rotátor (UDP) → 270°")
        rigApp.entry.runShortcut(.rotorLong)
        #expect(rigApp.status == "Rotátor (UDP) → 90°")
        await rigApp.settle()
        #expect(rigApp.hardware.events == [Self.udpMessage("Beam &amp; Co", "270.0"),
                                           Self.udpMessage("Beam &amp; Co", "90.0")])
    }

    /// An antenna on two rotors turns the stack: one message per rotor, with the antenna's offset; Stop stops them
    /// and the selected rotor.
    @Test func aStackTurnsEveryRotor() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.rotorUdpHost = "127.0.0.1"
            config.rotorUdpName = "Main"
            config.antennas = [AntennaEntry(code: 1, name: "Stack", bands: "20m", sector: "", rotors: "Top, Bottom",
                                            offset: 10)]
        }
        let rotator: RotatorModel = rigApp.rig.rotator
        rigApp.entry.setFrequency("14025")
        rotator.turnTo(45)
        rotator.stop()
        await rigApp.settle()
        #expect(rigApp.hardware.events == [
            Self.udpMessage("Top", "45.0", offset: 10), Self.udpMessage("Bottom", "45.0", offset: 10),
            "udp 127.0.0.1:12040 <N1MMRotor><stop>Top</stop></N1MMRotor>",
            "udp 127.0.0.1:12040 <N1MMRotor><stop>Bottom</stop></N1MMRotor>",
            "udp 127.0.0.1:12040 <N1MMRotor><stop>Main</stop></N1MMRotor>",
        ])
    }

    /// A named rotor of the setup with a south stop (-180…180) and a calibration: the window picks it, its position is
    /// read with the calibration, and a turn sends the controller's own azimuth.
    @Test func aNamedRotorWithLimitsAndCalibration() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            var setup = RotorSetup()
            setup.rotors = [RotorEntry(name: "South", host: "127.0.0.1", port: fake.port, calibration: 2,
                                       minAzimuth: -180, maxAzimuth: 180)]
            setup.presets = [nil, 300]
            config.rotor = setup
        }
        let rotator: RotatorModel = rigApp.rig.rotator
        #expect(rotator.rotorChoices == ["", "South"])
        #expect(rotator.azimuth == nil)
        rotator.selectRotor("south")
        #expect(rotator.selectedRotor == "South")
        await eventually("named rotor poll") { rotator.azimuth != nil }
        #expect(rotator.azimuth == 125)
        rotator.turnSelected(to: 272)
        await rigApp.settle()
        #expect(rigApp.status == "Rotátor → 272°")
        rotator.turnToPreset(0)
        rotator.turnToPreset(1)
        await rigApp.settle()
        #expect(fake.writes == ["P -90.0 0", "P -62.0 0"])
        rotator.selectRotor("")
        #expect(rotator.selectedRotor == "")
        #expect(rotator.azimuth == nil)
    }

    /// A rotor whose limits cannot reach the heading goes to the nearer limit and says so.
    @Test func aLimitedRotorStopsAtItsLimit() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            var setup = RotorSetup()
            setup.rotors = [RotorEntry(name: "Short", host: "127.0.0.1", port: fake.port, minAzimuth: 30,
                                       maxAzimuth: 300)]
            config.rotor = setup
        }
        let rotator: RotatorModel = rigApp.rig.rotator
        rotator.selectRotor("Short")
        rotator.turnSelected(to: 10)
        await rigApp.settle()
        #expect(rigApp.status == "Rotátor Short: směr je mimo rozsah, natočeno na mez 30°")
        #expect(fake.writes == ["P 30.0 0"])
    }

    /// The setup is saved; switching the network display on starts the receiver, a broadcast shows up, off clears it.
    @Test func theNetworkRotorsAreShown() async throws {
        let ports = ListenerPorts()
        let rigApp = try await RigApp.make(adjust: { environment in
            environment.hardware.listenRotorNetwork = { _, handler in
                let listener = try RotorNetworkListener(bindHost: "127.0.0.1", port: 0, handler: handler)
                ports.set(listener.boundPort)
                return listener
            }
        })
        let rotator: RotatorModel = rigApp.rig.rotator
        await rigApp.settle()
        #expect(ports.port == nil)
        var setup = RotorSetup()
        setup.networkEnabled = true
        rotator.saveSetup(setup)
        await rigApp.settle()
        let port: Int = try #require(ports.port)
        #expect(rigApp.model.config.config.rotor.networkEnabled)
        UdpProbeSender.send("Tribander @ 2250", port: port)
        await eventually("network rotor") { rotator.networkRotors["Tribander"] == 225 }
        #expect(rotator.networkStatus == nil)
        setup.networkEnabled = false
        rotator.saveSetup(setup)
        await rigApp.settle()
        #expect(rotator.networkRotors.isEmpty)
        await rotator.shutdown()
    }

    /// Off by default and inert hardware: the display says why nothing is received.
    @Test func theNetworkDisplayOnInertHardware() async throws {
        let rigApp = try await TestApp.make()
        let rotator: RotatorModel = rigApp.model.rig.rotator
        var setup = RotorSetup()
        setup.networkEnabled = true
        rotator.saveSetup(setup)
        await rotator.settle()
        await runMainQueue()
        #expect(rotator.networkStatus != nil)
    }

    /// The grid of a spot or of the typed station gives the bearing between the grids.
    @Test func theGridBearing() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.station.gridSquare = "JO70"
            config.rotorUdpHost = "127.0.0.1"
        }
        let expected: Int = try #require(RotorPlan.gridBearing(from: "JO70", to: "JN79"))
        rigApp.rig.typedCall = { "OK1KHL" }
        rigApp.rig.typedGrid = { "JN79" }
        #expect(rigApp.rig.azimuthTo("ok1khl") == expected)
        #expect(rigApp.rig.azimuthTo("OK2ABC", grid: "JN79") == expected)
        rigApp.rig.rotator.turnToStation("OK2ABC", grid: "JN79")
        #expect(rigApp.status == "Rotátor (UDP) → \(expected)°")
    }

    /// N1MM „Auto-select antenna based on azimuth": with the option on, Space in the call field chooses the band's
    /// antenna again by the bearing (a fixed bidirectional antenna also by its back end); off, only a band change does.
    @Test func theAntennaFollowsTheBearingWhenACallIsEntered() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.station.gridSquare = "JO70"
            config.antennas = [
                AntennaEntry(code: 1, name: "East", bands: "20m", sector: "60-120"),
                AntennaEntry(code: 2, name: "SouthFixed", bands: "20m", sector: "330-30", bidirectional: true),
            ]
        }
        rigApp.entry.setFrequency("14025")
        #expect(rigApp.rig.antenna.current?.name == "East")
        rigApp.rig.typedGrid = { "JN79" }
        rigApp.entry.callChanged("OK1KHL")
        rigApp.entry.jumpToExchange()
        #expect(rigApp.rig.antenna.current?.name == "East")
        rigApp.model.config.config.rotor.autoAntenna = true
        rigApp.entry.jumpToExchange()
        #expect(rigApp.rig.antenna.current?.name == "SouthFixed")
    }
}

/// The port a test listener bound (set on the rotator lane, read on the main actor).
private final class ListenerPorts: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int?

    var port: Int? {
        lock.withLock { value }
    }

    func set(_ port: Int) {
        lock.withLock { value = port }
    }
}

/// One datagram to a loopback port.
private enum UdpProbeSender {
    static func send(_ text: String, port: Int) {
        try? UdpSender.send(Array(text.utf8), host: "127.0.0.1", port: port)
    }
}
