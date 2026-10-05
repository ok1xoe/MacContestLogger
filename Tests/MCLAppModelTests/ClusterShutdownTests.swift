import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The quit closes the main **and** every parallel DX cluster connection (Kotlin closes only the main
/// one), waits for their threads, drops the queued callbook work and removes the listeners.
@MainActor @Suite struct ClusterShutdownTests {

    @Test func theQuitClosesEveryConnection() async throws {
        let spot = try await SpotApp.make { config, server in
            config.dxCluster.favorites = [server.favorite(name: "RBN", parallel: true)]
        }
        await eventually("parallel connected") { spot.dx.parallel.values.first?.connected == true }
        let main = try FakeTelnetServer()
        await spot.connectMain(main.favorite(name: "Main"))
        await eventually("both open") { spot.server.openConnections == 1 && main.openConnections == 1 }

        await spot.model.shutdown()
        await eventually("main closed") { main.openConnections == 0 }
        await eventually("parallel closed") { spot.server.openConnections == 0 }
        #expect(!spot.dx.connected)
        #expect(spot.dx.statusText == "ukončeno")
        let parallelState: DxClusterSession.Snapshot = try #require(spot.dx.parallel.values.first)
        #expect(!parallelState.connected)

        // Listeners gone: neither the feed nor the console moves any more.
        let revision: Int = spot.model.spotFeed.revision
        let logRevision: Int = spot.dx.logRevision
        spot.dx.spots.add(DxSpot(spotter: "OK1ABC", freqHz: 14_030_000, dxCall: "OH2AS", comment: ""))
        try? spot.dx.log.info("after the quit")
        await runMainQueue()
        #expect(spot.model.spotFeed.revision == revision)
        #expect(spot.dx.logRevision == logRevision)
    }

    /// After the quit's cluster part the window's actions and the parallel plan open and send nothing.
    @Test func actionsAfterTheQuitDoNothing() async throws {
        let spot = try await SpotApp.make()
        await spot.model.shutdown()
        let fav: DxClusterFavorite = spot.server.favorite(name: "Fake", login: "OK1XXX")
        spot.dx.connect(fav)
        spot.dx.toggle(fav)
        spot.dx.login(fav)
        spot.dx.send("SH/DX")
        spot.dx.logout()
        spot.model.config.config.dxCluster.favorites = [spot.server.favorite(name: "RBN", parallel: true)]
        spot.dx.syncParallelClusters()
        await spot.dx.settle()
        await spot.dx.drain()
        #expect(spot.server.connectionCount == 0)
        #expect(spot.dx.parallelKeys.isEmpty)
        #expect(!spot.dx.mainLane.session.snapshot.connected && !spot.dx.mainLane.session.snapshot.connecting)
    }

    /// A parallel connection waiting for its auto-login when the quit starts never logs in; the database closes
    /// (the second quit milestone) while that session thread is still held.
    @Test func noLoginReachesTheNodeDuringTheQuit() async throws {
        let sleeper = TestSleeper()
        sleeper.hold()
        let spot = try await SpotApp.make(configure: { config, server in
            config.dxCluster.favorites = [server.favorite(name: "RBN", login: "OK1XXX", password: "secret",
                                                          parallel: true)]
        }, adjust: { environment in
            environment.network.makeSession = NetworkPorts.sessions(sleep: sleeper.sleep)
        })
        await eventually("auto-login wait") { sleeper.requests == [1_500] }
        var milestones = 0
        spot.model.onQuitMilestone = { milestones += 1 }
        let quit = Task { await spot.model.shutdown() }
        await eventually("database closed") { milestones == 2 }
        sleeper.release()
        await quit.value
        await eventually("closed") { spot.server.openConnections == 0 }
        #expect(spot.server.lines(0).isEmpty)
    }

    /// A connect that hangs (DNS, the 8 s timeout) does not hold up the database close: only the drain after it
    /// waits for the session.
    @Test func aHangingConnectDoesNotHoldTheDatabaseClose() async throws {
        let hanging = HangingSession()
        let spot = try await SpotApp.make(adjust: { environment in
            environment.network.makeSession = { _ in hanging }
        })
        spot.dx.connect(DxClusterFavorite(name: "Never", host: FakeTelnetServer.host, port: 9, login: "", password: ""))
        await eventually("connect in flight") { hanging.connects == 1 }
        var milestones = 0
        spot.model.onQuitMilestone = { milestones += 1 }
        let quit = Task { await spot.model.shutdown() }
        await eventually("database closed") { milestones == 2 }
        #expect(hanging.disconnects == ["ukončeno"])
        hanging.finish()
        await quit.value
    }

    /// The cluster drain is the quit's last step: while a connect still hangs, the pending window geometry and the
    /// config are already written (a second signal ending the quit there loses nothing).
    @Test func aHangingConnectDoesNotDelayTheConfigFlush() async throws {
        let hanging = HangingSession()
        let spot = try await SpotApp.make(adjust: { environment in
            environment.network.makeSession = { _ in hanging }
        })
        spot.dx.connect(DxClusterFavorite(name: "Never", host: FakeTelnetServer.host, port: 9, login: "", password: ""))
        await eventually("connect in flight") { hanging.connects == 1 }
        spot.model.geometry.windowChanged(id: "bandmap", frame: CGRect(x: 100, y: 200, width: 460, height: 640),
                                          persistSize: true, mainScreenHeight: 1_000)
        spot.model.config.config.station.call = "OK9QQQ"
        let quit = Task { await spot.model.shutdown() }
        await eventually("drain waits for the connect") { hanging.idleCalls >= 1 }
        let saved: AppConfig = await spot.app.savedConfigFlushed()
        #expect(saved.windowGeometry["bandmap"] != nil)
        #expect(saved.station.call == "OK9QQQ")
        hanging.finish()
        await quit.value
    }

    @Test func theCallbookLaneIsClosed() async throws {
        let spot = try await SpotApp.make { config, _ in CallbookModelTests.credentials(&config, qrz: false) }
        spot.http.hamQth(call: "OK1ABC", grid: "JO70")
        await spot.model.callbook.shutdown()
        spot.model.callbook.lookup("OK1ABC", typedCall: { "OK1ABC" })
        await spot.model.callbook.lane.settle()
        #expect(spot.http.urls.isEmpty)
    }
}

/// A session whose connect never ends until the test says so (a stand-in for a DNS or connect-timeout hang; it opens
/// no socket).
final class HangingSession: ClusterSessionPort, @unchecked Sendable {
    private let lock = NSLock()
    private var connectCount = 0
    private var disconnectMessages: [String] = []
    private var finished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private var idleCount = 0

    var connects: Int { lock.withLock { connectCount } }
    var idleCalls: Int { lock.withLock { idleCount } }
    var disconnects: [String] { lock.withLock { disconnectMessages } }

    var snapshot: DxClusterSession.Snapshot {
        var state = DxClusterSession.Snapshot()
        state.connecting = lock.withLock { connectCount > 0 && !finished }
        return state
    }

    var myCall: String = ""
    var onSelfSpot: (@Sendable (SelfSpot) -> Void)?
    var onSpot: (@Sendable (DxSpot) throws -> Void)?

    func toggle(_ fav: DxClusterFavorite) throws {
        try connect(fav, autoLogin: false)
    }

    func connect(_ fav: DxClusterFavorite, autoLogin: Bool) throws {
        lock.withLock { connectCount += 1 }
    }

    func login(_ fav: DxClusterFavorite) {}
    func logout() throws {}
    func send(_ command: String) throws {}

    func disconnect(_ message: String) throws {
        lock.withLock { disconnectMessages.append(message) }
    }

    func idle() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let done: Bool = lock.withLock {
                idleCount += 1
                if finished || connectCount == 0 { return true }
                waiters.append(continuation)
                return false
            }
            if done { continuation.resume() }
        }
    }

    func finish() {
        let pending: [CheckedContinuation<Void, Never>] = lock.withLock {
            finished = true
            let list = waiters
            waiters = []
            return list
        }
        for waiter in pending { waiter.resume() }
    }
}
