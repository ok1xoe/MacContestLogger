import Foundation
import MCLCore

/// What a plan of `ConfigEffectPlan` applies: the configuration it writes and makes live, the language loaded for
/// it and the band data of the draft.
struct ConfigApplication {

    /// `draft.writeBandData()`: the directory (`contestDataDir.trim()` of the draft, the **new** one; blank = the
    /// default directory) and the tables.
    struct BandData {
        let dir: String
        let segments: [BandPlanFile.Segment]
        let table: DigiFreqFile.Table
    }

    /// Written by `.saveConfig`, made live by `.applyConfig`.
    let config: AppConfig
    /// The live configuration `config` was built from.
    let base: AppConfig
    /// Builds the value again over the live configuration when that changed while the file was written (an ESM
    /// toggle, a window flag): the draft's fields win, the others are kept, and the result is written again.
    let rebase: @MainActor (AppConfig) -> AppConfig?
    /// `.switchLanguage` (commit only): the language loaded before the write.
    var translator: Translator?
    /// `.writeBandData` (commit only).
    var bandData: BandData?
    /// „Uložit a připojit" (commit only).
    var reconnectRig: Bool = false
    /// `rigDiffers` over the old configuration (commit only).
    var rigChanged: Bool = false
}

extension SettingsModel {

    /// OK and „Uložit a připojit" (`commitConfigurer(state, draft, reconnectRig)`, `CD:554-614`), **atomic**:
    /// the eight predicates over the old configuration, the draft applied to a copy, the new language
    /// loaded off the main thread, then the plan — the copy is written first and becomes live (with the language)
    /// only after the write succeeded. A failed write shows `tr("Uložení nastavení selhalo: %s")` in the old
    /// language, changes nothing and returns `false` (the window stays open). `true` = saved; the view closes the
    /// window.
    public func commit(reconnectRig: Bool) async -> Bool {
        guard isOpen, let draft, !isSaving else { return false }
        isSaving = true
        // The end of the commit (the flag, a close asked meanwhile) belongs to the task itself, so whoever awaits
        // `commitTask` (shutdown, tests) sees the settled state.
        let task = Task { () -> Bool in
            let saved: Bool = await self.runCommit(draft, reconnectRig: reconnectRig)
            self.isSaving = false
            if self.closeWhenSaved {
                self.cancel()
            }
            return saved
        }
        commitTask = task
        return await task.value
    }

    /// OK: `commit`, and the window closes after a successful save.
    @discardableResult
    public func confirm(reconnectRig: Bool = false) async -> Bool {
        let saved: Bool = await commit(reconnectRig: reconnectRig)
        if saved {
            cancel()
        }
        return saved
    }

    /// „Použít": the whole commit of OK (same validation, write and effects); the window stays open on the same
    /// tab and the draft is read again from the committed configuration. A failed write keeps the draft and the
    /// window like OK. Nothing happens without changes.
    @discardableResult
    public func apply() async -> Bool {
        guard hasChanges, let committed = draft else { return false }
        let saved: Bool = await commit(reconnectRig: false)
        if saved {
            await rereadDraft(committed: committed)
        }
        return saved
    }

    /// „Odeslat teď" in Score reporting (`commitConfigurer(state, draft); state.reportScoreNow()`): the
    /// whole commit, then the report through its port whatever the commit's result; the window stays open.
    public func sendScoreNow() async {
        if let committed = draft, await commit(reconnectRig: false) {
            await rereadDraft(committed: committed)
        }
        services.reportScoreNow()
    }

    private func runCommit(_ draft: ConfigurerDraft, reconnectRig: Bool) async -> Bool {
        // Kotlin `I18n.use(language)` reads the language file inside `applyTo`; here it is read before the write
        // (off the main thread) and switched to only after the write succeeded.
        // A close asked meanwhile (`cancel()` while saving) waits for the end of the commit — an accepted OK is
        // never dropped (Kotlin's commit is synchronous).
        let translator: Translator = await language.prepare(draft.language)
        let old: AppConfig = config.config
        let changes = ConfigChanges(
            cluster: draft.clusterDiffers(old.cluster), broadcast: draft.broadcastDiffers(old.broadcast),
            wsjtx: draft.wsjtxDiffers(old.wsjtx), n1mm: draft.n1mmDiffers(old.n1mmRecv),
            adifUdp: draft.adifUdpDiffers(old.adifUdp),
            contestDir: draft.contestDirDiffers(old, defaultDir: defaultContestDataDir),
            rig: draft.rigDiffers(old.rig), scoringStation: draft.scoringStationDiffers(old.station))
        let instant = JavaInstant(date: now())
        // Kotlin decides the reconnect at the end of the commit (`CD:609`); the plan gets the step whenever it may
        // apply and `.reconnectCat` decides with the CAT state of that moment (the plan waits before it).
        let candidate: Bool = reconnectRig || changes.rig
        let plan: [ConfigEffect] = ConfigEffectPlan.commit(changes, reconnectRig: reconnectRig,
                                                           catConnected: candidate)
        let band = draft.bandData()
        var application = ConfigApplication(config: draft.applied(to: old, now: instant), base: old) { live in
            draft.applied(to: live, now: instant)
        }
        application.translator = translator
        application.bandData = ConfigApplication.BandData(dir: draft.bandDataDir, segments: band.segments,
                                                          table: band.table)
        application.reconnectRig = reconnectRig
        application.rigChanged = changes.rig
        return await applyConfigChanges(plan, application)
    }

    /// Runs a plan of `ConfigEffectPlan` (the Settings commit or a profile load) in its order: what the app already
    /// has runs here, the effects of the other subsystems go to `services` at the same place.
    ///
    /// The effects run back to back on the main actor; only the write, the contest-data reload, the band-data write
    /// and the band-data reload wait (their I/O is off the main thread). Because of those waits `.reconnectCat`
    /// decides with the CAT state when it runs: `reconnectRig || (rigChanged && catConnected)` (`CD:609`).
    ///
    /// - Returns: `false` when the write failed (the failure status shown, no other effect run).
    @discardableResult
    func applyConfigChanges(_ plan: [ConfigEffect], _ application: ConfigApplication) async -> Bool {
        for effect in plan {
            services.trace(effect)
            switch effect {
            case .saveConfig(let onFailure):
                do {
                    try await config.saveNow(application.config)
                } catch {
                    showSaveFailure(onFailure, ErrorText.message(error))
                    return false
                }
            case .applyConfig:
                adopt(application)
            case .switchLanguage:
                if let translator = application.translator {
                    language.apply(translator)
                }
            case .resetAntennaIndex:
                services.resetAntennaIndex()
            case .saveInner(let inner):
                runSaveInner(inner)
            case .statusSaved:
                status.show(SettingsTexts.saved)
            case .cwSpeed:
                services.cwSpeed()
            case .esm:
                operating.syncEsmFromConfig()
            case .runMode:
                operating.syncRunModeFromConfig()
            case .radioMode:
                services.radioMode()
            case .modeSettings:
                services.modeSettings()
            case .checkClock:
                services.checkClock()
            case .keyBindings:
                // The entry reads `config.keyBindings` live (`KeyBindings(config.config.keyBindings)` per key press).
                break
            case .configRevision:
                config.bumpRevision()
            case .spotBuffer:
                services.spotBuffer()
            case .minSkimmers:
                services.minSkimmers()
            case .blacklist:
                services.blacklist()
            case .hamQth:
                services.hamQth()
            case .restartCluster:
                services.restartCluster()
            case .restartBroadcast:
                services.restartBroadcast()
            case .restartWsjtx:
                services.restartWsjtx()
            case .restartN1mm:
                services.restartN1mm()
            case .restartAdifUdp:
                services.restartAdifUdp()
            case .reloadContestData:
                await contest.reloadContestData()
            case .rescore:
                contest.requestRescore()
            case .writeBandData:
                await writeBandData(application.bandData)
            case .reloadBandData:
                await contest.reloadBandData()
            case .reconnectCat:
                let connected: Bool = services.catConnected()
                if application.reconnectRig || (application.rigChanged && connected) {
                    services.reconnectCat(connected)
                }
            case .profileLoaded(let name):
                status.show(SettingsTexts.profileLoaded, .string(name))
            }
        }
        return true
    }

    private func showSaveFailure(_ onFailure: ConfigEffect.SaveFailure, _ message: String) {
        switch onFailure {
        case .abortPlan(status: .settingsSaveFailed):
            status.show(SettingsTexts.saveFailed, .string(message))
        case .abortPlan(status: .profileFailed):
            status.showVerbatim(SettingsTexts.profileFailurePrefix + message)
        }
    }

    /// `.applyConfig`: the written value becomes live. When the live configuration changed during the write, the
    /// value is built again over it and written once more, so neither the change nor the file is lost; a failure
    /// of that write is shown like a failed commit, but the commit has already returned `true` (the window closes):
    /// memory then holds the rebased value and the file the first write, until the next save writes the file again.
    /// When it cannot be built again (a profile that merged over the old configuration but no longer merges over the
    /// live one — not reachable with the shipped schema), the live configuration with the concurrent change stays
    /// and is written again, so memory and file agree; the profile's values are then not live.
    private func adopt(_ application: ConfigApplication) {
        let live: AppConfig = config.config
        guard live != application.base else {
            config.config = application.config
            return
        }
        if let rebased = application.rebase(live) {
            config.config = rebased
        }
        config.save(failureKey: SettingsTexts.saveFailed)
    }

    /// The inner effects of `saveConfig()` (`AS:3730-3736`).
    private func runSaveInner(_ inner: ConfigEffect.SaveInner) {
        switch inner {
        case .dxMyCall:
            services.dxMyCall()
        case .parallelClusters:
            services.parallelClusters()
        case .footswitch:
            services.footswitch()
        case .callData:
            // `reloadScp()` + `reloadCallHistory()`.
            callData.reload()
        }
    }

    /// `runCatching { draft.writeBandData() }.onFailure { statusMessage = tr(…) }` (`CD:606-607`), off the main
    /// thread; the failure overwrites „Nastavení uloženo" and the plan goes on. A blank directory is the default one
    /// (`ContestEnvironment.dataRoot`, as `reloadBandData` reads it) — never relative to the process directory, where
    /// Kotlin's `Path.of("")` would write (a fixed divergence).
    private func writeBandData(_ bandData: ConfigApplication.BandData?) async {
        guard let bandData else { return }
        let dir: URL = ContestEnvironment.dataRoot(configured: bandData.dir, fallback: defaultContestDataDir)
        do {
            try await BlockingQueue.run {
                try BandPlanFile.write(dir, bandData.segments)
                try DigiFreqFile.write(dir, bandData.table)
            }
        } catch {
            status.show(SettingsTexts.bandDataSaveFailed, .string(ErrorText.message(error)))
        }
    }
}
