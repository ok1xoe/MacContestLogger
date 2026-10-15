import Foundation

/// The own station's state for the other stations (`AppState.ownStationStatus`, `AS:3137-3148`).
public enum StationStatusBuilder {

    /// - Parameters:
    ///   - stationId: `cluster.stationId`
    ///   - operatorCall: the operator's callsign
    ///   - stationType: `cluster.stationType`; `NONE` is sent as `""`
    ///   - runNumber: `cluster.runNumber`: a RUN station 1 or 2 is sent as `RUN1` / `RUN2` (N1MM Multi-two)
    ///   - catFreqHz: the active rig's frequency, `nil` without a CAT state
    ///   - catMode: the active rig's mode
    ///   - tunedFreqHz: the tuned frequency, used without a CAT state
    ///   - runMode: `RUN`, otherwise `S&P`
    ///   - sending: CW or voice message playing (`isSending`)
    ///   - typedCall: the call field, trimmed and uppercased as `entryCall`
    public static func status(stationId: String, operatorCall: String, stationType: OperatingGuard.StationType,
                              catFreqHz: Int?, catMode: Mode?, tunedFreqHz: Int, runMode: RunMode, qsoCount: Int,
                              sending: Bool, typedCall: String, runNumber: Int = 0) -> StationStatusWire {
        let freq: Int = catFreqHz ?? tunedFreqHz
        let band: String = Band.from(frequencyHz: freq)?.adif ?? ""
        var cluster = ClusterConfig()
        cluster.stationType = stationType
        cluster.runNumber = runNumber
        let type: String = cluster.announcedStationType
        let entry: String = JavaText.toUpperCase(KotlinText.trim(typedCall))
        return StationStatusWire(stationId: stationId, operator: operatorCall, stationType: type, band: band,
                                 mode: catMode?.rawValue ?? "", freqHz: freq,
                                 runMode: runMode == .run ? "RUN" : "S&P", qsoCount: Int32(truncatingIfNeeded: qsoCount),
                                 transmitting: sending, online: true, timestampUtc: nil, entryCall: entry)
    }
}
