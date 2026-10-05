import Foundation

/// The own station's state for the other stations (`AppState.ownStationStatus`, `AS:3137-3148`).
public enum StationStatusBuilder {

    /// - Parameters:
    ///   - stationId: `cluster.stationId`
    ///   - operatorCall: the operator's callsign
    ///   - stationType: `cluster.stationType`; `NONE` is sent as `""`
    ///   - catFreqHz: the active rig's frequency, `nil` without a CAT state
    ///   - catMode: the active rig's mode
    ///   - tunedFreqHz: the tuned frequency, used without a CAT state
    ///   - runMode: `RUN`, otherwise `S&P`
    ///   - sending: CW or voice message playing (`isSending`)
    ///   - typedCall: the call field, trimmed and uppercased as `entryCall`
    public static func status(stationId: String, operatorCall: String, stationType: OperatingGuard.StationType,
                              catFreqHz: Int?, catMode: Mode?, tunedFreqHz: Int, runMode: RunMode, qsoCount: Int,
                              sending: Bool, typedCall: String) -> StationStatusWire {
        let freq: Int = catFreqHz ?? tunedFreqHz
        let band: String = Band.from(frequencyHz: freq)?.adif ?? ""
        let type: String = stationType == .none ? "" : stationType.rawValue
        let entry: String = JavaText.toUpperCase(KotlinText.trim(typedCall))
        return StationStatusWire(stationId: stationId, operator: operatorCall, stationType: type, band: band,
                                 mode: catMode?.rawValue ?? "", freqHz: freq,
                                 runMode: runMode == .run ? "RUN" : "S&P", qsoCount: Int32(truncatingIfNeeded: qsoCount),
                                 transmitting: sending, online: true, timestampUtc: nil, entryCall: entry)
    }
}
