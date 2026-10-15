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
        "help.contestRules", "help.contestCalendar", "help.errorLog", "settings.announcements",
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

    /// The ✓ of the toggles here.
    static func isMiscChecked(_ id: String, app: AppModel) -> Bool {
        switch id {
        case "tools.programLogging":
            return ProgramLog.shared.isEnabled
        case "tools.checkVersionAtStart":
            return app.updates.checksAtStart
        case "settings.announcements":
            return app.announcements.isEnabled
        default:
            return false
        }
    }
}
