import Foundation
import MCLCore
import os
import Testing
@testable import MCLAppModel

/// The Club Log and scoreboard POSTs of the tests: scripted answers, every call recorded — no HTTP, no host.
final class ScriptedOnline: @unchecked Sendable {
    struct Upload: Sendable {
        let email: String
        let password: String
        let callsign: String
        let apiKey: String
        let adif: String
    }

    struct ScorePost: Sendable {
        let url: String
        let xml: String
    }

    private struct State {
        var clubLogOutcomes: [ClubLogClient.Outcome] = []
        var uploads: [Upload] = []
        var scoreAnswers: [Result<Int, ScriptedFailure>] = []
        var posts: [ScorePost] = []
    }

    /// A failure whose message reads like a Java exception's (`getMessage()`), as the real ports' errors do.
    struct ScriptedFailure: JavaThrowable, Sendable {
        let message: String
        var javaClass: String { "java.io.IOException" }
        var javaMessage: String? { message }
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// The next Club Log outcomes (then `OK`).
    func scriptClubLog(_ outcomes: [ClubLogClient.Outcome]) {
        state.withLock { $0.clubLogOutcomes = outcomes }
    }

    func scriptScore(_ answers: [Result<Int, ScriptedFailure>]) {
        state.withLock { $0.scoreAnswers = answers }
    }

    var uploads: [Upload] { state.withLock { $0.uploads } }
    var posts: [ScorePost] { state.withLock { $0.posts } }

    var ports: OnlinePorts {
        OnlinePorts(
            uploadClubLog: { [self] email, password, callsign, apiKey, adif in
                state.withLock { s in
                    s.uploads.append(Upload(email: email, password: password, callsign: callsign, apiKey: apiKey,
                                            adif: adif))
                    return s.clubLogOutcomes.isEmpty ? .OK : s.clubLogOutcomes.removeFirst()
                }
            },
            postScore: { [self] url, xml in
                let answer: Result<Int, ScriptedFailure> = state.withLock { s in
                    s.posts.append(ScorePost(url: url, xml: xml))
                    return s.scoreAnswers.isEmpty ? .success(200) : s.scoreAnswers.removeFirst()
                }
                return try answer.get()
            })
    }
}

/// The NTP probe of the tests: scripted answers, the asked hosts recorded — never a lookup.
final class ScriptedClockProbe: @unchecked Sendable {
    private struct State {
        var answers: [Result<Int64, ScriptedOnline.ScriptedFailure>] = []
        var hosts: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func script(_ answers: [Result<Int64, ScriptedOnline.ScriptedFailure>]) {
        state.withLock { $0.answers = answers }
    }

    var hosts: [String] { state.withLock { $0.hosts } }

    var probe: ClockProbe {
        { [self] host in
            let answer: Result<Int64, ScriptedOnline.ScriptedFailure> = state.withLock { s in
                s.hosts.append(host)
                return s.answers.isEmpty ? .success(0) : s.answers.removeFirst()
            }
            return try answer.get()
        }
    }
}

/// An app over a temporary data directory whose network is loopback UDP, scripted HTTP POSTs and NTP, and plugins
/// rooted in the app's own temporary directory — never a real host, port or user plugin directory.
@MainActor
struct IntegrationApp {
    let app: TestApp
    let integrationClock: ManualClock
    let online: ScriptedOnline
    let probe: ScriptedClockProbe
    let udpCounts: UdpFactoryCounts
    let now: TestNow

    var model: AppModel { app.model }
    var integrations: IntegrationsModel { app.model.integrations }
    var services: OnlineServicesModel { app.model.onlineServices }
    var plugins: PluginsModel { app.model.plugins }

    static func ports(online: ScriptedOnline, probe: ScriptedClockProbe, counts: UdpFactoryCounts,
                      isInert: Bool = false) -> NetworkPorts {
        let plugins = PluginsPorts { root, timeoutMs in
            precondition(root.contains("mcl-app-model-"), "plugins run from the test's temporary directory only")
            return PluginRunner(root: root, timeoutMs: timeoutMs)
        }
        return NetworkPorts(makeSession: NetworkPorts.inert.makeSession, http: InertHttpGetter(), urlOpener: .inert,
                            udp: loopbackUdpPorts(counts), online: online.ports, clock: probe.probe,
                            plugins: plugins, isInert: isInert)
    }

    /// `configure` sets the `config.json` of the run; the NTP server is a placeholder the probe answers for.
    static func make(isInert: Bool = false, script: (ScriptedOnline, ScriptedClockProbe) -> Void = { _, _ in },
                     configure: @escaping (inout AppConfig, URL) throws -> Void = { _, _ in },
                     adjust: @escaping (inout AppModel.Environment) -> Void = { _ in }) async throws -> IntegrationApp {
        let online = ScriptedOnline()
        let probe = ScriptedClockProbe()
        let counts = UdpFactoryCounts()
        let clock = ManualClock()
        let now = TestNow(Date(timeIntervalSince1970: 1_790_000_000))
        script(online, probe)
        let app = try await TestApp.make(now: now, configure: { config, dir in
            config.ntpServer = "ntp.example.test"
            try configure(&config, dir)
        }, adjust: { environment in
            environment.network = ports(online: online, probe: probe, counts: counts, isInert: isInert)
            environment.integrationClock = clock
            adjust(&environment)
        })
        return IntegrationApp(app: app, integrationClock: clock, online: online, probe: probe, udpCounts: counts,
                              now: now)
    }
}
