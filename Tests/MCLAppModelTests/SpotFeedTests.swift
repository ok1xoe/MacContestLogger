import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The one spot subscription: buffer changes coalesce into one main-actor hop, observers run after it,
/// a 15 s tick raises the revision, and `stop` removes the listener.
@MainActor @Suite struct SpotFeedTests {

    static func spot(_ call: String, _ hz: Int = 14_030_000) -> DxSpot {
        DxSpot(spotter: "OK1ABC", freqHz: hz, dxCall: call, comment: "")
    }

    @Test func changesCoalesceIntoOneRevision() async {
        let clock = ManualClock()
        let buffer = SpotBuffer(maxAgeMinutes: 90, clock: { Date() })
        let feed = SpotFeed(buffer: buffer, clock: clock)
        feed.start()
        var observed = 0
        feed.addObserver { observed += 1 }
        for index in 0..<5 {
            buffer.add(Self.spot("OH\(index)AS"))
        }
        #expect(feed.revision == 0)
        await runMainQueue()
        #expect(feed.revision == 1)
        #expect(observed == 1)
        #expect(feed.snapshot().count == 5)
        buffer.remove("OH0AS")
        await runMainQueue()
        #expect(feed.revision == 2)
        #expect(observed == 2)
    }

    @Test func theTickRaisesTheRevisionOnly() async {
        let clock = ManualClock()
        let buffer = SpotBuffer(maxAgeMinutes: 90, clock: { Date() })
        let feed = SpotFeed(buffer: buffer, clock: clock)
        feed.start()
        var observed = 0
        feed.addObserver { observed += 1 }
        clock.advance(by: 14_999)
        #expect(feed.revision == 0)
        clock.advance(by: 1)
        #expect(feed.revision == 1)
        clock.advance(by: 15_000)
        #expect(feed.revision == 2)
        #expect(observed == 0)
    }

    @Test func stopRemovesTheListenerAndTheTick() async {
        let clock = ManualClock()
        let buffer = SpotBuffer(maxAgeMinutes: 90, clock: { Date() })
        let feed = SpotFeed(buffer: buffer, clock: clock)
        feed.start()
        let id: SpotFeed.ObserverID = feed.addObserver {}
        feed.removeObserver(id)
        feed.stop()
        buffer.add(Self.spot("OH2AS"))
        await runMainQueue()
        clock.advance(by: 15_000)
        #expect(feed.revision == 0)
        #expect(clock.pendingCount == 0)
    }

    /// The app's feed runs the callbook prefetch after a batch (and only one prefetch per batch).
    @Test func theAppFeedIsStartedAtBootstrap() async throws {
        let spot = try await SpotApp.make()
        spot.dx.spots.add(Self.spot("OH2AS"))
        spot.dx.spots.add(Self.spot("DL5XX", 7_010_000))
        await runMainQueue()
        #expect(spot.model.spotFeed.revision == 1)
        spot.spotClock.advance(by: SpotFeed.tickMilliseconds)
        #expect(spot.model.spotFeed.revision == 2)
    }
}
