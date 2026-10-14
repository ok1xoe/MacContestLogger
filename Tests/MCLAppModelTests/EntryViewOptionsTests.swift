import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// N1MM's Entry window right-click options, the band buttons' and the call's colours and the bearing line.
@MainActor @Suite struct EntryViewOptionsTests {

    @Test func sectionsBandsClockAndClickArePersisted() async throws {
        let app = try await TestApp.make()
        let entry: EntryModel = app.model.entry
        #expect(EntrySection.allCases.allSatisfy { entry.isShown($0) })
        #expect(!entry.showsUtcClock)
        #expect(entry.bandButtonsClick)
        entry.setShown(.functionKeys, false)
        entry.setShown(.bandButtons, false)
        entry.setShown(.functionKeys, false)
        #expect(!entry.isShown(.functionKeys))
        entry.setShowsBand(.m160, false)
        #expect(!entry.showsBand(.m160))
        #expect(entry.showsBand(.m20))
        entry.showsUtcClock = true
        entry.bandButtonsClick = false
        entry.showsUserInformation = false
        let saved: AppConfig = await app.savedConfigFlushed()
        #expect(saved.entryHiddenSections == ["bandButtons", "functionKeys"])
        #expect(saved.entryHiddenBands == ["160m"])
        #expect(saved.entryShowUtcClock)
        #expect(!saved.entryBandButtonsClick)
        #expect(!saved.callHistoryShowUserInfo)
        entry.setShown(.bandButtons, true)
        #expect(app.model.config.config.entryHiddenSections == ["functionKeys"])
    }

    private func type(_ entry: EntryModel, _ call: String, zone: String, kHz: String = "14025") {
        entry.setFrequency(kHz)
        entry.callChanged(call)
        entry.editContestField("zone", zone)
    }

    @Test func bandButtonsAndTheCallShowTheCallsStatus() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.model.logbook.settle()
        let entry: EntryModel = app.model.entry
        type(entry, "DL1ABC", zone: "14")
        #expect(entry.callStatus == .dupe)
        #expect(entry.bandStatuses[.m20] == .dupe)
        #expect(entry.bandStatuses[.m40] == .doubleMultiplier)
        entry.wipe()
        #expect(entry.bandStatuses.isEmpty)
        #expect(entry.callStatus == nil)
        type(entry, "OK1AA", zone: "14")
        #expect(entry.callStatus == .multiplier)
        entry.wipe()
        type(entry, "DL2ABC", zone: "14")
        #expect(entry.callStatus == .newQso)
        #expect(entry.bandStatuses[.m20] == .newQso)
        // Hidden band buttons compute nothing.
        entry.setShown(.bandButtons, false)
        #expect(entry.bandStatuses.isEmpty)
    }

    @Test func freeLoggingHasNoCallColours() async throws {
        let app = try await TestApp.make()
        let entry: EntryModel = app.model.entry
        entry.callChanged("DL1ABC")
        #expect(entry.callStatus == nil)
        #expect(entry.bandStatuses.isEmpty)
    }

    @Test func bearingLineNeedsACountryAndThePosition() async throws {
        let app = try await TestApp.make()
        app.model.entry.callChanged("DL1ABC")
        // The fixture's countries have no coordinates: the country alone.
        #expect(app.model.entry.bearingLine == "Germany")
        app.model.entry.callChanged("")
        #expect(app.model.entry.bearingLine == nil)
        #expect(InfoLines.bearing(nil) == nil)
        #expect(InfoLines.countryAndBearing(nil) == nil)
        let info = CallsignInfo(prefix: "GI", entityName: "Northern Ireland", continent: "EU", cqZone: 14,
                                shortPathDeg: 51, longPathDeg: 231, distanceKm: 4847, distanceMiles: 3012,
                                sunrise: nil, sunset: nil, dxLocalTime: nil, dxDayOfWeek: nil)
        #expect(InfoLines.bearing(info) == "SP 51° LP 231° · 4847 km")
        #expect(InfoLines.countryAndBearing(info) == "Northern Ireland · SP 51° LP 231° · 4847 km")
    }

    @Test func callBandStatusFromMultipliers() {
        #expect(CallBandStatus(dupe: true, newMultipliers: 2) == .dupe)
        #expect(CallBandStatus(dupe: false, newMultipliers: 3) == .doubleMultiplier)
        #expect(CallBandStatus(dupe: false, newMultipliers: 1) == .multiplier)
        #expect(CallBandStatus(dupe: false, newMultipliers: 0) == .newQso)
    }
}
