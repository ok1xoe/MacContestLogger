import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The rotator (`AS:667-763`): the 2 s poll over a fake `rotctld`, turning and stopping, the N1MM UDP
/// message, errors and `dropRotator`.
@MainActor @Suite struct RotatorModelTests {

    static func app(rotctld port: Int?, udp: Bool = false) async throws -> RigApp {
        try await RigApp.make { config, _ in
            if let port {
                config.rotatorHost = "127.0.0.1"
                config.rotatorPort = port
            }
            if udp {
                config.rotorUdpHost = "127.0.0.1"
                config.rotorUdpPort = 12_040
                config.rotorUdpName = "Beam & Co"
            }
        }
    }

    /// Without a host the poll says so and opens nothing; the default text before the first poll.
    @Test func withoutAHostNothingIsOpened() async throws {
        let rigApp = try await Self.app(rotctld: nil)
        let rotator: RotatorModel = rigApp.rig.rotator
        await rigApp.settle()
        #expect(rotator.azimuth == nil)
        #expect(rotator.statusText == .tr("Rotátor nenastaven (Nastavení → Antennas)"))
        #expect(rigApp.rotatorClock.pendingCount == 1)
        rigApp.entry.runShortcut(.rotorTurn)
        #expect(rigApp.status == "Rotátor: azimut k „“ neznám (chybí lokátor stanice nebo země)")
        rotator.turnTo(10)
        await rigApp.settle()
        #expect(rigApp.status == "Rotátor: rotátor není nastavený nebo dostupný")
        rotator.stop()
        await rigApp.settle()
        #expect(rigApp.status == "Rotátor zastaven")
        #expect(rigApp.hardware.events.isEmpty)
    }

    /// rotctld: the position every 2 s, `P az 0` and `S`, the texts with whole degrees.
    @Test func rotctldPollsTurnsAndStops() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await Self.app(rotctld: fake.port)
        let rotator: RotatorModel = rigApp.rig.rotator
        await eventually("first poll") { rotator.azimuth != nil }
        #expect(rotator.azimuth == 123.0)
        #expect(rotator.statusText == .tr("Rotátor %s:%s", .string("127.0.0.1"), .int(fake.port)))
        fake.setAzimuth("200.5")
        rigApp.rotatorClock.advance(by: RotatorModel.pollMs)
        await eventually("second poll") { rotator.azimuth == 200.5 }
        rotator.turnTo(-30)
        await rigApp.settle()
        #expect(rigApp.status == "Rotátor → 330°")
        rigApp.entry.runShortcut(.rotorStop)
        await rigApp.settle()
        #expect(rigApp.status == "Rotátor zastaven")
        #expect(fake.writes == ["P 330.0 0", "S"])
        #expect(fake.connectionCount == 1)
    }

    /// A refused turn drops the client (Kotlin `dropRotator`); the next call connects again. A refused stop keeps it.
    @Test func aFailedTurnDropsTheClient() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await Self.app(rotctld: fake.port)
        let rotator: RotatorModel = rigApp.rig.rotator
        await eventually("first poll") { rotator.azimuth != nil }
        fake.reject("P")
        rotator.turnTo(45)
        await rigApp.settle()
        #expect(rigApp.status == "Rotátor: rotctld odmítl natočení: RPRT -1")
        fake.reject("S")
        rotator.stop()
        await rigApp.settle()
        #expect(rigApp.status == "Rotátor: rotctld odmítl zastavení: RPRT -1")
        #expect(fake.connectionCount == 2)
        rotator.stop()
        await rigApp.settle()
        #expect(fake.connectionCount == 2)
    }

    /// An unreachable rotctld: the poll says „nedostupný", a turn reports that there is no client.
    @Test func anUnreachableRotator() async throws {
        let fake = try FakeRigctld()
        let port: Int = fake.port
        fake.stop()
        let rigApp = try await Self.app(rotctld: port)
        let rotator: RotatorModel = rigApp.rig.rotator
        await rigApp.settle()
        #expect(rotator.azimuth == nil)
        #expect(rotator.statusText == .tr("Rotátor nedostupný (%s:%s)", .string("127.0.0.1"), .int(port)))
        rotator.turnTo(90)
        await rigApp.settle()
        #expect(rigApp.status == "Rotátor: rotátor není nastavený nebo dostupný")
    }

    /// UDP only (no rotctld): the N1MM message with the tuned band, the UDP texts.
    @Test func udpOnly() async throws {
        let rigApp = try await Self.app(rotctld: nil, udp: true)
        let rotator: RotatorModel = rigApp.rig.rotator
        rigApp.entry.setFrequency("14025")
        rotator.turnTo(90)
        #expect(rigApp.status == "Rotátor (UDP) → 90°")
        rotator.stop()
        #expect(rigApp.status == "Rotátor (UDP) zastaven")
        await rigApp.settle()
        #expect(rigApp.hardware.events == [
            "udp 127.0.0.1:12040 <N1MMRotor><rotor>Beam &amp; Co</rotor><goazi>90.0</goazi><offset>0</offset>"
                + "<bidirectional>0</bidirectional><freqband>14</freqband></N1MMRotor>",
            "udp 127.0.0.1:12040 <N1MMRotor><stop>Beam &amp; Co</stop></N1MMRotor>",
        ])
    }

    /// Both configured: the UDP message first, then rotctld.
    @Test func udpThenRotctld() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.rotatorHost = "127.0.0.1"
            config.rotatorPort = fake.port
            config.rotorUdpHost = "127.0.0.1"
        }
        await eventually("first poll") { rigApp.rig.rotator.azimuth != nil }
        rigApp.rig.rotator.turnTo(10)
        await rigApp.settle()
        #expect(rigApp.status == "Rotátor → 10°")
        #expect(rigApp.hardware.events.count == 1)
        #expect(fake.writes == ["P 10.0 0"])
    }

    /// Quit: the poll stops and the client closes.
    @Test func shutdownStopsThePoll() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await Self.app(rotctld: fake.port)
        let rotator: RotatorModel = rigApp.rig.rotator
        await eventually("first poll") { rotator.azimuth != nil }
        #expect(rigApp.rotatorClock.pendingCount == 1)
        await rotator.shutdown()
        #expect(rigApp.rotatorClock.pendingCount == 0)
        rigApp.rotatorClock.advance(by: RotatorModel.pollMs)
        await rigApp.settle()
        #expect(fake.commands.filter { $0 == "p" }.count == 1)
    }
}
