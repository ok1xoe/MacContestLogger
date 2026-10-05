import Foundation
import Testing
@testable import MCLCore

/// Java parity: logic arm against Java v1.1.1: the pure logic of the network and external data
/// (`dxcluster/`, `wsjtx/`, `broadcast/`, `n1mmrecv/`, `scoreboard/`, `hamqth/`, `clublog/`, `solar/`, `map/`,
/// `propagation/`, `adifudp/`, `sync/`, `cluster/` and the MQTT codec) over hand-made corpora and seeded fuzzers.
/// The reference `Fixtures/net-logic-java.json.gz` from a maintainer-only probe (instructions kept with the probe).
///
/// Input rows are taken from the reference, outputs are computed by Swift (`*ParitySections`); inputs lying in the repo
/// (`dxcc-test.json`, `contest-data/`) are fingerprinted by Swift itself. A change of input = "REGENERATE REFERENCE", a different output
/// = "MISMATCH". The match is exact (texts, bytes, bits), only the continuous `geo.*` fields with the tolerance of `GeoParitySections`
/// (1e-11 relative; degenerate routes are a deliberate divergence from Java v1.1.1). The suite prints nothing; each item
/// runs on its own thread (not in the shared pool), concurrently at most as many as there are cores.
@Suite struct JavaNetParityTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    static let names: [String] = {
        var all: [String] = DxClusterParitySections.names
        all += WsjtxParitySections.names
        all += BroadcastParitySections.names
        all += CallbookParitySections.names
        all += GeoParitySections.names
        all += SyncParitySections.names
        return all
    }()

    /// Rows per item in the Java reference — against a broken generator (empty fuzzer, missing corpus),
    /// where inputs taken from the reference would still match.
    static let pinnedDxCluster: [String: Int] = [
        "dxcluster.DSP": 2506, "dxcluster.WWV": 4062, "dxcluster.SELF": 3000, "dxcluster.SMP": 4094,
        "dxcluster.SKIM": 3000, "dxcluster.GRID": 3000, "dxcluster.URLENC": 1262, "dxcluster.PLAN": 2400,
        "dxcluster.LAYOUT": 750, "dxcluster.COLOR": 36, "dxcluster.BLK": 6328, "dxcluster.BEACON": 3130,
        "dxcluster.DIGI": 327, "dxcluster.BUF": 9325,
    ]
    static let pinnedWsjtx: [String: Int] = [
        "wsjtx.FT8": 2124, "wsjtx.DEC": 3002, "wsjtx.ENC": 1418, "wsjtx.EXCH": 1800, "wsjtx.IMP": 2038,
        "wsjtx.DEDUP": 1600, "wsjtx.SEND": 300,
    ]
    static let pinnedBroadcast: [String: Int] = [
        "broadcast.TGT": 3072, "broadcast.BXML": 3400, "n1mmrecv.N1MM": 2160, "scoreboard.SXML": 514,
    ]
    static let pinnedCallbook: [String: Int] = [
        "hamqth.HQ": 3032, "hamqth.QRZ": 2016, "hamqth.MASK": 1600, "hamqth.FLOW": 2058, "hamqth.PREFILL": 3171,
        "hamqth.GRIDDB": 1404, "hamqth.GRIDF": 2002, "clublog.FORM": 2806,
    ]
    static let pinnedGeo: [String: Int] = [
        "geo.SUN": 13930, "geo.TERM": 4200, "geo.FOF2": 1288, "geo.PROP": 3900, "geo.FCST": 816, "geo.WMAP": 208,
        "adifudp.FILT": 2058,
    ]
    static let pinnedSync: [String: Int] = [
        "sync.TOPICS": 338, "sync.INST": 1690, "sync.JSONW": 900, "sync.JSONR": 7864, "sync.MAP": 800,
        "sync.COORD": 400, "sync.NET": 600, "mqtt.UTF8": 3570, "mqtt.RC": 8, "mqtt.ID": 240,
    ]

    static func pinned(_ name: String) -> Int? {
        let groups: [[String: Int]] = [pinnedDxCluster, pinnedWsjtx, pinnedBroadcast, pinnedCallbook, pinnedGeo,
                                       pinnedSync]
        return groups.lazy.compactMap { $0[name] }.first
    }

    @Test func logicArmMatchesJava() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("net-logic-java")
            #expect(reference.map(\.relative) == Self.names, "set of reference items")
            for entry in reference {
                #expect(entry.lines.count == Self.pinned(entry.relative),
                        "\(entry.relative): number of reference rows (pinned)")
            }
            let own: [String: String] = try JavaNetParityFixture.ownInputs()
            // At most as many item threads at once as there are cores (CI 3) — the rest of the suite is not starved.
            let width: Int = max(2, ProcessInfo.processInfo.activeProcessorCount)
            let mine: [JavaNetParityFixture.Entry] = try await withThrowingTaskGroup(
                of: (Int, JavaNetParityFixture.Entry).self
            ) { group in
                var results = [JavaNetParityFixture.Entry?](repeating: nil, count: reference.count)
                for (index, entry) in reference.enumerated() {
                    if index >= width, let (done, replayed) = try await group.next() {
                        results[done] = replayed
                    }
                    group.addTask {
                        let replayed = try await JavaNetParityFixture.onGateThread(entry.relative) {
                            try JavaNetParityFixture.replay(entry, own: own)
                        }
                        return (index, replayed)
                    }
                }
                for try await (index, entry) in group {
                    results[index] = entry
                }
                return results.compactMap { $0 }
            }
            let report = JavaNetParityFixture.differences(reference: reference, mine: mine, regenerate: Self.regenerate,
                                                          label: "network logic")
            #expect(report == nil, Comment(rawValue: report ?? ""))
        }
    }
}
