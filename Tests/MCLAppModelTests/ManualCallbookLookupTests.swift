import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The lookups the operator asks for: the entry window's button (preferred service, no mode filter, no debounce), the
/// log and band map menus with their result window. Scripted HTTP only; nothing reaches a network.
@MainActor @Suite struct ManualCallbookLookupTests {

    private static func make(hamQth: Bool = true, qrz: Bool = true, preferred: String = "hamqth",
                             inert: Bool = false) async throws -> SpotApp {
        try await SpotApp.make(configure: { config, _ in
            CallbookModelTests.credentials(&config, hamQth: hamQth, qrz: qrz)
            config.preferredCallbook = preferred
            // The automatic lookup would skip these modes; the manual one must not.
            config.hamQth.callModes = ["DIGI"]
            config.qrz.callModes = ["DIGI"]
        }, adjust: { environment in
            if inert {
                environment.network = NetworkPorts.inert
            }
        })
    }

    @Test func theEntryButtonUsesThePreferredServiceAndTheCallbookLine() async throws {
        let spot = try await Self.make(preferred: "qrz")
        spot.http.qrz(call: "OK1ABC", grid: "JN89", name: "Jan", cq: "15", itu: "28")
        let callbook: CallbookModel = spot.model.callbook
        #expect(callbook.preferredService == .qrz)
        callbook.lookupNow(" ok1abc ", service: callbook.preferredService, typedCall: { "OK1ABC" })
        #expect(callbook.entryLookup?.state == .loading)
        await callbook.settle()
        let expected = HamQthRecord(grid: "JN89", name: "Jan", cqZone: "15", ituZone: "28")
        #expect(callbook.callbookRecord == CallbookHit(call: "OK1ABC", record: expected))
        #expect(callbook.entryLookup == nil)
        #expect(spot.http.urls.allSatisfy { $0.contains("qrz.com") })
        #expect(callbook.record(for: "OK1ABC") == expected)
    }

    @Test func aMissingCallShowsWhyOnTheEntryLine() async throws {
        let spot = try await Self.make()
        spot.http.route("hamqth.com/xml.php?u=", "<HamQTH><session><session_id>s1</session_id></session></HamQTH>")
        spot.http.route("hamqth.com/xml.php?id=s1", "<HamQTH><session><error>Callsign not found</error></session></HamQTH>")
        let callbook: CallbookModel = spot.model.callbook
        callbook.lookupNow("OK9ZZZ", service: .hamQth, typedCall: { "OK9ZZZ" })
        await callbook.settle()
        #expect(callbook.callbookRecord == nil)
        #expect(callbook.entryLookup == ManualLookupResult(call: "OK9ZZZ", service: .hamQth, state: .notFound))
        // The call changed meanwhile: the late answer is dropped.
        callbook.lookupNow("OK9ZZZ", service: .hamQth, typedCall: { "OK1AAA" })
        await callbook.settle()
        #expect(callbook.callbookRecord == nil)
    }

    @Test func badPasswordNetworkErrorAndNoCredentialsAreTexts() async throws {
        let spot = try await Self.make(qrz: false)
        let callbook: CallbookModel = spot.model.callbook
        spot.http.route("hamqth.com/xml.php?u=", "<HamQTH><session><error>Wrong user name or password</error></session></HamQTH>")
        callbook.lookupInWindow("OK1ABC", service: .hamQth)
        await callbook.settle()
        #expect(callbook.windowLookup?.state == .badCredentials("Wrong user name or password"))
        #expect(callbook.windowLookup?.problem == ContestMessage("Chybné přihlášení (%s)",
                                                                .string("Wrong user name or password")))
        // QRZ.com has no credentials here: nothing is asked.
        let asked: Int = spot.http.urls.count
        callbook.lookupInWindow("OK1ABC", service: .qrz)
        await callbook.settle()
        #expect(callbook.windowLookup?.state == .notConfigured)
        #expect(spot.http.urls.count == asked)
        #expect(!callbook.isConfigured(.qrz) && callbook.isConfigured(.hamQth))
        // No route = the request fails.
        let offline = try await Self.make()
        offline.model.callbook.lookupInWindow("OK1ABC", service: .qrz)
        await offline.model.callbook.settle()
        #expect(offline.model.callbook.windowLookup?.state == .networkError("no route"))
    }

    @Test func theResultWindowGetsTheRecordAndOpensThePage() async throws {
        let spot = try await Self.make()
        spot.http.hamQth(call: "DL1ABC", grid: "JO62", name: "Hans", cq: "14", itu: "28")
        let callbook: CallbookModel = spot.model.callbook
        var shown = 0
        callbook.showLookupWindow = { shown += 1 }
        callbook.lookupInWindow("dl1abc", service: .hamQth)
        #expect(shown == 1)
        #expect(callbook.windowLookup?.state == .loading)
        await callbook.settle()
        let result: ManualLookupResult = try #require(callbook.windowLookup)
        #expect(result.record == HamQthRecord(grid: "JO62", name: "Hans", cqZone: "14", ituZone: "28"))
        callbook.openOnWeb(result)
        callbook.openOnWeb(ManualLookupResult(call: "W1AW", service: .qrz, state: .notFound))
        await eventually("pages") { spot.opener.urls.count == 2 }
        #expect(spot.opener.urls == ["https://www.hamqth.com/DL1ABC", "https://www.qrz.com/db/W1AW"])
    }

    @Test func inertNetworkReportsDisabled() async throws {
        let spot = try await Self.make(inert: true)
        let callbook: CallbookModel = spot.model.callbook
        callbook.lookupInWindow("OK1ABC", service: .hamQth)
        await callbook.settle()
        #expect(callbook.windowLookup?.state == .networkDisabled)
        #expect(spot.http.urls.isEmpty)
    }

    @Test func theBandmapMenuLooksUpOnlyConfiguredServices() async throws {
        let spot = try await Self.make(qrz: false)
        spot.http.hamQth(call: "DL1ABC", grid: "JO62")
        let bandmap: BandmapModel = spot.model.bandmap
        #expect(bandmap.canLookup(on: .hamQth))
        #expect(!bandmap.canLookup(on: .qrz))
        let target: DxSpot = BandmapModelTests.spot("DL1ABC", 14_100_000)
        bandmap.lookup(target, on: .qrz)
        #expect(spot.model.callbook.windowLookup == nil)
        bandmap.lookup(target, on: .hamQth)
        await spot.model.callbook.settle()
        #expect(spot.model.callbook.windowLookup?.record?.grid == "JO62")
    }

    @Test func theLogMenuOffersBothServicesGreyedWithoutCredentials() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "W1AW", zone: "5")
        await app.model.logbook.settle()
        let id: Int64 = try #require(app.model.logbook.rows.first { $0.call == "W1AW" }?.id)
        var asked: [String] = []
        let table = LogTableModel(logbook: app.model.logbook, windows: app.model.windows, status: app.model.status,
                                  lookupCall: { call, service in asked.append(call + "@" + service.rawValue) },
                                  isConfigured: { $0 == .hamQth })
        let items: [LogTableModel.LookupItem] = table.lookupItems(forRow: id)
        #expect(items.map(\.title) == [ContestMessage("Dohledat na %s", .string("HamQTH")),
                                       ContestMessage("Dohledat na %s", .string("QRZ.com"))])
        #expect(items.map(\.isEnabled) == [true, false])
        table.perform(items[0])
        table.perform(items[1])
        #expect(asked == ["W1AW@hamqth"])
        #expect(table.lookupItems(forRow: nil).isEmpty)
    }
}
