import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The callbooks over a scripted HTTP getter (no socket, no name lookup): HamQTH before QRZ.com with the
/// first non-blank value per field, the cache with `EMPTY`, the guard of the entry field's current call, Kotlin's
/// `configured()` gate, the spot prefetch with its field and mode filters, `reload` and the browser pages.
@MainActor @Suite struct CallbookModelTests {

    static func credentials(_ config: inout AppConfig, hamQth: Bool = true, qrz: Bool = true) {
        if hamQth {
            config.hamQth.username = "user"
            config.hamQth.password = "secret"
        }
        if qrz {
            config.qrz.username = "user"
            config.qrz.password = "secret"
        }
    }

    @Test func hamQthComesFirstAndQrzFillsTheBlanks() async throws {
        let spot = try await SpotApp.make { config, _ in Self.credentials(&config) }
        spot.http.hamQth(call: "OK1ABC", grid: "JO70")
        spot.http.qrz(call: "OK1ABC", grid: "JN89", name: "Jan", cq: "15")
        let callbook: CallbookModel = spot.model.callbook
        callbook.lookup(" ok1abc ", typedCall: { "OK1ABC" })
        await callbook.settle()
        let expected = HamQthRecord(grid: "JO70", name: "Jan", cqZone: "15", ituZone: "")
        #expect(callbook.callbookRecord == CallbookHit(call: "OK1ABC", record: expected))
        let urls: [String] = spot.http.urls
        let firstQrz: Int = try #require(urls.firstIndex { $0.contains("qrz.com") })
        #expect(urls[..<firstQrz].allSatisfy { $0.contains("hamqth.com") })
        #expect(firstQrz > 0)
        // A cache hit answers at once, without a request.
        callbook.lookup("OK1ABC", typedCall: { "OK1ABC" })
        await callbook.settle()
        #expect(spot.http.urls.count == urls.count)
        #expect(callbook.record(for: "ok1abc") == expected)
        #expect(callbook.analyzerLookup("OK1ABC") == expected)
    }

    @Test func nothingFoundIsCachedAsEmpty() async throws {
        let spot = try await SpotApp.make { config, _ in Self.credentials(&config, qrz: false) }
        spot.http.route("hamqth.com/xml.php?u=", "<HamQTH><session><session_id>s1</session_id></session></HamQTH>")
        let callbook: CallbookModel = spot.model.callbook
        callbook.lookup("OK9ZZZ", typedCall: { "OK9ZZZ" })
        await callbook.settle()
        #expect(callbook.callbookRecord == nil)
        #expect(callbook.cache.record("OK9ZZZ") == .empty)
        #expect(callbook.record(for: "OK9ZZZ") == nil)
        let asked: Int = spot.http.urls.count
        callbook.lookup("OK9ZZZ", typedCall: { "OK9ZZZ" })
        await callbook.settle()
        #expect(spot.http.urls.count == asked)
    }

    @Test func aLateResultForAnotherCallIsDropped() async throws {
        let spot = try await SpotApp.make { config, _ in Self.credentials(&config, qrz: false) }
        spot.http.hamQth(call: "OK1ABC", grid: "JO70")
        let callbook: CallbookModel = spot.model.callbook
        callbook.lookup("OK1ABC", typedCall: { "OK2XYZ" })
        await callbook.settle()
        #expect(callbook.callbookRecord == nil)
        #expect(callbook.record(for: "OK1ABC")?.grid == "JO70")
    }

    /// Kotlin's gate reads `configured()` only: enabled without credentials asks nothing; credentials but disabled
    /// reach the lane, which asks nothing and caches `EMPTY`. A key shorter than 3 clears the record.
    @Test func theGateIgnoresEnabled() async throws {
        let spot = try await SpotApp.make { config, _ in
            Self.credentials(&config, qrz: false)
            config.hamQth.enabled = false
        }
        let callbook: CallbookModel = spot.model.callbook
        callbook.lookup("OK1ABC", typedCall: { "OK1ABC" })
        await callbook.settle()
        #expect(spot.http.urls.isEmpty)
        #expect(callbook.cache.record("OK1ABC") == .empty)

        let bare = try await SpotApp.make()
        bare.model.callbook.lookup("OK1ABC", typedCall: { "OK1ABC" })
        await bare.model.callbook.settle()
        #expect(!bare.model.callbook.cache.contains("OK1ABC"))
        bare.model.callbook.lookup("OK", typedCall: { "OK" })
        #expect(bare.model.callbook.callbookRecord == nil)
    }

    @Test func prefetchFiltersFieldsModesAndOfflineGrids() async throws {
        let spot = try await SpotApp.make { config, _ in
            Self.credentials(&config, qrz: false)
            config.hamQth.callModes = []
            config.hamQth.fetchFields = ["cqZone"]
        }
        try await spot.app.startCqWwCw()
        spot.http.hamQth(call: "OH2AS", grid: "KP20", name: "Pekka", cq: "15")
        let buffer: SpotBuffer = spot.dx.spots
        buffer.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: ""))
        // In the offline grid database: never asked.
        buffer.add(DxSpot(spotter: "OK1ABC", freqHz: 14_026_000, dxCall: "0D7XOY", comment: ""))
        await runMainQueue()
        await spot.model.callbook.settle()
        #expect(spot.model.callbook.record(for: "OH2AS") == HamQthRecord(grid: "", name: "", cqZone: "15",
                                                                           ituZone: ""))
        #expect(!spot.http.urls.contains { $0.contains("0D7XOY") })
        #expect(!spot.model.callbook.cache.contains("0D7XOY"))
        #expect(spot.model.callbook.gridFromCsv("0d7xoy") == "CM98")
    }

    @Test func prefetchRespectsTheSourceModes() async throws {
        let spot = try await SpotApp.make { config, _ in Self.credentials(&config, qrz: false) }
        try await spot.app.startCqWwCw()
        spot.http.hamQth(call: "OH2AS", cq: "15")
        spot.dx.spots.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: ""))
        await runMainQueue()
        await spot.model.callbook.settle()
        // Default `callModes` = DIGI; a CW spot is not selected (not looked up, not cached as `EMPTY`).
        #expect(spot.http.urls.isEmpty)
        #expect(!spot.model.callbook.cache.contains("OH2AS"))
    }

    @Test func prefetchOnlyInAContestThatNeedsIt() async throws {
        let spot = try await SpotApp.make { config, _ in
            Self.credentials(&config, qrz: false)
            config.hamQth.callModes = []
        }
        spot.http.hamQth(call: "OH2AS", cq: "15")
        spot.dx.spots.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: ""))
        await runMainQueue()
        await spot.model.callbook.settle()
        #expect(spot.http.urls.isEmpty)
    }

    @Test func reloadClearsTheCache() async throws {
        let spot = try await SpotApp.make { config, _ in Self.credentials(&config, qrz: false) }
        spot.http.hamQth(call: "OK1ABC", grid: "JO70")
        let callbook: CallbookModel = spot.model.callbook
        callbook.lookup("OK1ABC", typedCall: { "OK1ABC" })
        await callbook.settle()
        #expect(callbook.cache.contains("OK1ABC"))
        callbook.reload()
        #expect(!callbook.cache.contains("OK1ABC"))
        let asked: Int = spot.http.urls.count
        callbook.lookup("OK1ABC", typedCall: { "OK1ABC" })
        await callbook.settle()
        #expect(spot.http.urls.count > asked)
    }

    @Test func theBrowserPagesOfACall() async throws {
        let spot = try await SpotApp.make()
        spot.model.callbook.openQrz(" ok1abc ")
        spot.model.callbook.openHamQth("oh2as")
        await spot.model.callbook.settle()
        #expect(spot.opener.urls == ["https://www.qrz.com/db/OK1ABC", "https://www.hamqth.com/OH2AS"])
    }
}
