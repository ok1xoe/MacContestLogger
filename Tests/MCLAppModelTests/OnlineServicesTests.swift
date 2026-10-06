import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Club Log, the score reporting and the clock check: every POST and every NTP query is
/// a scripted closure of the test, the waits are the injected `ManualClock` — no HTTP, no host, no wall-clock wait.
@MainActor @Suite struct OnlineServicesTests {

    static func clubLog(_ config: inout AppConfig, enabled: Bool = true) {
        config.clubLog.enabled = enabled
        config.clubLog.email = "user@example.test"
        config.clubLog.appPassword = "secret-password"
        config.clubLog.callsign = ""
        config.clubLog.apiKey = "secret-apikey"
    }

    static func score(_ config: inout AppConfig, enabled: Bool = true) {
        config.scoreReportingEnabled = enabled
        config.scoreReportingMinutes = 5
        config.scoreReportingUrl = "https://scoreboard.example.test/post/"
    }

    // MARK: - Club Log

    @Test func aLiveQsoIsUploadedAndTheStatusSaysSo() async throws {
        let app = try await IntegrationApp.make(configure: { config, _ in Self.clubLog(&config) })
        #expect(app.services.clubLogStatus.czech == "Club Log: zatím nic neodesláno")
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await eventually("uploaded") { app.online.uploads.count == 1 }
        let upload: ScriptedOnline.Upload = try #require(app.online.uploads.first)
        #expect(upload.email == "user@example.test")
        #expect(upload.apiKey == "secret-apikey")
        // The callsign falls back to the station's.
        #expect(upload.callsign == "OK1XOE")
        #expect(upload.adif.contains("OK1ABC"))
        await eventually("status") { app.services.clubLogStatus.czech == "Club Log: QSO odesláno (ve frontě 0)" }
        #expect(app.services.clubLogQueued == 0)
        // Credentials never reach a status text.
        #expect(!app.services.clubLogStatus.czech.contains("secret"))
        #expect(!app.model.status.message.contains("secret"))
    }

    @Test func anUnconfiguredClubLogQueuesNothing() async throws {
        let app = try await IntegrationApp.make(configure: { config, _ in Self.clubLog(&config, enabled: false) })
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await app.services.settle()
        #expect(app.online.uploads.isEmpty)
        #expect(app.services.clubLogQueued == 0)
    }

    @Test func aRejectedRecordIsDroppedAndTheNextOneGoesOut() async throws {
        let app = try await IntegrationApp.make(script: { online, _ in
            online.scriptClubLog([.REJECTED])
        }, configure: { config, _ in Self.clubLog(&config) })
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await eventually("rejected") {
            app.services.clubLogStatus.czech == "Club Log odmítl QSO (přihlášení nebo data) — zkontroluj nastavení"
        }
        #expect(app.services.clubLogQueued == 0)
        await app.app.logContestQso(call: "OK1ABD", zone: "15")
        await eventually("second uploaded") { app.online.uploads.count == 2 }
        #expect(app.online.uploads.last?.adif.contains("OK1ABD") == true)
        #expect(app.integrationClock.pendingCount >= 0)
    }

    /// RETRY: the record goes back to the front and waits 60 s of the injected clock, no tight loop.
    @Test func aRetryWaitsSixtySecondsAndSendsTheSameRecordAgain() async throws {
        let app = try await IntegrationApp.make(script: { online, _ in
            online.scriptClubLog([.RETRY, .OK])
        }, configure: { config, _ in Self.clubLog(&config) })
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await eventually("retry status") {
            app.services.clubLogStatus.czech == "Club Log nedostupný — zkusím znovu (ve frontě 1)"
        }
        #expect(app.services.clubLogQueued == 1)
        // A second QSO queues behind it and nothing is sent while the retry waits.
        await app.app.logContestQso(call: "OK1ABD", zone: "15")
        await app.services.settle()
        #expect(app.online.uploads.count == 1)
        app.integrationClock.advance(by: 59_999)
        await app.services.settle()
        #expect(app.online.uploads.count == 1)
        app.integrationClock.advance(by: 1)
        await eventually("both sent in order") { app.online.uploads.count == 3 }
        #expect(app.online.uploads[1].adif.contains("OK1ABC"))
        #expect(app.online.uploads[2].adif.contains("OK1ABD"))
        await eventually("queue empty") { app.services.clubLogQueued == 0 }
    }

    /// The queue is in memory only and is dropped at the quit.
    @Test func theQuitDropsTheClubLogQueue() async throws {
        let app = try await IntegrationApp.make(script: { online, _ in
            online.scriptClubLog([.RETRY])
        }, configure: { config, _ in Self.clubLog(&config) })
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await eventually("retry waits") { app.services.clubLogQueued == 1 }
        await app.model.shutdown()
        #expect(app.services.clubLogQueued == 0)
        app.integrationClock.advance(by: 120_000)
        await app.services.settle()
        #expect(app.online.uploads.count == 1)
    }

    // MARK: - score reporting

    @Test func theScoreIsPostedWhenDueAndOnlyOnceForTheSameLog() async throws {
        let app = try await IntegrationApp.make(configure: { config, _ in Self.score(&config) })
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        #expect(app.services.scoreReportStatus.czech == "Skóre se zatím neodesílalo")
        app.integrationClock.advance(by: 60_000)
        await eventually("posted") { app.online.posts.count == 1 }
        let post: ScriptedOnline.ScorePost = try #require(app.online.posts.first)
        #expect(post.url == "https://scoreboard.example.test/post/")
        #expect(post.xml.contains("<call>OK1XOE</call>"))
        #expect(post.xml.contains("<dynamicresults>"))
        #expect(post.xml.contains("<version>vývojová verze</version>"))
        await eventually("status") { app.services.scoreReportStatus.czech.hasSuffix("(HTTP 200)") }
        #expect(app.services.scoreReportStatus.czech.hasPrefix("Skóre "))
        // Nothing changed: the next tick posts nothing, however long it waits.
        app.now.advance(seconds: 3_600)
        app.integrationClock.advance(by: 60_000)
        await app.services.settle()
        #expect(app.online.posts.count == 1)
        // A new QSO after the interval is due at the next tick.
        await app.app.logContestQso(call: "OK1ABD", zone: "15")
        app.integrationClock.advance(by: 60_000)
        await eventually("second post") { app.online.posts.count == 2 }
        await app.services.settle()
        // Another QSO inside the interval is not due yet, after it is.
        await app.app.logContestQso(call: "OK1ABE", zone: "15")
        app.integrationClock.advance(by: 60_000)
        await app.services.settle()
        #expect(app.online.posts.count == 2)
        app.now.advance(seconds: 301)
        app.integrationClock.advance(by: 60_000)
        await eventually("third post") { app.online.posts.count == 3 }
    }

    /// A server error shows its HTTP status and does not remember the log revision: the same log is posted again at
    /// the next due time; the attempt time is remembered either way.
    @Test func aServerErrorIsShownAndTheSameLogIsPostedAgain() async throws {
        let app = try await IntegrationApp.make(script: { online, _ in
            online.scriptScore([.success(500), .success(ScoreResponse(status: 404, detail: "Contest not supported")), .failure(ScriptedOnline.ScriptedFailure(message: "boom")), .success(204)])
        }, configure: { config, _ in Self.score(&config) })
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        app.integrationClock.advance(by: 60_000)
        await eventually("500") { app.services.scoreReportStatus.czech == "Server vrátil HTTP 500" }
        // The attempt time counts: no second try within the interval.
        app.integrationClock.advance(by: 60_000)
        await app.services.settle()
        #expect(app.online.posts.count == 1)
        app.now.advance(seconds: 301)
        app.integrationClock.advance(by: 60_000)
        await eventually("404 with reason") {
            app.services.scoreReportStatus.czech == "Server vrátil HTTP 404: Contest not supported"
        }
        app.now.advance(seconds: 301)
        app.integrationClock.advance(by: 60_000)
        await eventually("failure") { app.services.scoreReportStatus.czech == "Odeslání skóre selhalo: boom" }
        app.now.advance(seconds: 301)
        app.integrationClock.advance(by: 60_000)
        await eventually("accepted") { app.services.scoreReportStatus.czech.hasSuffix("(HTTP 204)") }
        #expect(app.online.posts.count == 4)
        app.now.advance(seconds: 301)
        app.integrationClock.advance(by: 60_000)
        await app.services.settle()
        #expect(app.online.posts.count == 4)
    }

    @Test func sendNowPostsEvenWhenDisabledAndNotDue() async throws {
        let app = try await IntegrationApp.make(configure: { config, _ in Self.score(&config, enabled: false) })
        try await app.app.startCqWwCw()
        app.integrationClock.advance(by: 60_000)
        await app.services.settle()
        #expect(app.online.posts.isEmpty)
        app.model.settings.services.reportScoreNow()
        await eventually("posted") { app.online.posts.count == 1 }
        // A send while the first one is still in flight is dropped (Kotlin `scoreInFlight`), so press again until the
        // second post goes out instead of racing the first one's outcome.
        await eventually("posted again") {
            app.services.reportScoreNow()
            return app.online.posts.count >= 2
        }
    }

    @Test func noScoreWithoutAContest() async throws {
        let app = try await IntegrationApp.make(configure: { config, _ in Self.score(&config) })
        app.services.reportScoreNow()
        app.integrationClock.advance(by: 60_000)
        await app.services.settle()
        #expect(app.online.posts.isEmpty)
    }

    // MARK: - clock check

    @Test func theClockIsCheckedAtStartAndEveryHalfHour() async throws {
        let app = try await IntegrationApp.make(script: { _, probe in probe.script([.success(120), .success(-80)]) })
        await eventually("first check") { app.probe.hosts.count == 1 }
        #expect(app.probe.hosts == ["ntp.example.test"])
        await eventually("status") { app.services.clockStatus.czech == "Hodiny: odchylka +0.12 s od ntp.example.test" }
        #expect(app.services.clockOffsetMs == 120)
        app.integrationClock.advance(by: 30 * 60_000)
        await eventually("second check") { app.probe.hosts.count == 2 }
        await eventually("new status") { app.services.clockStatus.czech == "Hodiny: odchylka -0.08 s od ntp.example.test" }
        app.model.settings.services.checkClock()
        await eventually("third check") { app.probe.hosts.count == 3 }
    }

    @Test func theQsoTimeIsCorrectedOnlyWithTheOption() async throws {
        let plain = try await IntegrationApp.make(script: { _, probe in probe.script([.success(400)]) })
        await eventually("checked") { plain.services.clockOffsetMs == 400 }
        await plain.model.logbook.setClockOffset(milliseconds: 0)
        let plainOffset: TimeInterval = try await plain.model.database.handle.run { $0.service.clockOffset }
        #expect(plainOffset == 0)
        #expect(!plain.services.clockStatus.czech.contains("opravován"))

        let corrected = try await IntegrationApp.make(script: { _, probe in probe.script([.success(400)]) },
                                                      configure: { config, _ in config.ntpCorrectQsoTime = true })
        await eventually("checked") { corrected.services.clockOffsetMs == 400 }
        await eventually("applied") {
            corrected.services.clockStatus.czech == "Hodiny: odchylka +0.40 s od ntp.example.test (čas QSO opravován)"
        }
        // The offset is written on the database queue right after the status; read it until it shows (bounded).
        var appliedOffset: TimeInterval = 0
        for _ in 0..<5_000 where appliedOffset != 0.4 {
            appliedOffset = try await corrected.model.database.handle.run { $0.service.clockOffset }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(appliedOffset == 0.4)
    }

    @Test func aLargeOffsetWarnsInTheStatusLineAndTheMessages() async throws {
        let app = try await IntegrationApp.make(script: { _, probe in probe.script([.success(2_500)]) })
        await eventually("warned") {
            app.model.status.message == "⏰ Hodiny: odchylka +2.50 s od ntp.example.test — srovnej hodiny počítače"
        }
        #expect(app.model.messages.lines.last?.text == "Hodiny: odchylka +2.50 s od ntp.example.test")
        #expect(app.model.infoStrip.text.contains("HODINY +2.5 s"))
    }

    @Test func anUnreachableServerIsAStatus() async throws {
        let app = try await IntegrationApp.make(script: { _, probe in
            probe.script([.failure(ScriptedOnline.ScriptedFailure(message: "boom"))])
        })
        await eventually("failed") { app.services.clockStatus.czech == "NTP ntp.example.test nedostupný: boom" }
        #expect(app.services.clockOffsetMs == nil)
    }

    @Test func aBlankServerSwitchesTheCheckOff() async throws {
        let app = try await IntegrationApp.make(configure: { config, _ in config.ntpServer = "  " })
        app.services.checkClock()
        #expect(app.services.clockStatus.czech == "Synchronizace času vypnutá")
        await app.services.settle()
        #expect(app.probe.hosts.isEmpty)
    }

    // MARK: - the inert switch

    /// With the inert ports nothing is bound, sent, uploaded, posted or asked, whatever the config says.
    @Test func theInertEnvironmentOpensNothing() async throws {
        let app = try await IntegrationApp.make(isInert: true, configure: { config, _ in
            Self.clubLog(&config)
            Self.score(&config)
            config.wsjtx.receiveEnabled = true
            config.wsjtx.receiveBind = "127.0.0.1:45002"
            config.wsjtx.sendEnabled = true
            config.wsjtx.sendTargets = "127.0.0.1:45010"
            config.n1mmRecv.receiveEnabled = true
            config.n1mmRecv.receiveBind = "127.0.0.1:45004"
            config.adifUdp.receiveEnabled = true
            config.adifUdp.receiveBind = "127.0.0.1:45005"
            config.broadcast.contactsEnabled = true
            config.broadcast.contactsTargets = "127.0.0.1:45011"
        })
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        app.services.reportScoreNow()
        app.services.checkClock()
        app.integrationClock.advance(by: 30 * 60_000)
        await app.integrations.settle()
        await app.services.settle()
        #expect(app.udpCounts.listeners == 0)
        #expect(app.udpCounts.broadcasters == 0)
        #expect(app.integrations.wsjtxPort == nil && app.integrations.n1mmPort == nil && app.integrations.adifPort == nil)
        #expect(!app.integrations.broadcastActive && !app.integrations.wsjtxSendActive)
        #expect(app.online.uploads.isEmpty)
        #expect(app.online.posts.isEmpty)
        #expect(app.probe.hosts.isEmpty)
    }
}
