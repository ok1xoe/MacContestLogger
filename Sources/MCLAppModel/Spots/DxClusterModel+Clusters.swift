import Foundation
import MCLCore

/// The N1MM Telnet window's spot keeping options: saving the spots across a restart and randomizing the frequency
/// of tuning to a spot (`RigModel.tuneToSpot`). Both apply and are saved at once.
extension DxClusterModel {

    public var saveSpots: Bool {
        config.config.dxCluster.saveSpots
    }

    public func setSaveSpots(_ on: Bool) {
        guard config.config.dxCluster.saveSpots != on else { return }
        config.config.dxCluster.saveSpots = on
        config.save(failureKey: ClusterTexts.macroSaveFailedKey)
    }

    public var randomizeSpotFrequencies: Bool {
        config.config.dxCluster.randomizeSpotFrequencies
    }

    public func setRandomizeSpotFrequencies(_ on: Bool) {
        guard config.config.dxCluster.randomizeSpotFrequencies != on else { return }
        config.config.dxCluster.randomizeSpotFrequencies = on
        config.save(failureKey: ClusterTexts.macroSaveFailedKey)
    }

    /// The quit: with „Save Spots" on, the live buffer is written to `savedSpotsFile`; with it off a file left from
    /// before is removed (it would be stale when the option is turned on again). A failed write is only logged.
    func persistSpots() {
        guard let file = savedSpotsFile else { return }
        guard saveSpots else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        do {
            try SavedSpotsFile.encode(spots.exportEntries()).write(to: file, options: .atomic)
        } catch {
            try? log.info(ErrorText.message(error))
        }
    }

    /// The start: with „Save Spots" on, the buffer takes the configured timeout and the saved spots still alive in
    /// it (their original times; blacklisted ones stay out). Returns how many were restored.
    @discardableResult
    func restoreSpots() -> Int {
        guard saveSpots, let file = savedSpotsFile, let data = try? Data(contentsOf: file),
              let stored = SavedSpotsFile.decode(data) else { return 0 }
        setBufferMinutes()
        return spots.importEntries(stored)
    }
}
