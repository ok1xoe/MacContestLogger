/// What a tuning step asks of the rig: `rig` = the frequency to send with `setFrequencyHz`, or `nil`
/// when nothing goes to CAT (a frequency ≤ 0 never reaches the rig — the `RigPort.qsy` contract).
public struct TuneEffect: Equatable, Sendable {
    public let rig: Int64?

    public init(rig: Int64?) {
        self.rig = rig
    }
}

/// The shared tuned frequency of v1.1.1 (`AppState.tunedFreqHz`, `previousFreqHz`, `lastFreqOnBand`,
/// `antennaBand` — `AS:487-589`, `AS:811-838`) and the entry-window tuning steps that use it (`EP:771-803`,
/// `EP:1032-1043`). A pure value: the model applies the effects (CAT on the rig lane, antenna selection) in Kotlin
/// order.
public struct TuningState: Sendable, Equatable {

    /// `tunedFreqHz` — the source of truth of the entry window and the bandmap.
    public private(set) var tunedFreqHz: Int64 = 0
    /// `previousFreqHz` — Alt+F8 returns here.
    public private(set) var previousFreqHz: Int64 = 0
    /// `lastFreqOnBand` — Ctrl+PgUp/PgDn go back here (N1MM).
    public private(set) var lastFreqOnBand: [Band: Int64] = [:]
    /// `antennaBand` — the band of the last automatic antenna selection.
    public private(set) var antennaBand: Band?

    public init() {}

    /// `AppState.qsy` (`AS:544-551`): the previous frequency is remembered only when the old one is > 0 and the jump is
    /// more than 1 kHz (`kotlin.math.abs` of a wrapping `Long` difference — `Long.MIN_VALUE` stays negative). Kotlin
    /// has no guard for ≤ 0: the local half is faithful (the frequency becomes the tuned one), but nothing goes to the
    /// rig.
    public mutating func qsy(_ freqHz: Int64) -> TuneEffect {
        if tunedFreqHz > 0 && Self.kotlinAbs(tunedFreqHz &- freqHz) > 1_000 {
            previousFreqHz = tunedFreqHz
        }
        tunedFreqHz = freqHz
        return TuneEffect(rig: freqHz > 0 ? freqHz : nil)
    }

    /// `AppState.tuneTo` (`AS:827-831`): arrows and wheel — ≤ 0 does nothing; the previous frequency is untouched.
    public mutating func tuneTo(_ freqHz: Int64) -> TuneEffect? {
        guard freqHz > 0 else { return nil }
        tunedFreqHz = freqHz
        return TuneEffect(rig: freqHz)
    }

    /// `AppState.updateTunedFreq` (`AS:582-588`): only the shared frequency (CAT poll / manual field), no tuning.
    /// Returns the band on which an antenna is to be selected automatically (a band different from the last one).
    public mutating func updateTuned(_ freqHz: Int64) -> Band? {
        tunedFreqHz = freqHz
        guard let band = Band.from(frequencyHz: Int(freqHz)) else { return nil }
        lastFreqOnBand[band] = freqHz
        guard band != antennaBand else { return nil }
        antennaBand = band
        return band
    }

    /// `AppState.lastFrequencyOn`.
    public func lastFrequency(on band: Band) -> Int64? {
        lastFreqOnBand[band]
    }

    /// `AppState.returnToPreviousFrequency` (`AS:817-823`): `nil` = no previous frequency (the status is
    /// `RigTexts.noPreviousFrequency`), otherwise a `qsy` to it — so Alt+F8 toggles there and back.
    public mutating func returnToPrevious() -> TuneEffect? {
        guard previousFreqHz > 0 else { return nil }
        return qsy(previousFreqHz)
    }

    /// `AppState.bandsForStepping` (`AS:834-837`): the bands of the entry grid without WARC; outside a contest
    /// (`contestBands == nil` = every band) only up to 10 m.
    public static func bandsForStepping(contestBands: [Band]?) -> [Band] {
        let grid: [Band] = contestBands ?? Band.allCases
        let bands = grid.filter { !FrequencySteps.isWarc($0) }
        guard contestBands == nil, let limit = Band.allCases.firstIndex(of: .m10) else {
            return bands
        }
        return bands.filter { (Band.allCases.firstIndex(of: $0) ?? 0) <= limit }
    }

    /// Entry `stepBand` (`EP:783-795`): the next band in `direction`; the last frequency on it, otherwise the start of
    /// the mode's segment (CW / SSB·AM·FM → PH / RTTY → RY / else DI, falling back to CW). The result is the kHz the
    /// entry window QSYs to (`qsy(kHz, mode)`), `nil` = nothing.
    public func stepBand(from band: Band?, mode: Mode, allowed: [Band], direction: Int) -> Double? {
        guard let next = FrequencySteps.nextBand(band, allowed: allowed, direction: direction) else { return nil }
        if let last = lastFreqOnBand[next] {
            return Double(last) / 1000.0
        }
        guard let row = BandRows.all.first(where: { $0.band == next }) else { return nil }
        let column: Double?
        switch mode {
        case .cw: column = row.cwKHz
        case .ssb, .am, .fm: column = row.phKHz
        case .rtty: column = row.rttyKHz
        default: column = row.diKHz
        }
        return column ?? row.cwKHz
    }

    /// `AppState.tuneStepHz` (`AS:2373-2376`): SSB/AM/FM `tuneStepSsbHz`, otherwise `tuneStepCwHz`.
    public static func tuneStepHz(_ mode: Mode, cwHz: Int, ssbHz: Int) -> Int64 {
        switch mode {
        case .ssb, .am, .fm: return Int64(ssbHz)
        default: return Int64(cwHz)
        }
    }

    /// Entry `tuneStep` (`EP:798-804`): ↑ = −1, ↓ = +1 (N1MM). `nil` when the field frequency is ≤ 0; otherwise the
    /// new field frequency (the field shows it even when `tuneTo` then refuses a value ≤ 0).
    public static func tuneStep(fieldHz: Int64, mode: Mode, direction: Int, cwHz: Int, ssbHz: Int) -> Int64? {
        guard fieldHz > 0 else { return nil }
        let step: Int64 = tuneStepHz(mode, cwHz: cwHz, ssbHz: ssbHz)
        return fieldHz &+ Int64(direction) &* step
    }

    /// The entry-window wheel (`EP:1032-1043`): up = +1 notch, down = −1; nothing for no movement or a field
    /// frequency ≤ 0. Alt = 1 kHz, Ctrl = 10 kHz, Ctrl+Alt = 100 kHz rounding (`FrequencySteps.wheel`).
    public static func wheel(fieldHz: Int64, mode: Mode, direction: Int, alt: Bool, ctrl: Bool) -> Int64? {
        guard direction != 0, fieldHz > 0 else { return nil }
        let notches: Int = direction > 0 ? 1 : -1
        return Int64(FrequencySteps.wheel(Int(fieldHz), mode: mode, notches: notches, alt: alt, ctrl: ctrl))
    }

    /// `kotlin.math.abs(Long)` = `Math.abs`: `Long.MIN_VALUE` stays negative.
    static func kotlinAbs(_ value: Int64) -> Int64 {
        value < 0 ? 0 &- value : value
    }
}
