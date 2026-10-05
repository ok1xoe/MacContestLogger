/// Run / S&P by frequency (N1MM+ Entry Window → "Run mode and S+P mode"), Java
/// `runmode/RunModeTracker` v1.1.1:
/// - calling CQ (F1) or switching to Run remembers the **CQ frequency** on the band;
/// - in Run: QSY away from the last CQ frequency (outside the tolerance) switches to S&P;
/// - in S&P: returning to the band's CQ frequency switches back to Run — can be turned off
///   ("Do not automatically switch to Run on CQ-frequency", for sprints);
/// - automatic switching can be turned off entirely (Alt+F11, DXpeditions, several Run stations on a band).
///
/// Pure logic without UI; the state holds only the CQ frequency. Owned by the main thread (not `Sendable`).
public final class RunModeTracker {

    private var cqFreq: [Band: Int] = [:]
    /// Last CQ frequency (on any band) — "QSY away" in Run is measured from it.
    private var lastCq: Int?

    public init() {}

    /// Tuning tolerance: in CW/digital stations sit exactly, on phone tuning is coarse. You are on the CQ frequency
    /// until you tune away from it by more than this value. `nil` mode = 300 Hz.
    public static func toleranceHz(_ mode: Mode?) -> Int {
        switch mode {
        case .ssb?, .am?, .fm?:
            return 1_000
        default:
            return 300
        }
    }

    /// CQ on this frequency (F1, switch to Run): remembers it (only if positive; the band only when
    /// the frequency belongs to one), the mode is Run.
    @discardableResult
    public func onCq(_ freqHz: Int) -> RunMode {
        if freqHz > 0 {
            lastCq = freqHz
            if let band = Band.from(frequencyHz: freqHz) {
                cqFreq[band] = freqHz
            }
        }
        return .run
    }

    /// Alt+U: switches the mode; switching to Run sets the CQ frequency to the current one.
    public func toggle(_ current: RunMode, _ freqHz: Int) -> RunMode {
        current == .run ? .searchAndPounce : onCq(freqHz)
    }

    /// CQ frequency on a band (Alt+Q, marker in the bandmap); `nil` band → `nil`.
    public func cqFrequency(_ band: Band?) -> Int? {
        guard let band else { return nil }
        return cqFreq[band]
    }

    /// New mode after retuning, or `nil` when it should not change.
    ///
    /// - Parameters:
    ///   - autoSwitch: automatic switching on (Alt+F11)
    ///   - runOnCqFreq: returning to the CQ frequency switches to Run
    public func onTuned(_ freqHz: Int, mode: Mode?, current: RunMode, autoSwitch: Bool,
                        runOnCqFreq: Bool) -> RunMode? {
        guard autoSwitch, freqHz > 0 else { return nil }
        let tolerance: Int = Self.toleranceHz(mode)
        if current == .run {
            if let lastCq, abs(freqHz - lastCq) > tolerance {
                return .searchAndPounce
            }
            return nil
        }
        guard runOnCqFreq else { return nil }
        guard let band = Band.from(frequencyHz: freqHz), let cq = cqFreq[band] else { return nil }
        if abs(freqHz - cq) <= tolerance {
            lastCq = cq
            return .run
        }
        return nil
    }
}
