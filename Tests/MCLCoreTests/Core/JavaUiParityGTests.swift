import Foundation
import Testing
@testable import MCLCore

/// Java parity: the network and integration logic against the real Kotlin code of v1.1.1, over a synthetic corpus
/// (`Fixtures/ui-gate/net-g.txt`): the chat / PASS / STACK reducer and the send plans over peers that are online,
/// offline or stale (`net.MSG`); the serial reservation over ticks, replies and writes (`net.SERIAL`); the own station
/// status (`net.STATUS`); the N1MM and ADIF ingest in four contexts (`ext.INGEST`); the broadcast mapping and its XML
/// (`bc.MAP`); the WSJT-X decode list with its filters and cell texts (`wsjtx.DEC`); the scoreboard report, the Club Log
/// queue and the NTP clock texts (`svc.POLICY`). The reference `Fixtures/ui-g-java.json.gz` comes from
/// a maintainer-only probe (fixture `g`, instructions kept with the probe). The generator opens no socket, binds no UDP port,
/// sends no HTTP request, asks no NTP server and starts no plugin.
///
/// Input rows are taken from the reference (the rows that carry a corpus record, the `defs` and the `corpus` row are
/// rebuilt by Swift from its own files), outputs are computed by Swift (`UiParityGSections`). A change of inputs =
/// "REGENERATE REFERENCE", a different output = "MISMATCH". The gate prints nothing; each item runs on its own
/// thread, not in the shared pool.
@Suite struct JavaUiParityGTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Rows per item in the Java reference — against a broken generator (an empty corpus, a missing context),
    /// where inputs taken from the reference would still match.
    static let pinned: [String: Int] = [
        "net.MSG": 1_690, "net.SERIAL": 1_122, "net.STATUS": 842, "ext.INGEST": 954, "bc.MAP": 244, "wsjtx.DEC": 5_810,
        "svc.POLICY": 620,
    ]

    @Test func networkAndIntegrationsMatchKotlin() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("ui-g-java")
            #expect(reference.map(\.relative) == UiParityGSections.names, "set of reference items")
            for entry in reference {
                #expect(entry.lines.count == Self.pinned[entry.relative],
                        "\(entry.relative): number of reference rows (pinned)")
            }
            let mine: [UiParityGSections.Entry] = try await UiParityGSections.replayAll(reference)
            let report = JavaNetParityFixture.differences(reference: reference, mine: mine, regenerate: Self.regenerate,
                                                          label: "network and integrations")
            #expect(report == nil, Comment(rawValue: report ?? ""))
        }
    }

    /// The corpus and the scripts reach what the sections are meant to compare: every message type, the three
    /// reducer outcomes of PASS, peers online / offline / stale, a duplicate inside and outside the 120 s window, a
    /// foreign mode, an own echo, a decode with a dupe and one with a new multiplier, a refused report and a
    /// non-2xx one, every Club Log outcome and a clock warning.
    @Test func referenceCoversTheCases() throws {
        let reference = try JavaIoParityFixture.reference("ui-g-java")
        func lines(_ name: String) throws -> [[String]] {
            let entry = try #require(reference.first { $0.relative == name })
            return entry.lines.map(JavaEngineParityTests.fields)
        }
        let msg: [[String]] = try lines("net.MSG").filter { $0[1] == "out" && $0[0].hasPrefix("r/") }
        #expect(msg.contains { $0[2].hasPrefix("Chat ") }, "a chat message")
        #expect(msg.contains { $0[2].hasPrefix("Pass od ") && $0[7] != "" }, "a PASS with a spot")
        #expect(msg.contains { $0[2].hasPrefix("Z\\u00E1sobn\\u00EDk od ") }, "a STACK message")
        #expect(msg.contains { $0[2] == "" && $0[5] != "~" }, "a message of another type")
        let send: [[String]] = try lines("net.MSG").filter { $0[1] == "out" && $0[0].hasPrefix("t/") }
        #expect(send.contains { $0[2].contains("sent=[PASS") }, "a PASS sent")
        let ingest: [[String]] = try lines("ext.INGEST").filter { $0[1] == "out" }
        for outcome in ["drop", "status", "log", "logfail"] {
            #expect(ingest.contains { $0[2] == outcome }, "ingest outcome \(outcome)")
        }
        #expect(ingest.contains { $0[2] == "log" && $0[3] == "false" }, "a QSO the contest does not count")
        let decodes: [[String]] = try lines("wsjtx.DEC").filter { $0[1] == "out" && $0.count == 11 }
        #expect(decodes.contains { $0[4] == "1" }, "a dupe decode")
        #expect(decodes.contains { $0[5] != "0" && $0[4] == "0" }, "a decode with a new multiplier")
        let policy: [[String]] = try lines("svc.POLICY").filter { $0[1] == "out" }
        #expect(policy.contains { $0[0].hasPrefix("p/") && $0[2] == "posts=1" }, "a posted report")
        #expect(policy.contains { $0[0].hasPrefix("p/") && $0[2] == "posts=0" }, "a report that was not due")
        #expect(policy.contains { $0[0].hasPrefix("o/RETRY") }, "a Club Log retry")
        #expect(policy.contains { $0[0].hasPrefix("n/") && $0[5].hasPrefix("\\u23F0") }, "a clock warning")
    }
}
