/// Does a QSO in the given mode belong to the contest? Decided by `modes` from the definition. Port of Java
/// `engine/ModeEligibility.java`.
///
/// The mode **family** (CW / phone / data) is compared, not the exact name. An exact match would
/// throw away valid contacts: VHF contests declare `[CW, SSB]`, but FM is common on VHF;
/// `ww-digi` declares `[DIGITAL]`, yet FT8 and FT4 come from WSJT-X; `cq-wpx-rtty` declares
/// `[RTTY]` and generic DIGITAL belongs in it too. Between families, on the other hand, they get mixed up only by mistake —
/// an FT8 contact in a CW contest does not belong in the score.
///
/// When it cannot be decided (the contest lists no modes, the QSO mode is missing or unknown), the QSO is
/// counted. A `nil` element of `modes` is an "unrecognized mode" and is skipped — Java does the same
/// (`Mode.fromAdif(null)` → `null`), no crash.
public enum ModeEligibility {

    /// Mode family — no distinction within it.
    private enum Family { case cw, phone, digi }

    private static func family(of mode: Mode?) -> Family? {
        guard let mode else { return nil }
        if mode == .cw { return .cw }
        return mode.isDigital ? .digi : .phone
    }

    /// - Parameters:
    ///   - contestModes: `modes` from the contest definition (may be `nil` or empty)
    ///   - qsoMode: the QSO mode (mode name or ADIF abbreviation)
    /// - Returns: whether the QSO may be counted toward the score
    public static func counts(_ contestModes: [String?]?, _ qsoMode: String?) -> Bool {
        guard let contestModes, !contestModes.isEmpty else { return true }
        guard let qso = family(of: Mode.from(adif: qsoMode)) else {
            return true // we do not know the QSO mode — we do not throw it out
        }
        var anyKnown = false
        for name in contestModes {
            guard let known = family(of: Mode.from(adif: name)) else { continue }
            anyKnown = true
            if known == qso { return true }
        }
        return !anyKnown // the definition has not a single recognized mode — we do not restrict
    }
}
