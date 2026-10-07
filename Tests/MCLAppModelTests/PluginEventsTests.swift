import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The plugin events beyond QSO_LOGGED / CONTEST_OPENED / SPOT_RECEIVED. Plugins are tiny `/bin/sh` scripts in the
/// test's own temporary directory; each run stores its stdin in `out/<MCL_EVENT>.<pid>`. The clock is the injected
/// `ManualClock`, never a wall-clock wait. "Does not fire" cases end with a positive control through the same
/// (serial) plugin lane.
@MainActor @Suite struct PluginEventsTests {

    /// Installs a recorder plugin for `events` (directory names) and returns the output directory.
    static func record(_ app: IntegrationApp, _ events: [String]) throws -> URL {
        let out: URL = app.app.dir.child("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for event in events {
            try PluginsModelTests.plugin(app, event: event, name: "rec.sh",
                                         body: "cat > \"\(out.path)/$MCL_EVENT.$$\"")
        }
        return out
    }

    /// Installs the recorder before the app starts (the data directory is known to `configure`).
    static func recordBeforeStart(_ dataDir: URL, out: URL, event: String) throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let dir: URL = dataDir.appendingPathComponent("plugins/\(event)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file: URL = dir.appendingPathComponent("rec.sh")
        try ("#!/bin/sh\ncat > \"\(out.path)/$MCL_EVENT.$$\"\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }

    /// The payloads received for the event (its directory name), as parsed JSON objects.
    static func payloads(_ out: URL, _ event: String) -> [[String: Any]] {
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []
        return names.filter { $0.hasPrefix(event + ".") }.sorted().compactMap { name in
            guard let data = try? Data(contentsOf: out.appendingPathComponent(name)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return json
        }
    }

    static func count(_ out: URL, _ event: String) -> Int {
        payloads(out, event).count
    }

    /// A positive control behind everything queued so far: a harmless extra event, awaited through the lane.
    static func control(_ app: IntegrationApp) async {
        app.plugins.fire(.spotReceived, json: "{}")
        await app.plugins.settle()
    }

    static func num(_ json: [String: Any], _ key: String) -> Int64? {
        (json[key] as? NSNumber)?.int64Value
    }

    // MARK: - QSO edits and deletes

    @Test func anEditAndADeleteFireWithTheQsos() async throws {
        let app = try await IntegrationApp.make()
        let out = try Self.record(app, ["qso-edited", "qso-deleted"])
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        let old: Qso = try #require(app.model.logbook.rows.first)
        var new: Qso = old
        new.comment = "edited"
        _ = await app.model.logbook.update(LogbookMutations.Edit(old: old, new: new))
        await app.plugins.settle()
        let edited = try #require(Self.payloads(out, "qso-edited").first)
        let oldJson = try #require(edited["old"] as? [String: Any])
        let newJson = try #require(edited["new"] as? [String: Any])
        #expect(oldJson["call"] as? String == "OK1ABC")
        #expect(newJson["call"] as? String == "OK1ABC")
        #expect(newJson["uuid"] as? String == old.uuid)

        await app.model.logbook.delete(app.model.logbook.rows)
        await app.plugins.settle()
        let deleted = try #require(Self.payloads(out, "qso-deleted").first)
        #expect(deleted["call"] as? String == "OK1ABC")
        #expect(Self.count(out, "qso-edited") == 1)
        #expect(Self.count(out, "qso-deleted") == 1)
    }

    @Test func aSimulatedQsoEditOrDeleteFiresNothing() async throws {
        let audio = SimAudioFactory()
        let app = try await IntegrationApp.make(adjust: { audio.install(into: &$0) })
        let out = try Self.record(app, ["qso-edited", "qso-deleted"])
        try await app.app.startCqWwCw()
        app.model.simulator.liveOutwardService = { nil }
        app.model.simulator.random = CountingPileupRandom()
        app.model.simulator.start(settings: SimulatorModelTests.settings, noise: 0.15)
        await app.model.simulator.settle()
        await app.app.logContestQso(call: "OK1SIM", zone: "15")
        let old: Qso = try #require(app.model.logbook.rows.first { $0.call == "OK1SIM" })
        var new: Qso = old
        new.comment = "edited"
        _ = await app.model.logbook.update(LogbookMutations.Edit(old: old, new: new))
        await app.model.logbook.delete(app.model.logbook.rows.filter { $0.call == "OK1SIM" })
        await Self.control(app)
        #expect(Self.count(out, "qso-edited") == 0)
        #expect(Self.count(out, "qso-deleted") == 0)
    }

    // MARK: - lifecycle

    @Test func leavingAContestFiresContestClosed() async throws {
        let app = try await IntegrationApp.make()
        let out = try Self.record(app, ["contest-closed"])
        try await app.app.startCqWwCw()
        await Self.control(app)
        #expect(Self.count(out, "contest-closed") == 0, "opening the first contest closes nothing")
        // Another contest.
        var setup = ContestSetup()
        setup.sentExchange = ["zone": "15"]
        let firstId: String? = app.model.contest.activeId
        let started: Bool = await app.model.contest.createAndStart(definitionId: "cq-ww-ssb", setup: setup)
        #expect(started)
        await app.plugins.settle()
        let first = try #require(Self.payloads(out, "contest-closed").first)
        #expect(first["contestId"] as? String == firstId)
        #expect(Self.count(out, "contest-closed") == 1)
        // Contest -> None.
        let secondId: String? = app.model.contest.activeId
        app.model.contest.deactivate()
        await app.model.contest.settleActivations()
        await app.plugins.settle()
        let all = Self.payloads(out, "contest-closed")
        #expect(all.count == 2)
        #expect(all.contains { $0["contestId"] as? String == secondId })
        // Nothing active: no second close.
        app.model.contest.deactivate()
        await app.model.contest.settleActivations()
        await Self.control(app)
        #expect(Self.count(out, "contest-closed") == 2)
    }

    @Test func startUpFiresAppStartedWithTheVersionOnly() async throws {
        let holder = DirHolder()
        let app = try await IntegrationApp.make(configure: { _, dataDir in
            let out: URL = dataDir.deletingLastPathComponent().appendingPathComponent("out")
            holder.out = out
            try Self.recordBeforeStart(dataDir, out: out, event: "app-started")
        }, adjust: { $0.appVersion = "9.9.9-test" })
        let out: URL = try #require(holder.out)
        await eventually("app-started") { Self.count(out, "app-started") == 1 }
        let payload = try #require(Self.payloads(out, "app-started").first)
        #expect(payload["version"] as? String == "9.9.9-test")
        #expect(payload["contestId"] is NSNull)
        #expect(Set(payload.keys) == ["version", "contestId", "name"], "no paths, no other fields")
        _ = app
    }

    @Test func quittingFiresAppQuittingAndNeverOutlastsTheQuitDeadline() async throws {
        let app = try await IntegrationApp.make(adjust: { $0.appVersion = "9.9.9-test" })
        let out: URL = try Self.record(app, ["app-quitting"])
        let marker: URL = app.app.dir.child("slow-finished")
        // Sorted after `rec.sh`: it starts after the recorder and would run 30 s without the deadline.
        try PluginsModelTests.plugin(app, event: "app-quitting", name: "slow.sh",
                                     body: "sleep 30\ntouch '\(marker.path)'")
        try await app.app.startCqWwCw()
        app.plugins.quitBoundMs = 2_000
        await app.model.shutdown()
        #expect(Self.count(out, "app-quitting") == 1)
        let payload = try #require(Self.payloads(out, "app-quitting").first)
        #expect(payload["version"] as? String == "9.9.9-test")
        #expect((payload["contestId"] as? String)?.isEmpty == false)
        // The 30 s plugin would leave the marker if the quit had waited for it; no wall-clock bound (slow CI runners).
        #expect(!FileManager.default.fileExists(atPath: marker.path), "the slow plugin was cut off")
    }

    // MARK: - band, mode, frequency

    @Test func bandAndModeFireOnChangeOnly() async throws {
        let app = try await IntegrationApp.make()
        let out = try Self.record(app, ["band-changed", "mode-changed"])
        let entry: EntryModel = app.model.entry
        entry.setMode(.cw)
        entry.setFrequency("14025")
        await Self.control(app)
        #expect(Self.count(out, "band-changed") == 0, "the first value is only the baseline")
        #expect(Self.count(out, "mode-changed") == 0)
        entry.setFrequency("14030")
        entry.setMode(.cw)
        await Self.control(app)
        #expect(Self.count(out, "band-changed") == 0, "the same band again")
        #expect(Self.count(out, "mode-changed") == 0)
        entry.setFrequency("7050")
        entry.setMode(.ssb)
        await app.plugins.settle()
        let band = try #require(Self.payloads(out, "band-changed").first)
        #expect(band["oldBand"] as? String == "20m")
        #expect(band["newBand"] as? String == "40m")
        #expect(Self.num(band, "radio") == 0)
        let mode = try #require(Self.payloads(out, "mode-changed").first)
        #expect(mode["oldMode"] as? String == "CW")
        #expect(mode["newMode"] as? String == "SSB")
        #expect(Self.count(out, "band-changed") == 1)
        #expect(Self.count(out, "mode-changed") == 1)
    }

    @Test func frequencyFiresOnlyAfterItHasBeenStableForASecond() async throws {
        let app = try await IntegrationApp.make()
        let out = try Self.record(app, ["frequency-changed"])
        let entry: EntryModel = app.model.entry
        let clock: ManualClock = app.integrationClock
        entry.setFrequency("14025")
        // Tuning the VFO: many steps, each restarts the wait.
        for kHz in ["14026", "14027", "14028", "14029", "14030"] {
            entry.setFrequency(kHz)
            clock.advance(by: 400)
        }
        await Self.control(app)
        #expect(Self.count(out, "frequency-changed") == 0, "still being tuned")
        clock.advance(by: PluginsModel.frequencySettleMs - 400)
        await app.plugins.settle()
        #expect(Self.count(out, "frequency-changed") == 1)
        let payload = try #require(Self.payloads(out, "frequency-changed").first)
        #expect(Self.num(payload, "oldFreqHz") == 14_025_000)
        #expect(Self.num(payload, "newFreqHz") == 14_030_000)
        #expect(Self.num(payload, "radio") == 0)
        // Away and back within the wait: nothing.
        entry.setFrequency("14040")
        clock.advance(by: 500)
        entry.setFrequency("14030")
        clock.advance(by: 5_000)
        await Self.control(app)
        #expect(Self.count(out, "frequency-changed") == 1)
        // A new stable frequency: a second event, reported from the previous reported one.
        entry.setFrequency("14040")
        clock.advance(by: PluginsModel.frequencySettleMs)
        await app.plugins.settle()
        let all = Self.payloads(out, "frequency-changed")
        #expect(all.count == 2)
        #expect(all.contains { Self.num($0, "oldFreqHz") == 14_030_000 && Self.num($0, "newFreqHz") == 14_040_000 })
    }

    @Test func noRadioTimersWithoutAPluginsRunner() async throws {
        let app = try await IntegrationApp.make(isInert: true, adjust: { $0.network.plugins = .inert })
        #expect(!app.plugins.isActive)
        let before: Int = app.integrationClock.pendingCount
        app.model.entry.setFrequency("14025")
        app.model.entry.setFrequency("7050")
        #expect(app.integrationClock.pendingCount == before)
        app.integrationClock.advance(by: 10_000)
        await app.plugins.settle()
        #expect(app.plugins.completedRuns == 0)
    }

    // MARK: - self-spots

    @Test func aSelfSpotFiresWithSpotterAndSource() async throws {
        let app = try await IntegrationApp.make()
        let out = try Self.record(app, ["self-spotted"])
        let human = SelfSpot(spotter: "OK1ABC", freqHz: 14_025_000, rbn: false, snrDb: nil, wpm: nil, at: Date())
        let skimmer = SelfSpot(spotter: "DK9IP-#", freqHz: 14_026_300, rbn: true, snrDb: 23, wpm: 28, at: Date())
        app.model.dxCluster.selfSpotted(human)
        app.model.dxCluster.selfSpotted(skimmer)
        await app.plugins.settle()
        let all = Self.payloads(out, "self-spotted")
        #expect(all.count == 2)
        let first = try #require(all.first { $0["spotter"] as? String == "OK1ABC" })
        #expect(first["source"] as? String == "human")
        #expect(Self.num(first, "freqHz") == 14_025_000)
        #expect(first["snr"] is NSNull)
        let second = try #require(all.first { $0["spotter"] as? String == "DK9IP-#" })
        #expect(second["source"] as? String == "skimmer")
        #expect(Self.num(second, "snr") == 23)
        #expect(Self.num(second, "wpm") == 28)
    }

    // MARK: - multipliers and score

    @Test func aNewMultiplierFiresOnlyForAQsoThatMakesOne() async throws {
        let app = try await IntegrationApp.make()
        let out = try Self.record(app, ["new-multiplier"])
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await app.plugins.settle()
        #expect(Self.count(out, "new-multiplier") == 1)
        let payload = try #require(Self.payloads(out, "new-multiplier").first)
        #expect(payload["call"] as? String == "OK1ABC")
        #expect(payload["band"] as? String == "20m")
        #expect(payload["mode"] as? String == "CW")
        #expect((payload["contestId"] as? String)?.isEmpty == false)
        let mults = try #require(payload["multipliers"] as? [[String: Any]])
        #expect(!mults.isEmpty)
        #expect(mults.allSatisfy { $0["key"] is String && $0["set"] is String })
        // The same zone and country on the same band: nothing new.
        await app.app.logContestQso(call: "OK1ABD", zone: "15")
        // A dupe: nothing.
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await Self.control(app)
        #expect(Self.count(out, "new-multiplier") == 1)
    }

    @Test func scoreChangesAreCoalescedIntoOneEvent() async throws {
        let app = try await IntegrationApp.make()
        let out = try Self.record(app, ["score-changed"])
        let clock: ManualClock = app.integrationClock
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await app.app.logContestQso(call: "OK2ABC", zone: "15")
        await app.app.logContestQso(call: "DL1ABC", zone: "14")
        await Self.control(app)
        #expect(Self.count(out, "score-changed") == 0, "nothing until the score has been quiet")
        clock.advance(by: PluginsModel.scoreSettleMs)
        await app.plugins.settle()
        #expect(Self.count(out, "score-changed") == 1)
        let payload = try #require(Self.payloads(out, "score-changed").first)
        #expect(Self.num(payload, "qsos") == 3)
        #expect(Self.num(payload, "total") == app.model.contest.score?.total)
        #expect(Self.num(payload, "mults") == Int64(app.model.contest.score?.multTotal ?? -1))
        #expect(payload["contestId"] as? String == app.model.contest.activeId)
        // A rescore that changes nothing fires nothing.
        app.model.contest.requestRescore(manual: true)
        await app.model.contest.settleRescore()
        clock.advance(by: 10_000)
        await Self.control(app)
        #expect(Self.count(out, "score-changed") == 1)
    }

    @Test func noScoreEventWithoutAContest() async throws {
        let app = try await IntegrationApp.make()
        let out = try Self.record(app, ["score-changed"])
        let score = ScoreState(qsoCount: 1, qsoPoints: 1, multTotal: 1, multByGroup: JavaLinkedMap<Int32>(),
                               bonusPoints: 0, qtcPoints: 0, total: 1)
        app.plugins.scoreChanged(contestId: nil, score: score)
        app.integrationClock.advance(by: 10_000)
        await Self.control(app)
        #expect(Self.count(out, "score-changed") == 0)
    }

    // MARK: - uploads

    @Test func aScoreReportFiresWithoutTheUrlOrSecrets() async throws {
        let app = try await IntegrationApp.make(configure: { config, _ in OnlineServicesTests.score(&config) })
        let out = try Self.record(app, ["score-reported"])
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        app.services.reportScoreNow()
        await eventually("posted") { app.online.posts.count == 1 }
        await app.services.settle()
        await app.plugins.settle()
        let payload = try #require(Self.payloads(out, "score-reported").first)
        #expect(payload["host"] as? String == "scoreboard.example.test")
        #expect(Self.num(payload, "status") == 200)
        #expect(payload["accepted"] as? Bool == true)
        #expect(payload["message"] is String)
        let text: String = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        #expect(!text.contains("/post"), "never the full URL")
    }

    @Test func aRejectedScoreReportSaysSo() async throws {
        let app = try await IntegrationApp.make(script: { online, _ in
            online.scriptScore([.success(ScoreResponse(status: 500))])
        }, configure: { config, _ in OnlineServicesTests.score(&config) })
        let out = try Self.record(app, ["score-reported"])
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        app.services.reportScoreNow()
        await eventually("posted") { app.online.posts.count == 1 }
        await app.services.settle()
        await app.plugins.settle()
        let payload = try #require(Self.payloads(out, "score-reported").first)
        #expect(Self.num(payload, "status") == 500)
        #expect(payload["accepted"] as? Bool == false)
    }

    @Test func clubLogUploadsFireWithTheOutcomeAndNoCredentials() async throws {
        let app = try await IntegrationApp.make(script: { online, _ in
            online.scriptClubLog([.OK, .REJECTED, .RETRY])
        }, configure: { config, _ in OnlineServicesTests.clubLog(&config) })
        let out = try Self.record(app, ["clublog-upload"])
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await eventually("first") { app.online.uploads.count == 1 }
        await app.app.logContestQso(call: "OK1ABD", zone: "15")
        await eventually("second") { app.online.uploads.count == 2 }
        await app.app.logContestQso(call: "OK1ABE", zone: "15")
        await eventually("third") { app.online.uploads.count == 3 }
        await app.services.settle()
        await app.plugins.settle()
        let all = Self.payloads(out, "clublog-upload")
        #expect(all.count == 3)
        var byCall: [String: String] = [:]
        for item in all {
            if let call = item["call"] as? String, let outcome = item["outcome"] as? String {
                byCall[call] = outcome
            }
        }
        #expect(byCall["OK1ABC"] == "ok")
        #expect(byCall["OK1ABD"] == "rejected")
        #expect(byCall["OK1ABE"] == "retry")
        let text: String = String(decoding: try JSONSerialization.data(withJSONObject: all), as: UTF8.self)
        for secret in ["secret-password", "secret-apikey", "user@example.test"] {
            #expect(!text.contains(secret))
        }
    }
}

/// Carries a value out of a `configure` closure.
final class DirHolder: @unchecked Sendable {
    var out: URL?
}
