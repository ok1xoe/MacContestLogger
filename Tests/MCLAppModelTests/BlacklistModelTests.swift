import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The DX cluster blacklist (`AS:473-500, 1029-1073`): the start-up migration of the old string lists,
/// the CRUD of the window, the buffer applied after every change, and the save without `saveConfig`'s side effects.
@MainActor @Suite struct BlacklistModelTests {

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func spot(_ call: String, spotter: String = "OK1ABC") -> DxSpot {
        DxSpot(spotter: spotter, freqHz: 14_030_000, dxCall: call, comment: "")
    }

    @Test func theLegacyListsAreMigratedAtStart() async throws {
        let app = try await TestApp.make(fixedNow: Self.now) { config, _ in
            config.dxCluster.blacklistedCalls = ["oh2as", " DL5XX "]
            config.dxCluster.blacklistedSpotters = ["W1AW-#"]
            config.dxCluster.callBlacklist = [BlacklistEntry(value: "OH2AS", addedAtUtc: "2026-01-01T00:00:00Z",
                                                             note: "kept")]
        }
        let blacklist: BlacklistModel = app.model.blacklist
        #expect(blacklist.entries(isCall: true) == [
            BlacklistEntry(value: "OH2AS", addedAtUtc: "2026-01-01T00:00:00Z", note: "kept"),
            BlacklistEntry(value: "DL5XX", addedAtUtc: "", note: ""),
        ])
        #expect(blacklist.entries(isCall: false) == [BlacklistEntry(value: "W1AW-#", addedAtUtc: "", note: "")])
        let saved: AppConfig = await app.savedConfigFlushed()
        #expect(saved.dxCluster.blacklistedCalls.isEmpty)
        #expect(saved.dxCluster.blacklistedSpotters.isEmpty)
        #expect(saved.dxCluster.callBlacklist.count == 2)
        // Applied before the first spot.
        let buffer: SpotBuffer = app.model.dxCluster.spots
        buffer.add(Self.spot("DL5XX"))
        buffer.add(Self.spot("OK2ZZ", spotter: "W1AW-#"))
        buffer.add(Self.spot("OK2YY"))
        #expect(buffer.snapshot().map(\.dxCall) == ["OK2YY"])
    }

    @Test func crudSavesAndAppliesTheBuffer() async throws {
        let app = try await TestApp.make(fixedNow: Self.now)
        let blacklist: BlacklistModel = app.model.blacklist
        let buffer: SpotBuffer = app.model.dxCluster.spots
        buffer.add(Self.spot("OH2AS"))
        buffer.add(Self.spot("DL5XX", spotter: "W1AW-#"))
        blacklist.blacklistCall(" oh2as ")
        #expect(buffer.snapshot().map(\.dxCall) == ["DL5XX"])
        blacklist.blacklistSpotter("w1aw-#")
        #expect(buffer.snapshot().isEmpty)
        let stamp: String = JavaInstant(date: Self.now).toString()
        #expect(blacklist.entries(isCall: true) == [BlacklistEntry(value: "OH2AS", addedAtUtc: stamp, note: "")])

        blacklist.setNote(isCall: true, value: "OH2AS", note: "pirate")
        blacklist.updateValue(isCall: true, oldValue: "OH2AS", newValue: "OH2AA")
        #expect(blacklist.entries(isCall: true) == [BlacklistEntry(value: "OH2AA", addedAtUtc: stamp, note: "pirate")])
        buffer.add(Self.spot("OH2AS"))
        #expect(buffer.snapshot().map(\.dxCall) == ["OH2AS"])
        blacklist.remove(isCall: false, value: "W1AW-#")
        #expect(blacklist.entries(isCall: false).isEmpty)

        let saved: AppConfig = await app.savedConfigFlushed()
        #expect(saved.dxCluster.callBlacklist == [BlacklistEntry(value: "OH2AA", addedAtUtc: stamp, note: "pirate")])
        #expect(saved.dxCluster.spotterBlacklist.isEmpty)
    }

    @Test func applySetsTheSkimmerThreshold() async throws {
        let app = try await TestApp.make { config, _ in
            config.dxCluster.minSkimmers = 0
        }
        let buffer: SpotBuffer = app.model.dxCluster.spots
        buffer.add(DxSpot(spotter: "DL1ABC-#", freqHz: 14_025_000, dxCall: "OH2AS", comment: "CW 21 dB 25 WPM CQ"))
        #expect(buffer.snapshot().isEmpty)
        app.model.config.config.dxCluster.minSkimmers = 1
        app.model.blacklist.apply()
        #expect(buffer.snapshot().count == 1)
    }

    /// A blacklist change writes the file and the buffer — the footswitch is not reopened, the parallel plan
    /// does not run (Kotlin's `saveConfig` would do both).
    @Test func aChangeHasNoSaveConfigSideEffects() async throws {
        let server = try FakeTelnetServer()
        let rigApp = try await RigApp.make(configure: { config, _ in
            config.footswitchPort = "/dev/fake-fs"
            config.dxCluster.favorites = [server.favorite(name: "RBN", parallel: true)]
        }, adjust: { environment in
            environment.network = NetworkPorts(makeSession: NetworkPorts.sessions(), http: FakeHttpGetter(),
                                               urlOpener: RecordingUrlOpener().opener)
        })
        await rigApp.settle()
        let dx: DxClusterModel = rigApp.model.dxCluster
        await eventually("parallel connected") { dx.parallel.values.first?.connected == true }
        // A lost parallel connection: Kotlin's `saveConfig` would reopen it.
        server.dropAll()
        await eventually("lost") { dx.parallel.values.first?.connected == false }
        let opens: Int = rigApp.hardware.events.filter { $0.hasPrefix("footswitch open") }.count
        #expect(opens == 1)
        rigApp.model.blacklist.blacklistCall("OH2AS")
        await rigApp.model.config.flush()
        await rigApp.settle()
        #expect(rigApp.hardware.events.filter { $0.hasPrefix("footswitch open") }.count == opens)
        await dx.settle()
        #expect(server.connectionCount == 1)
        // The arm can fail: a re-plan does reopen it.
        dx.syncParallelClusters()
        await eventually("reopened by a plan") { server.connectionCount == 2 }
    }

    /// Kotlin quirk: removing a blank value drops the blank entries in memory but reports no change (no save).
    @Test func removingABlankValueIsNotSaved() async throws {
        let app = try await TestApp.make { config, _ in
            config.dxCluster.callBlacklist = [BlacklistEntry(value: "", addedAtUtc: "", note: "x"),
                                              BlacklistEntry(value: "OH2AS", addedAtUtc: "", note: "")]
        }
        app.model.blacklist.remove(isCall: true, value: "  ")
        #expect(app.model.blacklist.entries(isCall: true).map(\.value) == ["OH2AS"])
        let saved: AppConfig = await app.savedConfigFlushed()
        #expect(saved.dxCluster.callBlacklist.count == 2)
    }
}
