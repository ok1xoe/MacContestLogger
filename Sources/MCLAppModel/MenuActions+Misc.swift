import Foundation
import MCLCore

/// The N1MM View, Tools and Help items of the program itself: the call's QRZ.com / Google page, the imported
/// country list, program execution logging and the error log, the update check, the contest's rules and the
/// WA7BNM contest calendar. Every outward call is the user's click (the update check at start is opt-in).
extension MenuActions {

    /// WA7BNM's contest calendar.
    public static let contestCalendarUrl = "https://www.contestcalendar.com/"

    /// The ids handled here.
    static let miscIds: Set<String> = [
        "view.qrz", "view.google", "tools.importCountryFile", "tools.removeCountryFile", "tools.programLogging",
        "tools.diagnosticsFolder", "tools.checkVersion", "tools.checkVersionAtStart", "help.checkUpdates",
        "help.contestRules", "help.contestCalendar", "help.errorLog", "settings.announcements", "tools.tuneBeacon",
        "settings.autoSend", "settings.grabFocus", "settings.snapWindows",
    ]

    /// Runs one of `miscIds`; what the app layer must do is returned.
    static func performMisc(_ id: String, app: AppModel) -> Request? {
        switch id {
        case "view.qrz", "view.google":
            let call: String = (app.activeEntry ?? app.entry).form.call
            guard !CallbookPolicy.key(call).isEmpty else {
                app.status.show("Nejdřív napiš volačku")
                return nil
            }
            if id == "view.qrz" {
                app.callbook.openQrz(call)
            } else {
                app.callbook.openGoogle(call)
            }
        case "tools.importCountryFile":
            return .openCountryFile
        case "tools.tuneBeacon":
            tuneBeacon(app: app, now: Date())
        case "settings.autoSend":
            promptAutoSend(app: app)
        case "settings.grabFocus":
            toggleWindowSetup(.grabFocusOnTune, app: app, on: "Ladění rádia převezme fokus od jiných aplikací",
                              off: "Ladění rádia fokus nepřevezme")
        case "settings.snapWindows":
            toggleWindowSetup(.snapWindows, app: app, on: "Okna se přichytávají k okrajům",
                              off: "Okna se nepřichytávají")
        case "tools.removeCountryFile":
            app.dataTools.removeCountryFile()
        case "tools.programLogging":
            let on: Bool = !ProgramLog.shared.isEnabled
            ProgramLog.shared.setEnabled(on)
            app.status.show(on ? "Logování běhu programu zapnuto (složka diagnostics)" : "Logování běhu programu vypnuto")
        case "tools.diagnosticsFolder":
            let dir: URL = app.dataDir.appendingPathComponent(ProgramLog.folderName)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return .openDataFolder(dir)
        case "tools.checkVersion", "help.checkUpdates":
            app.updates.checkNow()
        case "tools.checkVersionAtStart":
            app.updates.checksAtStart.toggle()
        case "help.contestRules":
            guard app.contest.isActive else {
                app.status.show("Pravidla závodu: není aktivní závod")
                return nil
            }
            guard let url = NewContestModel.rulesUrl(of: app.contest.definition) else {
                app.status.show("Definice závodu nemá odkaz na pravidla")
                return nil
            }
            app.callbook.openUrl(url.absoluteString)
        case "settings.announcements":
            let on: Bool = !app.announcements.isEnabled
            app.announcements.isEnabled = on
            app.status.show(on ? "Hlášení pro nevidomé zapnuta (VoiceOver)" : "Hlášení pro nevidomé vypnuta")
        case "help.contestCalendar":
            app.callbook.openUrl(contestCalendarUrl)
        case "help.errorLog":
            guard let file = ProgramLog.shared.ensureErrorFile() else {
                app.status.show("Chybový log není k dispozici")
                return nil
            }
            return .openFile(file)
        default:
            break
        }
        return nil
    }

    /// N1MM Tools „Tune to beacon for this band": the active entry window (and the rig) goes to the NCDXF/IARU
    /// beacon frequency of its band in CW; the status line names the beacon sending now and its bearing from the
    /// station's locator. Only on 20, 17, 15, 12 and 10 m.
    static func tuneBeacon(app: AppModel, now: Date) {
        let entry: EntryModel = app.activeEntry ?? app.entry
        let tuned: Int64 = app.rig.tuning.tunedFreqHz
        let hz: Int64 = tuned > 0 ? tuned : entry.form.freqHz
        guard let target = NcdxfBeacons.beaconFrequency(forBandOf: hz) else {
            app.status.show("Majáky NCDXF jsou jen na 20, 17, 15, 12 a 10 m")
            return
        }
        entry.qsy(toKHz: Double(target) / 1000, mode: .cw)
        guard let beacon = NcdxfBeacons.transmitting(freqHz: target, at: now) else { return }
        if let bearing = NcdxfBeacons.bearing(from: app.config.config.station.gridSquare, to: beacon) {
            app.status.show("Maják NCDXF: vysílá %s (%s), azimut %s°", .string(beacon.call),
                            .string(beacon.location), .int(bearing))
        } else {
            app.status.show("Maják NCDXF: vysílá %s (%s)", .string(beacon.call), .string(beacon.location))
        }
    }

    /// N1MM Config „CW/PH AutoSend Threshold" (Ctrl+Shift+M in N1MM): the threshold asked for and saved (0 = off).
    static func promptAutoSend(app: AppModel) {
        let config: ConfigModel = app.config
        let status: StatusModel = app.status
        app.dialogs.prompt(
            title: ContestMessage("AutoSend volačky (CW)"),
            hint: ContestMessage("Počet znaků za poslední číslicí volačky, po kterém se v Run začne vysílat (0 = vypnuto)"),
            initial: String(config.config.autoSendThreshold)) { text in
            applyAutoSend(text, config: config, status: status)
        }
    }

    /// The prompt's answer: 0–20 is saved, anything else refused.
    static func applyAutoSend(_ text: String, config: ConfigModel, status: StatusModel) {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), (0...20).contains(value) else {
            status.show("Neplatný práh AutoSend (0–20)")
            return
        }
        config.config.autoSendThreshold = value
        config.save(failureKey: "Uložení nastavení selhalo: %s")
        if value == 0 {
            status.show("AutoSend vypnut")
        } else {
            status.show("AutoSend: vysílání volačky po %s znacích za číslicí", .int(value))
        }
    }

    /// The ✓ of the toggles here.
    static func isMiscChecked(_ id: String, app: AppModel) -> Bool {
        switch id {
        case "tools.programLogging":
            return ProgramLog.shared.isEnabled
        case "tools.checkVersionAtStart":
            return app.updates.checksAtStart
        case "settings.announcements":
            return app.announcements.isEnabled
        case "settings.grabFocus":
            return app.config.config.window.flag(.grabFocusOnTune)
        case "settings.snapWindows":
            return app.config.config.window.flag(.snapWindows)
        default:
            return false
        }
    }

    /// A window behaviour switch flipped and saved, with its status.
    static func toggleWindowSetup(_ key: WindowSetup.Key, app: AppModel, on: String, off: String) {
        var setup: WindowSetup = app.config.config.window
        let next: Bool = !setup.flag(key)
        setup.set(key, flag: next)
        app.config.config.window = setup
        app.config.save(failureKey: "Uložení nastavení selhalo: %s")
        app.status.show(next ? on : off)
    }
}
