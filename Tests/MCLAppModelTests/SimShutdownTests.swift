import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The end of the simulator (a regression pin): the sound output is closed on the model's lane at the
/// quit — Kotlin leaves the player open — and never on the main thread; after the quit nothing starts again.
@MainActor @Suite struct SimShutdownTests {

    @Test func theQuitStopsTheSimulationAndClosesTheOutputOffTheMainThread() async throws {
        let rig = try await SimulatorModelTests.make()
        await rig.start()
        let sink: RecordingSimAudio = try #require(rig.audio.sink)
        #expect(sink.closes == 0)
        await rig.app.model.shutdown()
        #expect(!rig.simulator.isOn)
        #expect(sink.closes == 1)
        #expect(sink.closedOnMain == [false])
    }

    @Test func shutdownOfTheModelAloneIsIdempotentAndBlocksALaterStart() async throws {
        let rig = try await SimulatorModelTests.make()
        await rig.start()
        let sink: RecordingSimAudio = try #require(rig.audio.sink)
        await rig.simulator.shutdown()
        await rig.simulator.shutdown()
        #expect(sink.closes == 1)
        rig.simulator.start(settings: SimulatorModelTests.settings, noise: 0.1)
        await rig.simulator.settle()
        #expect(!rig.simulator.isOn)
        #expect(!rig.simulator.isStarting)
        #expect(rig.audio.sinks.count == 1)
    }

    /// The output that opens only after the quit began is closed at once and no session exists.
    @Test func anOutputThatOpensAfterTheQuitIsClosed() async throws {
        let rig = try await SimulatorModelTests.make()
        rig.audio.holdOpen()
        rig.simulator.start(settings: SimulatorModelTests.settings, noise: 0.15)
        let quit = Task { @MainActor in
            await rig.simulator.shutdown()
        }
        await eventually("quit began") { rig.simulator.keyingRefusal == nil }
        rig.audio.releaseOpen()
        await quit.value
        #expect(!rig.simulator.isOn)
        #expect(rig.audio.sink?.closes == 1)
        #expect(rig.audio.sink?.closedOnMain == [false])
    }
}
