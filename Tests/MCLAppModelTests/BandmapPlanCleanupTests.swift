import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The band map's N1MM context menu additions: removing the spots of this band or of all bands with or without the
/// self spots, the band plan edited at a frequency (written to `bandplan.yaml` and reloaded) and the US licence
/// class lines option. The rig is inert; nothing transmits.
@MainActor @Suite struct BandmapPlanCleanupTests {

    static func spot(_ call: String, _ freqHz: Int, selfSpotted: Bool = false) -> DxSpot {
        DxSpot(spotter: "OK1RR", freqHz: freqHz, dxCall: call, comment: "", selfSpotted: selfSpotted)
    }

    @Test func removeSpotsThisBandAndAllBands() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        let bandmap: BandmapModel = model.bandmap
        let buffer: SpotBuffer = model.dxCluster.spots
        // Without a tuned band "this band" removes nothing.
        buffer.add(Self.spot("OH2AS", 14_025_000))
        bandmap.removeSpots(thisBand: true, keepSelf: false)
        #expect(buffer.snapshot().count == 1)

        model.rig.qsy(14_025_000)
        func fill() {
            buffer.clear()
            buffer.add(Self.spot("OH2AS", 14_025_000))
            buffer.add(Self.spot("DL1ABC", 14_030_000, selfSpotted: true))
            buffer.add(Self.spot("W1AW", 7_005_000))
            buffer.add(Self.spot("K1ZZ", 7_010_000, selfSpotted: true))
        }
        fill()
        bandmap.removeSpots(thisBand: true, keepSelf: true)
        #expect(buffer.snapshot().map(\.dxCall) == ["DL1ABC", "W1AW", "K1ZZ"])
        fill()
        bandmap.removeSpots(thisBand: true, keepSelf: false)
        #expect(buffer.snapshot().map(\.dxCall) == ["W1AW", "K1ZZ"])
        fill()
        bandmap.removeSpots(thisBand: false, keepSelf: true)
        #expect(buffer.snapshot().map(\.dxCall) == ["DL1ABC", "K1ZZ"])
        fill()
        bandmap.clearSpots()
        #expect(buffer.snapshot().isEmpty)
    }

    @Test func theBandPlanIsEditedAtTheFrequency() async throws {
        let contestData: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcl-bandplan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: contestData, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: contestData) }
        let spot = try await SpotApp.make { config, _ in config.contestDataDir = contestData.path }
        let model: AppModel = spot.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        #expect(bandmap.analyzer().bandPlanCategory(14_065_000) == .cw)

        // No file yet: the built-in plan is the start; the digital segment now begins at 14 060 kHz.
        #expect(await bandmap.editBandPlan(.setLow(mode: "DIGI"), atHz: 14_060_000))
        let rows: [BandPlanFile.Segment] = BandPlanFile.read(contestData)
        #expect(rows.contains(BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 14_000, toKhz: 14_060)))
        #expect(rows.contains(BandPlanFile.Segment(region: "R1", mode: "DIGI", fromKhz: 14_060, toKhz: 14_099)))
        #expect(bandmap.analyzer().bandPlanCategory(14_065_000) == .digi)
        #expect(bandmap.analyzer().bandPlanCategory(14_055_000) == .cw)
        #expect(model.status.message.contains("14060.00"))

        #expect(await bandmap.editBandPlan(.remove, atHz: 14_065_000))
        #expect(bandmap.analyzer().bandPlanCategory(14_065_000) == nil)

        // A refused edit leaves the file and says why.
        let before: [BandPlanFile.Segment] = BandPlanFile.read(contestData)
        #expect(await bandmap.editBandPlan(.setLow(mode: "CW"), atHz: 14_065_000) == false)
        #expect(BandPlanFile.read(contestData) == before)
        #expect(await bandmap.editBandPlan(.setLow(mode: "CW"), atHz: 13_000_000) == false)
    }

    @Test func theLicenseLinesOption() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        #expect(!bandmap.showLicenseLines)
        #expect(bandmap.licenseLines.isEmpty)
        bandmap.toggleLicenseLines()
        #expect(bandmap.licenseLines == [14_025_000, 14_150_000, 14_175_000, 14_225_000])
        #expect(await spot.app.savedConfigFlushed().dxCluster.showUsLicenseLines)
        bandmap.zoomIn()
        #expect(bandmap.licenseLines.allSatisfy { $0 >= bandmap.viewport.loHz && $0 <= bandmap.viewport.hiHz })
        bandmap.toggleLicenseLines()
        #expect(bandmap.licenseLines.isEmpty)
    }
}
