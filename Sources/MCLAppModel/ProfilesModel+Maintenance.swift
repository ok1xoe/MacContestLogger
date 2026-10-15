import Foundation
import MCLCore

/// The whole-configuration tools beside the profiles: N1MM's daily settings backups and their restore, „Clear INI
/// file settings" (a reset to the defaults after a backup) and the saved window layouts (Tools › Save / Restore
/// Window Positions, per operator). The disk work runs on `BlockingQueue`; a restore or a reset goes through the
/// same effects as a profile load (`ConfigEffectPlan.profileLoad`).
extension ProfilesModel {

    // MARK: - backups

    /// Reads the backups off the main thread.
    public func refreshBackups() async {
        let backups = ConfigBackups(dataDir: dataDir)
        let listed: [ConfigBackups.Entry]? = try? await BlockingQueue.run { try backups.list() }
        self.backups = listed ?? []
    }

    /// The day's backup of `config.json` (at start-up; nothing when today's exists).
    nonisolated static func dailyBackup(dataDir: URL, now: Date) {
        let backups = ConfigBackups(dataDir: dataDir)
        _ = try? backups.daily(configFile: dataDir.appendingPathComponent("config.json"), now: now)
    }

    /// Restores a backup: the current settings are backed up first, then the backup's settings replace them —
    /// except the databases, the contest data, the windows and their places (`ConfigBackups.preserving`).
    public func restoreBackup(_ entry: ConfigBackups.Entry, now: Date = Date()) async {
        let backups = ConfigBackups(dataDir: dataDir)
        let read: AppConfig
        do {
            read = try await BlockingQueue.run { try backups.read(entry) }
        } catch {
            status.show("Zálohu nastavení nejde načíst: %s", .string(ErrorText.message(error)))
            return
        }
        guard await replaceConfig(read, keepStation: false, now: now) else { return }
        status.show("Nastavení obnoveno ze zálohy %s — rig a síťová spojení připoj znovu", .string(entry.label))
    }

    /// N1MM „Clear INI file settings": after a backup, every setting goes back to its default — except the
    /// station, the databases, the contest data, the windows and their places.
    public func resetToDefaults(now: Date = Date()) async {
        var defaults = AppConfig()
        defaults.contestDataDir = config.config.contestDataDir
        guard await replaceConfig(defaults, keepStation: true, now: now) else { return }
        status.show("Nastavení vráceno na výchozí (předchozí je v zálohách) — rig a síťová spojení připoj znovu")
    }

    /// Backs the live configuration up, then makes `next` (with the kept parts of the live one) the configuration
    /// through the profile-load effects. `false` = the backup failed and nothing changed.
    private func replaceConfig(_ next: AppConfig, keepStation: Bool, now: Date) async -> Bool {
        let backups = ConfigBackups(dataDir: dataDir)
        let snapshot: AppConfig = config.config
        do {
            _ = try await BlockingQueue.run { try backups.backupNow(snapshot, now: now) }
        } catch {
            status.show("Záloha nastavení selhala, nic se nezměnilo: %s", .string(ErrorText.message(error)))
            return false
        }
        let base: AppConfig = config.config
        let merged: AppConfig = ConfigBackups.preserving(base, into: next, station: keepStation)
        let application = ConfigApplication(config: merged, base: base) { live in
            ConfigBackups.preserving(live, into: next, station: keepStation)
        }
        let plan: [ConfigEffect] = ConfigEffectPlan.profileLoad(name: "", replacesAntennas: true).filter {
            if case .profileLoaded = $0 { return false }
            return true
        }
        let applied: Bool = await settings.applyConfigChanges(plan, application)
        await refreshBackups()
        return applied
    }

    // MARK: - window layouts

    /// The saved layout names (sorted).
    public func layoutNames() async -> [String] {
        let layouts = WindowLayouts(dataDir: dataDir)
        return (try? await BlockingQueue.run { try layouts.names() }) ?? []
    }

    /// N1MM „Save Window Positions": the open windows and their places under `name` (the operator's call by
    /// default).
    public func saveLayout(name: String) async {
        guard WindowLayouts.fileName(name) != nil else { return }
        let layouts = WindowLayouts(dataDir: dataDir)
        let layout: WindowLayout = .of(config.config)
        let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await BlockingQueue.run { try layouts.save(layout, name: trimmed) }
            status.show("Rozložení oken „%s“ uloženo", .string(trimmed))
        } catch {
            status.show("Rozložení oken nejde uložit: %s", .string(ErrorText.message(error)))
        }
    }

    /// N1MM „Restore Window Positions": the layout's places go into the configuration (the open windows move there
    /// through `WindowGeometryStore.layoutRestored`); returns the window ids the layout opens, `nil` = no such layout.
    public func restoreLayout(name: String) async -> [String]? {
        let layouts = WindowLayouts(dataDir: dataDir)
        let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let layout: WindowLayout?
        do {
            layout = try await BlockingQueue.run { try layouts.load(name: trimmed) }
        } catch {
            status.show("Rozložení oken nejde načíst: %s", .string(ErrorText.message(error)))
            return nil
        }
        guard let layout else {
            status.show("Rozložení oken „%s“ neexistuje", .string(trimmed))
            return nil
        }
        let next: AppConfig = layout.applied(to: config.config)
        config.config.windowGeometry = next.windowGeometry
        config.save(failureKey: "Uložení geometrie okna selhalo (%s)")
        NotificationCenter.default.post(name: WindowGeometryStore.layoutRestored, object: nil)
        status.show("Rozložení oken „%s“ obnoveno", .string(trimmed))
        return layout.openWindows
    }
}
