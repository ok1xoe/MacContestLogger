import Foundation
import MCLCore

extension AppModel {

    /// The integrations (broadcast, WSJT-X, N1MM and ADIF receive, Club Log, the scoreboard, the clock
    /// check, the plugins) and their hooks: the stored QSO (Club Log, plugins, broadcast, WSJT-X, in Kotlin's order),
    /// an edit and a delete (the broadcast), the activation's plugin event, the spots' plugin event, BCLOG, HODINY and
    /// the Settings ports. The services start in `activateIntegrations` (Kotlin `App.kt:140-143`).
    static func wireIntegrations(_ model: AppModel, environment: Environment) {
        let clock: any RescoreClock = environment.integrationClock ?? MainQueueRescoreClock()
        let plugins = PluginsModel(ports: environment.network.plugins, dataDir: environment.dataDir,
                                   messages: model.messages, language: model.language, now: environment.now,
                                   clock: clock, appVersion: environment.appVersion)
        let integrations = IntegrationsModel(IntegrationsModel.Dependencies(
            config: model.config, status: model.status, language: model.language, contest: model.contest,
            logbook: model.logbook, operating: model.operating, rig: model.rig, network: environment.network,
            analyzer: { [weak analysis = model.spotAnalysis] in analysis?.current() }, clock: clock,
            now: environment.now))
        let online = OnlineServicesModel(OnlineServicesModel.Dependencies(
            config: model.config, status: model.status, language: model.language, contest: model.contest,
            logbook: model.logbook, messages: model.messages, network: environment.network, clock: clock,
            now: environment.now, appVersion: environment.appVersion))
        model.plugins = plugins
        model.integrations = integrations
        model.onlineServices = online

        model.logbook.onLiveQso = { [weak integrations, weak online, weak plugins] qso in
            online?.queueClubLog(qso)
            plugins?.qsoLogged(qso)
            integrations?.qsoLogged(qso)
        }
        model.logbook.onLiveScored = { [weak plugins, weak contest = model.contest] qso, result in
            plugins?.newMultiplier(contestId: contest?.activeId, qso: qso, result: result)
        }
        model.logbook.onQsoEdited = { [weak integrations, weak plugins] old, new in
            integrations?.qsoEdited(old: old, new: new)
            plugins?.qsoEdited(old: old, new: new)
        }
        model.logbook.onQsoDeleted = { [weak integrations, weak plugins] qso in
            integrations?.qsoDeleted(qso)
            plugins?.qsoDeleted(qso)
        }
        model.contest.onFirePlugin = { [weak plugins] event, json in
            plugins?.fire(event, json: json)
        }
        model.contest.onContestClosed = { [weak plugins] id, name in
            plugins?.contestClosed(contestId: id, name: name)
        }
        // The pileup simulator's QSOs change the score and the entry: no plugin hears of that.
        model.contest.onScoreChanged = { [weak plugins, weak logbook = model.logbook] id, score in
            guard logbook?.simulatorActive() != true else { return }
            plugins?.scoreChanged(contestId: id, score: score)
        }
        model.operating.onOperating = { [weak plugins, weak logbook = model.logbook] radio, freqHz, mode in
            guard logbook?.simulatorActive() != true else { return }
            plugins?.operatingChanged(radio: radio, freqHz: freqHz, mode: mode)
        }
        model.dxCluster.onSelfSpotted = { [weak plugins] spot in
            plugins?.selfSpotted(spot)
        }
        online.onClubLogUpload = { [weak plugins] outcome, call, status in
            plugins?.clubLogUpload(outcome: outcome, call: call, status: status)
        }
        online.onScoreReported = { [weak plugins] host, status, accepted, message in
            plugins?.scoreReported(host: host, status: status, accepted: accepted, message: message)
        }
        model.dxCluster.pluginSpot = plugins.spotHandler
        for panel in [model.panel(vfo: 0), model.vfoB] {
            panel.entry.integrations = integrations
        }
        integrations.syncInfo = { [weak logbook = model.logbook] in
            (logbook?.syncStationId, logbook?.reservedServerSerial)
        }
        model.infoStrip.sources.clockOffsetMs = { [weak online] in
            online?.clockOffsetMs
        }

        var services: SettingsServices = model.settings.services
        services.checkClock = chained(services.checkClock) { [weak online] in
            online?.checkClock()
        }
        services.restartBroadcast = chained(services.restartBroadcast) { [weak integrations] in
            integrations?.restartBroadcast()
        }
        services.restartWsjtx = chained(services.restartWsjtx) { [weak integrations] in
            integrations?.restartWsjtx()
        }
        services.restartN1mm = chained(services.restartN1mm) { [weak integrations] in
            integrations?.restartN1mm()
        }
        services.restartAdifUdp = chained(services.restartAdifUdp) { [weak integrations] in
            integrations?.restartAdifUdp()
        }
        services.reportScoreNow = chained(services.reportScoreNow) { [weak online] in
            online?.reportScoreNow()
        }
        model.settings.services = services
    }

    /// An injected port (tests) runs first, then the live one.
    private static func chained(_ injected: @escaping @MainActor () -> Void,
                                _ live: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        {
            injected()
            live()
        }
    }

    /// The end of the start-up (Kotlin `App.kt:140-143`, after the start-up dialog): the services start when enabled
    /// in the Settings, the loops of the online services run, and the quit gets its steps — the integrations close
    /// after the cluster and before the database, a plugin in flight is awaited after it (the last step).
    func activateIntegrations() {
        let integrations: IntegrationsModel = self.integrations
        let online: OnlineServicesModel = self.onlineServices
        let plugins: PluginsModel = self.plugins
        shutdownServices.integrations = { [weak integrations, weak online] in
            online?.shutdown()
            await integrations?.shutdown()
        }
        let drain: @MainActor () async -> Void = shutdownServices.dxClusterDrain
        shutdownServices.dxClusterDrain = { [weak plugins] in
            await drain()
            await plugins?.drain()
        }
        online.start()
        integrations.startBroadcastIfEnabled()
        integrations.startWsjtxIfEnabled()
        integrations.startN1mmIfEnabled()
        integrations.startAdifUdpIfEnabled()
    }
}
