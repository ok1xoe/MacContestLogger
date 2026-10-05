import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The Available Multipliers window's model (`AvailableMultipliersWindow.kt`): the definition's
/// default filter after an opening activation, Mults / Mults & Qs, bands and modes, the band matrix, the title, the
/// sort, a click that tunes (or QSYs with the call) and the row menu. The rig is inert; nothing transmits.
@MainActor @Suite struct AvailMultModelTests {

    static func spot(_ call: String, _ freqHz: Int, spotter: String = "OK1RR") -> DxSpot {
        DxSpot(spotter: spotter, freqHz: freqHz, dxCall: call, comment: "")
    }

    /// CQ WW CW with DL1ABC logged on 20 m and five spots (a dupe, a plain Q, two multipliers, a phone spot).
    static func app() async throws -> SpotApp {
        let spot = try await SpotApp.make()
        try await spot.app.startCqWwCw()
        await spot.app.logContestQso(call: "DL1ABC", zone: "14")
        await spot.model.logbook.settleMutations()
        let buffer: SpotBuffer = spot.model.dxCluster.spots
        buffer.add(Self.spot("DL1ABC", 14_025_000))
        buffer.add(Self.spot("DL2XYZ", 14_026_000))
        buffer.add(Self.spot("W1AW", 14_030_000, spotter: "W3LPL"))
        buffer.add(Self.spot("OK1XYZ", 7_010_000))
        buffer.add(Self.spot("K1AA", 14_250_000))
        await runMainQueue()
        return spot
    }

    @Test func outsideAContestNothingIsShown() async throws {
        let spot = try await SpotApp.make()
        spot.model.dxCluster.spots.add(Self.spot("W1AW", 14_030_000))
        #expect(!spot.model.availMult.contestActive)
        #expect(spot.model.availMult.snapshot() == .empty)
    }

    /// The opening activation sets the definition's bands and the CW category (Kotlin `setDefaultSpotFilters`).
    @Test func theDefaultFilterComesFromTheDefinition() async throws {
        let spot = try await SpotApp.make()
        let avail: AvailMultModel = spot.model.availMult
        #expect(avail.bands.isEmpty && avail.modes.isEmpty)
        try await spot.app.startCqWwCw()
        #expect(avail.modes == ["CW"])
        let definition: ContestDefinition = try #require(spot.model.contest.definition)
        let bands = Set((definition.bands ?? []).compactMap { $0.flatMap { Band.from(adif: $0) } })
        #expect(!bands.isEmpty)
        #expect(avail.bands == bands)
    }

    @Test func filterMatrixAndTitle() async throws {
        let spot = try await Self.app()
        let avail: AvailMultModel = spot.model.availMult
        var shown: AvailMultModel.Snapshot = avail.snapshot()
        // The phone spot is outside the CW filter.
        #expect(shown.rows.map(\.call) == ["OK1XYZ", "DL1ABC", "DL2XYZ", "W1AW"])
        #expect(shown.counts == AvailableMults.Counts(mults: 2, qs: 3, total: 4))
        #expect(shown.matrix[.m20] == AvailableMults.Counts(mults: 1, qs: 2, total: 3))
        #expect(shown.matrix[.m40] == AvailableMults.Counts(mults: 1, qs: 1, total: 1))
        #expect(spot.model.language.text(avail.title(shown.counts)) == "Dostupné — 2 Mults, 3 Qs z 4 spotů")
        avail.multsOnly = true
        #expect(avail.snapshot().rows.map(\.call) == ["OK1XYZ", "W1AW"])
        avail.bands = [.m40]
        #expect(avail.snapshot().rows.map(\.call) == ["OK1XYZ"])
        avail.multsOnly = false
        avail.bands = []
        avail.modes = []
        shown = avail.snapshot()
        #expect(shown.rows.map(\.call) == ["OK1XYZ", "DL1ABC", "DL2XYZ", "W1AW", "K1AA"])
        // A new spot shows after the feed's revision.
        spot.model.dxCluster.spots.add(Self.spot("JA1ABC", 21_010_000))
        await runMainQueue()
        #expect(avail.snapshot().rows.count == 6)
    }

    /// The sort: Freq ascending at first; the same column flips the direction, another column starts ascending.
    @Test func theSortFollowsTheHeaders() async throws {
        let spot = try await Self.app()
        let avail: AvailMultModel = spot.model.availMult
        let rows: [SpotRow] = avail.snapshot().rows
        avail.sort(by: .freq)
        #expect(avail.sortColumn == .freq && !avail.ascending)
        #expect(avail.snapshot().rows == AvailableMults.sorted(rows, by: .freq, ascending: false))
        avail.sort(by: .pts)
        #expect(avail.sortColumn == .pts && avail.ascending)
        #expect(avail.snapshot().rows == AvailableMults.sorted(rows, by: .pts, ascending: true))
        avail.sort(by: .dir)
        avail.sort(by: .dir)
        #expect(avail.snapshot().rows == AvailableMults.sorted(rows, by: .dir, ascending: false))
        avail.resetSort()
        #expect(avail.sortColumn == .freq && avail.ascending)
    }

    /// A click tunes to the call's spot; when the spot is gone, `qsy(freq, call)` still brings the call.
    @Test func aClickTunesToTheRow() async throws {
        let spot = try await Self.app()
        let model: AppModel = spot.model
        let avail: AvailMultModel = model.availMult
        let rows: [SpotRow] = avail.snapshot().rows
        let w1aw: SpotRow = try #require(rows.first { $0.call == "W1AW" })
        avail.click(w1aw)
        #expect(model.rig.tuning.tunedFreqHz == 14_030_000)
        #expect(model.entry.form.call == "W1AW")
        let ok: SpotRow = try #require(rows.first { $0.call == "OK1XYZ" })
        model.dxCluster.spots.remove("OK1XYZ")
        avail.click(ok)
        #expect(model.rig.tuning.tunedFreqHz == 7_010_000)
        #expect(model.entry.form.call == "OK1XYZ")
        #expect(model.entry.callFromSpot)
    }

    /// The row menu: remove, blacklist the call or the spotter, the browser pages, clear all.
    @Test func theRowMenu() async throws {
        let spot = try await Self.app()
        let model: AppModel = spot.model
        let avail: AvailMultModel = model.availMult
        let rows: [SpotRow] = avail.snapshot().rows
        let w1aw: SpotRow = try #require(rows.first { $0.call == "W1AW" })
        avail.openQrz(w1aw)
        avail.openHamQth(w1aw)
        await eventually("pages") { spot.opener.urls.count == 2 }
        #expect(spot.opener.urls == ["https://www.qrz.com/db/W1AW", "https://www.hamqth.com/W1AW"])
        avail.blacklistSpotter(w1aw)
        #expect(model.config.config.dxCluster.spotterBlacklist.map(\.value) == ["W3LPL"])
        let dl: SpotRow = try #require(rows.first { $0.call == "DL2XYZ" })
        avail.blacklistCall(dl)
        #expect(model.config.config.dxCluster.callBlacklist.map(\.value) == ["DL2XYZ"])
        let ok: SpotRow = try #require(rows.first { $0.call == "OK1XYZ" })
        avail.remove(ok)
        await runMainQueue()
        #expect(avail.snapshot().rows.map(\.call) == ["DL1ABC"])
        avail.clearSpots()
        await runMainQueue()
        #expect(avail.snapshot().rows.isEmpty)
    }
}
