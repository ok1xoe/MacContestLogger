import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// Program announcements for blind operators: VoiceOver announcements through a recording port (nothing is posted to
/// the system, no audio device). Off by default; the Settings menu item switches them and is saved.
@MainActor @Suite struct AnnouncementsTests {

    final class Posted {
        var texts: [String] = []
    }

    private static func make(on: Bool) async throws -> (app: TestApp, posted: Posted) {
        let posted = Posted()
        let app = try await TestApp.make(configure: { config, _ in config.accessibilityAnnouncements = on },
                                         adjust: { $0.announce = { posted.texts.append($0) } })
        try await app.startCqWwCw()
        app.model.entry.setFrequency("14025")
        return (app, posted)
    }

    @Test func nothingIsAnnouncedByDefault() async throws {
        let (app, posted) = try await Self.make(on: false)
        await app.logContestQso(call: "DL1ABC", zone: "14")
        app.model.entry.callChanged("DL1ABC")
        app.model.entry.submit()
        #expect(app.model.entry.isDupe)
        #expect(posted.texts.isEmpty)
        #expect(!MenuActions.isChecked("settings.announcements", app: app.model))
    }

    @Test func aNewMultiplierAndADupeAreAnnouncedOncePerChange() async throws {
        let (app, posted) = try await Self.make(on: true)
        let entry: EntryModel = app.model.entry
        let language: LanguageModel = app.model.language
        entry.callChanged("DL1ABC")
        entry.editContestField("zone", "14")
        // The call is a new country, then (with the zone) a double multiplier: one announcement per change.
        #expect(posted.texts == [language.tr("Nový násobič"), language.tr("Dvojitý násobič")])
        entry.editContestField("zone", "14")
        #expect(posted.texts.count == 2, "the same status is not repeated")
        entry.submit()
        await entry.settle()
        posted.texts.removeAll()
        entry.callChanged("DL1AB")
        entry.callChanged("DL1ABC")
        #expect(entry.isDupe)
        #expect(posted.texts == [language.tr("Dupe")])
    }

    @Test func aQsoThatCannotBeLoggedIsAnnounced() async throws {
        let (app, posted) = try await Self.make(on: true)
        let entry: EntryModel = app.model.entry
        entry.callChanged("DL1ABC")
        posted.texts.removeAll()
        entry.submit()
        await entry.settle()
        #expect(app.model.logbook.rows.isEmpty)
        #expect(posted.texts == [app.model.language.tr("Neúplná výměna, QSO nezapsáno")])
    }

    @Test func theMenuItemSwitchesAndSavesIt() async throws {
        let (app, posted) = try await Self.make(on: false)
        #expect(MenuActions.perform("settings.announcements", app: app.model) == nil)
        #expect(MenuActions.isChecked("settings.announcements", app: app.model))
        #expect(await app.savedConfigFlushed().accessibilityAnnouncements)
        app.model.announcements.note(.split(on: true))
        app.model.announcements.note(.split(on: false))
        #expect(posted.texts == [app.model.language.tr("Split zapnut"), app.model.language.tr("Split vypnut")])
        _ = MenuActions.perform("settings.announcements", app: app.model)
        app.model.announcements.note(.paperTimeMissing)
        #expect(posted.texts.count == 2)
    }
}
