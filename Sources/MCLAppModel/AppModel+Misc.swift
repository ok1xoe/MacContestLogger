import Foundation
import MCLCore

extension AppModel {

    /// The program's own services: the error and diagnostics log in `<data>/diagnostics` (the app's
    /// `ProgramLog.shared`; `MCL_DIAGNOSTICS=1` turns program execution logging on from the start) and the update
    /// check, which at start runs only when the user opted in, and the VoiceOver announcements (off by default).
    static func wireMisc(_ model: AppModel, environment: Environment) {
        if let log = environment.programLog {
            log.setDirectory(model.dataDir.appendingPathComponent(ProgramLog.folderName))
            if environment.diagnosticsAtStart {
                log.setEnabled(true)
            }
        }
        model.updates = UpdateCheckModel(config: model.config, status: model.status, network: environment.network,
                                         appVersion: environment.appVersion)
        model.updates.checkAtStartIfEnabled()
        let announcements = AnnouncementsModel(config: model.config, language: model.language,
                                               post: environment.announce)
        model.announcements = announcements
        for entry in [model.entry, model.vfoB.entry] {
            entry.announce = { [weak announcements] event in announcements?.note(event) }
        }
        model.rig.onSplitChanged = { [weak announcements] on in
            announcements?.note(.split(on: on))
        }
    }
}
