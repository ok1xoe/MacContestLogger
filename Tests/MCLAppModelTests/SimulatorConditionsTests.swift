import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// QSB and QRM of the pileup simulator over the recording sink (never a device): off by default, and switching them on
/// changes the sound only — the callers, their speeds, amplitudes and delays stay the same.
@MainActor @Suite struct SimulatorConditionsTests {

    /// The plays of a fixed run: a CQ pressed until the stations answered twice.
    private static func run(qsb: Bool, qrm: Bool) async throws -> [RecordingSimAudio.Played] {
        let rig = try await SimulatorModelTests.make()
        #expect(!rig.simulator.qsb && !rig.simulator.qrm)
        rig.simulator.qsb = qsb
        rig.simulator.qrm = qrm
        await rig.start()
        let sink: RecordingSimAudio = try #require(rig.audio.sink)
        for _ in 0..<12 {
            rig.pressF1()
            rig.app.clock.advance(by: 20_000)
        }
        return sink.plays
    }

    @Test func conditionsChangeTheSoundNotTheCallers() async throws {
        let plain = try await Self.run(qsb: false, qrm: false)
        let faded = try await Self.run(qsb: true, qrm: false)
        // The same sends and replies, the same lengths and delays; the faded ones never louder.
        #expect(plain.count == faded.count)
        #expect(plain.map(\.samples) == faded.map(\.samples))
        #expect(plain.map(\.delayMs) == faded.map(\.delayMs))
        for (a, b) in zip(plain, faded) {
            #expect(b.peak <= a.peak + 1e-6)
        }
        #expect(zip(plain, faded).contains { $0.peak > $1.peak + 1e-3 }, "at least one reply faded")
    }

    @Test func qrmAddsAWeakStationPerAnswer() async throws {
        let plain = try await Self.run(qsb: false, qrm: false)
        let busy = try await Self.run(qsb: false, qrm: true)
        let extra: [RecordingSimAudio.Played] = busy.filter { $0.peak <= Float(SimConditions.qrmAmplitude) + 1e-6 }
        #expect(busy.count > plain.count)
        #expect(extra.count == busy.count - plain.count)
        #expect(extra.allSatisfy { $0.peak > 0.05 })
    }
}
