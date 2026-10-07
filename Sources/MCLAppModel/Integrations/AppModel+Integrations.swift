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
        let pluginWindows = PluginWindowsModel(
            launcher: environment.network.plugins.launchWindowPlugin, dataDir: environment.dataDir,
            windows: model.windows, messages: model.messages, language: model.language, clock: clock,
            now: environment.now, appVersion: environment.appVersion)
        plugins.windowEvents = pluginWindows.router
        pluginWindows.context = pluginContext(model)
        for panel in [model.panel(vfo: 0), model.vfoB] {
            panel.entry.pluginKeyHook = { [weak pluginWindows] combo, pressed in
                pluginWindows?.handleKey(combo, pressed: pressed)
            }
        }
        model.plugins = plugins
        model.pluginWindows = pluginWindows
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

    /// What the window plugins' requests read: the active contest, the logbook, the active entry window, the spots.
    private static func pluginContext(_ model: AppModel) -> PluginHostContext {
        var context = PluginHostContext()
        context.contest = { [weak contest = model.contest] in
            (contest?.activeId, contest?.activeName)
        }
        context.handle = { [weak database = model.database] in
            database?.handle
        }
        context.freshSession = { [weak contest = model.contest] in
            contest?.runtime.freshSession()
        }
        context.bandOrder = { [weak contest = model.contest] in
            contest?.runtime.bandOrder ?? []
        }
        context.rig = { [weak model] in
            guard let model, let entry = model.activeEntry else { return nil }
            return PluginRigState(radio: entry.vfo, freqHz: entry.form.freqHz, mode: entry.form.mode.rawValue,
                                  catConnected: model.rig.catConnected)
        }
        context.spots = { [weak feed = model.spotFeed] in
            feed?.snapshot() ?? []
        }
        context.actions = pluginActions(model)
        return context
    }

    /// The acting requests of window plugins, through the same calls as the operator's own actions.
    private static func pluginActions(_ model: AppModel) -> PluginHostActions {
        var actions = PluginHostActions()
        let noEntry = "no active entry window"
        actions.entryState = { [weak model] in
            guard let entry = model?.activeEntry else { return nil }
            let exchange: [(String, String)] = entry.form.contestExchange.entries.compactMap { item in
                guard let key = item.key else { return nil }
                return (key, item.value ?? "")
            }
            return PluginHostActions.EntryState(call: entry.form.call, exchange: exchange, freqHz: entry.form.freqHz,
                                                mode: entry.form.mode.rawValue, radio: entry.vfo)
        }
        actions.setCall = { [weak model] call in
            model?.activeEntry?.callChanged(call)
        }
        actions.setExchange = { [weak model] values in
            guard let entry = model?.activeEntry else { return Array(values.keys) }
            let known: Set<String> = Set(entry.fields.compactMap(\.id))
            var unknown: [String] = []
            for (id, value) in values.sorted(by: { $0.key < $1.key }) {
                if known.contains(id) {
                    entry.editContestField(id, value)
                } else {
                    unknown.append(id)
                }
            }
            return unknown
        }
        actions.wipe = { [weak model] in
            model?.activeEntry?.wipe()
        }
        actions.log = { [weak model] in
            guard let entry = model?.activeEntry else { return noEntry }
            guard entry.acceptsInput else { return "the entry takes no input now" }
            // A command in the call field would run instead of logging: plugins run commands only through
            // `app.command` and its policy.
            guard !entry.hasCommand else { return "the call field holds a command" }
            entry.submit()
            return nil
        }
        actions.status = { [weak model] text in
            model?.status.showVerbatim(text)
        }
        actions.qsy = { [weak model] hz, mode in
            guard let entry = model?.activeEntry else { return noEntry }
            entry.qsy(toKHz: Double(hz) / 1000, mode: mode ?? entry.form.mode)
            return nil
        }
        actions.setMode = { [weak model] mode in
            guard let entry = model?.activeEntry else { return noEntry }
            entry.setMode(mode)
            return nil
        }
        actions.split = { [weak model] hz in
            guard let entry = model?.activeEntry else { return noEntry }
            entry.runCommand(hz.map { .split(txFreqHz: $0) } ?? .splitOff)
            return nil
        }
        actions.rit = { [weak model] offset in
            guard let entry = model?.activeEntry else { return noEntry }
            entry.runCommand(.rit(offsetHz: offset))
            return nil
        }
        actions.swapVfo = { [weak model] in
            guard let entry = model?.activeEntry else { return noEntry }
            entry.runCommand(.swapVfo)
            return nil
        }
        actions.focusRadio = { [weak model] radio in
            guard let model else { return noEntry }
            model.rig.activateVfo(radio)
            return nil
        }
        actions.addSpot = { [weak model] spot in
            model?.dxCluster.spots.add(spot)
        }
        actions.removeSpot = { [weak model] call, blacklist in
            guard let model else { return false }
            let found: Bool = model.dxCluster.spots.snapshot().contains { $0.dxCall == call }
            if found {
                model.dxCluster.spots.remove(call)
            }
            if blacklist {
                model.blacklist.blacklistCall(call)
            }
            return found
        }
        actions.mark = { [weak model] hz in
            model?.spotNavigation.mark(freqHz: hz)
        }
        actions.blacklist = { [weak model] call in
            model?.blacklist.blacklistCall(call)
        }
        actions.sendSpot = { [weak model] call, hz, comment in
            guard let model else { return "not connected" }
            return model.spotNavigation.spotToCluster(call: call, freqHz: hz, comment: comment)
                ? nil : model.status.message
        }
        actions.stationCall = { [weak model] in
            model?.config.config.station.call ?? ""
        }
        actions.command = { [weak model] text in
            guard let entry = model?.activeEntry else { return noEntry }
            let parsed: CallFieldCommand?
            do throws(JavaArithmeticError) {
                parsed = try CallFieldCommands.parse(text, currentFreqHz: entry.form.freqHz,
                                                    otherVfoHz: entry.otherVfoHz)
            } catch {
                return "not a command"
            }
            guard let command = parsed else { return "not a command" }
            if let refusal = PluginCommandPolicy.refusal(command) {
                return refusal
            }
            entry.runCommand(command)
            return nil
        }
        return actions
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
        let pluginWindows: PluginWindowsModel = self.pluginWindows
        shutdownServices.dxClusterDrain = { [weak plugins, weak pluginWindows] in
            await drain()
            await pluginWindows?.shutdown()
            await plugins?.drain()
        }
        online.start()
        pluginWindows.refreshCatalog()
        integrations.startBroadcastIfEnabled()
        integrations.startWsjtxIfEnabled()
        integrations.startN1mmIfEnabled()
        integrations.startAdifUdpIfEnabled()
    }
}
