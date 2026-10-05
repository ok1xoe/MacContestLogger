import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Quit: the keyers first, then **both** rigs disconnect with `tr("ukončeno")`, then the footswitch,
/// OTRSP and the rotator.
@MainActor @Suite struct RigShutdownTests {

    @Test func shutdownDisconnectsBothRigsAndClosesThePeripherals() async throws {
        let fake1 = try FakeRigctld()
        let fake2 = try FakeRigctld(freqHz: 7_010_000)
        let rotctld = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2R"
            config.otrspPort = "/dev/fake-otrsp"
            config.footswitchPort = "/dev/fake-fs"
            config.rig = fakeRigConfig(fake1.port)
            config.rig2 = fakeRigConfig(fake2.port)
            config.rotatorHost = "127.0.0.1"
            config.rotatorPort = rotctld.port
        }
        let rig: MCLAppModel.RigModel = rigApp.rig
        await rigApp.settle()
        await rigApp.connect(vfo: 0)
        rig.toggle(vfo: 1)
        await eventually("rig 2") { rig.cat2.state != nil }
        await eventually("rotator") { rig.rotator.azimuth != nil }
        let steps = StepLog()
        let cat: @MainActor () async -> Void = rigApp.model.shutdownServices.cat
        rigApp.model.shutdownServices.keyers = { steps.add("keyers") }
        rigApp.model.shutdownServices.cat = {
            steps.add("cat")
            await cat()
        }
        await rigApp.model.shutdown()
        await runMainQueue()
        #expect(steps.names == ["keyers", "cat"])
        #expect(!rig.cat1.connected && !rig.cat2.connected)
        #expect(rig.cat1.statusMessage == "ukončeno")
        #expect(rig.cat2.statusMessage == "ukončeno")
        #expect(Array(rigApp.hardware.events.suffix(2)) == ["footswitch close", "otrsp close"])
        #expect(rigApp.rotatorClock.pendingCount == 0)
        #expect(!rigApp.model.peripherals.otrspOpen)
        await eventually("connections closed") {
            fake1.openConnections == 0 && fake2.openConnections == 0 && rotctld.openConnections == 0
        }
    }

    /// A launched daemon whose connect is still running (held at the connector).
    static func connecting() async throws -> (RigApp, FakeRigctld) {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port, mode: .launchDaemon)
        }
        try rigApp.hardware.useSleeperDaemon()
        rigApp.hardware.holdConnects()
        rigApp.rig.toggle(vfo: 0)
        await eventually("connect held") { rigApp.hardware.connectAttempts == 1 }
        #expect(rigApp.hardware.processManagers.first?.isAlive == true)
        return (rigApp, fake)
    }

    /// Nothing of a cancelled connect survives: no daemon, no rig, no poller (the fake never saw a poll).
    static func expectNothingLeft(_ rigApp: RigApp, _ fake: FakeRigctld) async {
        #expect(!rigApp.rig.cat1.connected)
        #expect(rigApp.hardware.daemonStarts == 1)
        #expect(rigApp.hardware.processManagers.allSatisfy { !$0.isAlive })
        await eventually("no connection left") { fake.openConnections == 0 }
        #expect(!fake.commands.contains("f"))
    }

    /// Quit during „Připojuji…": the connect is cancelled and awaited; its daemon is stopped.
    @Test func quitCancelsAConnectInFlight() async throws {
        let (rigApp, fake) = try await Self.connecting()
        let model: AppModel = rigApp.model
        let quit = Task { await model.shutdown() }
        await eventually("disconnected") { rigApp.rig.cat1.statusMessage == "ukončeno" }
        rigApp.hardware.releaseConnects()
        await quit.value
        await runMainQueue()
        #expect(rigApp.rig.cat1.statusMessage == "ukončeno")
        await Self.expectNothingLeft(rigApp, fake)
    }

    /// The scan's disconnect during „Připojuji…": the same, before the scan opens the serial port.
    @Test func scanDisconnectCancelsAConnectInFlight() async throws {
        let (rigApp, fake) = try await Self.connecting()
        let rig: MCLAppModel.RigModel = rigApp.rig
        let scan = Task { await rig.disconnectForScan(reason: "scan") }
        await eventually("disconnected") { rig.cat1.statusMessage == "scan" }
        rigApp.hardware.releaseConnects()
        await scan.value
        await runMainQueue()
        #expect(rig.cat1.statusMessage == "scan")
        await Self.expectNothingLeft(rigApp, fake)
    }

    /// The LED pressed again during „Připojuji…": the connect is cancelled (one daemon, stopped); the next press
    /// connects normally.
    @Test func secondToggleCancelsTheConnect() async throws {
        let (rigApp, fake) = try await Self.connecting()
        let rig: MCLAppModel.RigModel = rigApp.rig
        rig.toggle(vfo: 0)
        await eventually("disconnected") { rig.cat1.statusMessage == nil }
        rigApp.hardware.releaseConnects()
        await rig.settle()
        await runMainQueue()
        await Self.expectNothingLeft(rigApp, fake)
        rig.toggle(vfo: 0)
        await eventually("connected") { rig.cat1.state != nil }
        #expect(rigApp.hardware.daemonStarts == 2)
        #expect(rigApp.hardware.processManagers.filter { $0.isAlive }.count == 1)
        rig.toggle(vfo: 0)
        await rig.settle()
        #expect(rigApp.hardware.processManagers.allSatisfy { !$0.isAlive })
    }

    /// Quit with the footswitch PTT held: `T 0` reaches the keyed rig before it disconnects.
    @Test func quitReleasesAHeldPtt() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "PTT"
            config.rig = fakeRigConfig(fake.port)
        }
        await rigApp.settle()
        await rigApp.connect()
        rigApp.hardware.press(true)
        await eventually("PTT on") { fake.writes == ["T 1"] }
        await rigApp.model.shutdown()
        #expect(fake.writes == ["T 1", "T 0"])
        #expect(rigApp.hardware.events.last == "footswitch close")
    }

    /// A footswitch press after the transmit-release milestone (the rigs are still connected) keys nothing; the
    /// footswitch is still open then, so the press does reach the rig model.
    @Test func aPressAfterTheTransmitReleaseKeysNothing() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "PTT"
            config.rig = fakeRigConfig(fake.port)
        }
        await rigApp.settle()
        await rigApp.connect()
        let hardware: FakeHardware = rigApp.hardware
        let rig: MCLAppModel.RigModel = rigApp.rig
        var pressedOpen = false
        var milestones = 0
        rigApp.model.onQuitMilestone = {
            milestones += 1
            guard milestones == 1 else { return }
            pressedOpen = hardware.footswitchOpen && rig.cat1.connected
            hardware.press(true)
        }
        await rigApp.model.shutdown()
        await runMainQueue()
        #expect(pressedOpen)
        #expect(!fake.writes.contains("T 1"))
        #expect(rigApp.hardware.events.last == "footswitch close")
    }

    /// Control for the test above (the fake rig only): with a quit whose transmit release never closes the rig's
    /// transmitter, the same press at the milestone does key the rig — the check above can fail.
    @Test func thePressAtTheMilestoneKeysWithoutTheTransmitClose() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "PTT"
            config.rig = fakeRigConfig(fake.port)
        }
        await rigApp.settle()
        await rigApp.connect()
        let hardware: FakeHardware = rigApp.hardware
        rigApp.model.shutdownServices.releaseTransmit = {}
        var milestones = 0
        rigApp.model.onQuitMilestone = {
            milestones += 1
            if milestones == 1 {
                hardware.press(true)
            }
        }
        await rigApp.model.shutdown()
        await runMainQueue()
        #expect(fake.writes.contains("T 1"))
    }
}

/// SIGTERM/SIGINT/SIGHUP (transmit-release milestone): the signal is injected into
/// `TerminationSignals.handle` — no signal is raised on the test process. The first one runs the regular quit; a
/// further one exits only after the quit released the transmitter (deferred until then), a third one or the deadline
/// exits anyway.
@MainActor @Suite struct TerminationSignalsTests {

    @Test func theGateQuitsDefersAndExits() {
        var gate = TerminationSignalGate()
        #expect(gate.receive(SIGTERM, isTerminating: false, exitAllowed: false) == .terminate)
        #expect(gate.receive(SIGTERM, isTerminating: true, exitAllowed: false) == .deferred(startDeadline: true))
        #expect(gate.pendingCode == 143)
        #expect(gate.milestone(exitAllowed: false) == .none)
        #expect(gate.milestone(exitAllowed: true) == .forceExit(code: 143))
        #expect(gate.receive(SIGTERM, isTerminating: true, exitAllowed: true) == .none) // once only
        #expect(gate.deadlineExpired() == .none)

        // After the milestone a further signal exits at once.
        var released = TerminationSignalGate()
        #expect(released.receive(SIGINT, isTerminating: false, exitAllowed: true) == .terminate)
        #expect(released.receive(SIGINT, isTerminating: true, exitAllowed: true) == .forceExit(code: 130))

        // A signal during a ⌘Q quit is deferred like a second one; the third forces the exit.
        var during = TerminationSignalGate()
        #expect(during.receive(SIGHUP, isTerminating: true, exitAllowed: false) == .deferred(startDeadline: true))
        #expect(during.receive(SIGTERM, isTerminating: true, exitAllowed: false) == .deferred(startDeadline: false))
        #expect(during.receive(SIGINT, isTerminating: true, exitAllowed: false) == .forceExit(code: 130))

        // The deadline exits with the pending code.
        var wedged = TerminationSignalGate()
        _ = wedged.receive(SIGTERM, isTerminating: false, exitAllowed: false)
        _ = wedged.receive(SIGHUP, isTerminating: true, exitAllowed: false)
        #expect(wedged.deadlineExpired() == .forceExit(code: 129))
        #expect(wedged.milestone(exitAllowed: true) == .none)
        #expect(TerminationSignals.signals == [SIGTERM, SIGINT, SIGHUP])
    }

    /// A `kill` with the footswitch PTT held, and a second `kill` right after it: the second one is deferred until
    /// the quit's transmit release, so `T 0` reaches the keyed rig before the exit; the exit runs once.
    @Test func aSecondSignalWaitsForTheTransmitRelease() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "PTT"
            config.rig = fakeRigConfig(fake.port)
        }
        await rigApp.settle()
        await rigApp.connect()
        rigApp.hardware.press(true)
        await eventually("PTT on") { fake.writes == ["T 1"] }
        let model: AppModel = rigApp.model
        let probe = SignalProbe()
        let signals = TerminationSignals(actions: TerminationSignals.Actions(
            terminate: {
                probe.terminating = true
                probe.quit = Task { await model.shutdown() }
            },
            isTerminating: { probe.terminating },
            exitAllowed: { model.signalExitAllowed },
            transmitReleased: { model.transmitReleased },
            forceExit: { code in
                probe.exits.append(code)
                probe.writesAtExit = fake.writes
                probe.connectedAtExit = rigApp.rig.cat1.connected
            },
            after: { _, body in probe.deadlines.append(body) }))
        model.onQuitMilestone = { signals.milestoneReached() }
        signals.handle(SIGTERM)
        let shutdown: Task<Void, Never> = try #require(probe.quit)
        signals.handle(SIGTERM)
        #expect(probe.exits.isEmpty) // deferred: the transmitter is not released yet
        #expect(probe.deadlines.count == 2) // the first signal's release deadline and the deferral's
        await eventually("exit") { !probe.exits.isEmpty }
        #expect(probe.exits == [143])
        #expect(probe.writesAtExit == ["T 1", "T 0"])
        #expect(probe.connectedAtExit == true) // the release went over the still-connected rig
        #expect(model.transmitReleased)
        // The real exit would end the process here; the fake lets the quit finish: no second exit.
        await shutdown.value
        probe.deadlines.forEach { $0() }
        #expect(probe.exits == [143])
        #expect(fake.writes == ["T 1", "T 0"])
    }

    /// A quit whose transmit release never finishes (a wedged lane): the deferred exit runs at the deadline.
    @Test func theDeadlineEndsAWedgedQuit() {
        let probe = SignalProbe()
        let signals = TerminationSignals(actions: TerminationSignals.Actions(
            terminate: { probe.terminating = true },
            isTerminating: { probe.terminating },
            exitAllowed: { false },
            transmitReleased: { false },
            forceExit: { probe.exits.append($0) },
            after: { seconds, body in
                probe.deadlineSeconds.append(seconds)
                probe.deadlines.append(body)
            }))
        signals.handle(SIGINT)
        signals.handle(SIGTERM)
        signals.milestoneReached()
        #expect(probe.exits.isEmpty)
        #expect(probe.deadlineSeconds == [TerminationSignals.releaseDeadline, TerminationSignals.deadline])
        probe.deadlines[1]()
        #expect(probe.exits == [143])
        probe.deadlines[0]()
        #expect(probe.exits == [143]) // once only
    }

    /// One signal (launchd, a logout) and a quit wedged before the transmit release: the release deadline ends the
    /// process through the forced exit (hooks, frame cleanup); a quit that released the transmitter is left alone.
    @Test func theReleaseDeadlineEndsASingleSignalWedgedQuit() {
        let probe = SignalProbe()
        let released = false
        let signals = TerminationSignals(actions: TerminationSignals.Actions(
            terminate: { probe.terminating = true },
            isTerminating: { probe.terminating },
            exitAllowed: { released },
            transmitReleased: { released },
            forceExit: { probe.exits.append($0) },
            after: { seconds, body in
                probe.deadlineSeconds.append(seconds)
                probe.deadlines.append(body)
            }))
        signals.handle(SIGHUP)
        #expect(probe.terminating)
        #expect(probe.deadlineSeconds == [TerminationSignals.releaseDeadline])
        probe.deadlines.forEach { $0() }
        #expect(probe.exits == [128 + SIGHUP])

        let releasedProbe = SignalProbe()
        let quiet = TerminationSignals(actions: TerminationSignals.Actions(
            terminate: { releasedProbe.terminating = true },
            isTerminating: { releasedProbe.terminating },
            exitAllowed: { true },
            transmitReleased: { true },
            forceExit: { releasedProbe.exits.append($0) },
            after: { _, body in releasedProbe.deadlines.append(body) }))
        quiet.handle(SIGTERM)
        releasedProbe.deadlines.forEach { $0() }
        #expect(releasedProbe.exits.isEmpty) // the quit goes on (the forced backup, the config) undisturbed
    }

    /// The gate's release deadline: only after a first signal, only while the transmitter is held, once.
    @Test func theGateReleaseDeadline() {
        var idle = TerminationSignalGate()
        #expect(idle.releaseDeadlineExpired(transmitReleased: false) == .none)
        var gate = TerminationSignalGate()
        #expect(gate.receive(SIGTERM, isTerminating: false, exitAllowed: false) == .terminate)
        #expect(gate.firstCode == 143)
        #expect(gate.releaseDeadlineExpired(transmitReleased: true) == .none)
        #expect(gate.releaseDeadlineExpired(transmitReleased: false) == .forceExit(code: 143))
        #expect(gate.releaseDeadlineExpired(transmitReleased: false) == .none)
        // A ⌘Q quit (no first signal of ours) has no release deadline.
        var quit = TerminationSignalGate()
        #expect(quit.receive(SIGINT, isTerminating: true, exitAllowed: false) == .deferred(startDeadline: true))
        #expect(quit.firstCode == nil)
    }
}

/// What the injected signal actions did.
@MainActor
final class SignalProbe {
    var terminating = false
    var quit: Task<Void, Never>?
    var exits: [Int32] = []
    var writesAtExit: [String] = []
    var connectedAtExit: Bool?
    var deadlines: [@MainActor () -> Void] = []
    var deadlineSeconds: [Double] = []
}

/// The order of the quit steps.
@MainActor
final class StepLog {
    private(set) var names: [String] = []

    func add(_ name: String) {
        names.append(name)
    }
}
