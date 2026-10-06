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
        spot.http.route("hamqth.com/xml.php?u=",
                        "<HamQTH><session><error>Wrong user name or password</error></session></HamQTH>")
        callbook.lookupNow("OK1ABC", service: .hamQth, typedCall: { "OK1ABC" })
        await callbook.settle()
        #expect(callbook.entryLookup?.state == .badCredentials("Wrong user name or password"))
        #expect(callbook.entryLookup?.problem == ContestMessage("Chybné přihlášení (%s)",
                                                               .string("Wrong user name or password")))
        // QRZ.com has no credentials here: nothing is asked.
        let asked: Int = spot.http.urls.count
        callbook.lookupNow("OK1ABC", service: .qrz, typedCall: { "OK1ABC" })
        await callbook.settle()
        #expect(callbook.entryLookup?.state == .notConfigured)
        #expect(spot.http.urls.count == asked)
        #expect(!callbook.isConfigured(.qrz) && callbook.isConfigured(.hamQth))
        // No route = the request fails.
        let offline = try await Self.make()
        offline.model.callbook.lookupNow("OK1ABC", service: .qrz, typedCall: { "OK1ABC" })
        await offline.model.callbook.settle()
        #expect(offline.model.callbook.entryLookup?.state == .networkError("no route"))
    }

    @Test func inertNetworkReportsDisabled() async throws {
        let spot = try await Self.make(inert: true)
        let callbook: CallbookModel = spot.model.callbook
        callbook.lookupNow("OK1ABC", service: .hamQth, typedCall: { "OK1ABC" })
        await callbook.settle()
        #expect(callbook.entryLookup?.state == .networkDisabled)
        #expect(spot.http.urls.isEmpty)
    }

    @Test func theBandmapMenuOpensTheCallsPageWithoutCredentials() async throws {
        let spot = try await Self.make(hamQth: false, qrz: false)
        let bandmap: BandmapModel = spot.model.bandmap
        let target: DxSpot = BandmapModelTests.spot("DL1ABC", 14_100_000)
        #expect(bandmap.canLookup(target))
        #expect(!bandmap.canLookup(BandmapModelTests.spot(" ", 14_100_000)))
        bandmap.lookup(target, on: .qrz)
        bandmap.lookup(target, on: .hamQth)
        await eventually("pages") { spot.opener.urls.count == 2 }
        #expect(spot.opener.urls == ["https://www.qrz.com/db/DL1ABC", "https://www.hamqth.com/DL1ABC"])
        #expect(spot.http.urls.isEmpty)
    }

    @Test func theLogMenuOpensTheCallsPage() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "W1AW", zone: "5")
        await app.model.logbook.settle()
        let id: Int64 = try #require(app.model.logbook.rows.first { $0.call == "W1AW" }?.id)
        var opened: [String] = []
        let table = LogTableModel(logbook: app.model.logbook, windows: app.model.windows, status: app.model.status,
                                  openCallPage: { call, service in opened.append(call + "@" + service.rawValue) })
        let items: [LogTableModel.LookupItem] = table.lookupItems(forRow: id)
        #expect(items.map(\.title) == [ContestMessage("Dohledat na %s", .string("HamQTH")),
                                       ContestMessage("Dohledat na %s", .string("QRZ.com"))])
        #expect(items.map(\.isEnabled) == [true, true])
        table.perform(items[0])
        table.perform(items[1])
        #expect(opened == ["W1AW@hamqth", "W1AW@qrz"])
        #expect(table.lookupItems(forRow: nil).isEmpty)
    }

    @Test func theMenuOpensTheRealPagesOfTheModel() async throws {
        let spot = try await Self.make(hamQth: false, qrz: false)
        spot.model.callbook.openPage(" ok1abc ", on: .hamQth)
        spot.model.callbook.openPage("ok1abc", on: .qrz)
        spot.model.callbook.openPage("  ", on: .qrz)
        await spot.model.callbook.settle()
        await eventually("pages") { spot.opener.urls.count == 2 }
        #expect(spot.opener.urls == ["https://www.hamqth.com/OK1ABC", "https://www.qrz.com/db/OK1ABC"])
    }
}
