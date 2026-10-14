/// The parts of the Entry window that its right-click menu can hide (N1MM Entry window → right click: Band Button,
/// CW speed, Show User Information…). Stored by `rawValue` in `AppConfig.entryHiddenSections`.
public enum EntrySection: String, CaseIterable, Sendable {
    /// The band × mode buttons.
    case bandButtons
    /// The hints in the frequency strip (callbook, call history, worked before…).
    case hints
    /// The bearing / distance line.
    case bearing
    /// The line with the LEDs, Run/S&P, ESM and the CW speed.
    case statusLine
    /// The CW speed spinner of that line.
    case cwSpeed
    /// The F1–F12 buttons.
    case functionKeys
    /// The Esc / Wipe / Log It… buttons.
    case actionButtons

    /// The Czech label (a translation key).
    public var label: String {
        switch self {
        case .bandButtons: return "Tlačítka pásem"
        case .hints: return "Nápovědy u frekvence (callbook, call history…)"
        case .bearing: return "Azimut a vzdálenost"
        case .statusLine: return "Řádek Run/S&P a ESM"
        case .cwSpeed: return "Rychlost CW"
        case .functionKeys: return "Tlačítka F1–F12"
        case .actionButtons: return "Tlačítka Wipe, Log It, Edit…"
        }
    }
}

/// N1MM's status of the typed call on a band (the band buttons' colours and the call field's colour): green = a
/// double (or better) multiplier, red = a multiplier, blue = a new QSO without a multiplier, grey = a dupe.
public enum CallBandStatus: Equatable, Sendable {
    case doubleMultiplier
    case multiplier
    case newQso
    case dupe

    /// The status of a contest preview.
    public init(dupe: Bool, newMultipliers: Int) {
        if dupe {
            self = .dupe
        } else if newMultipliers >= 2 {
            self = .doubleMultiplier
        } else if newMultipliers == 1 {
            self = .multiplier
        } else {
            self = .newQso
        }
    }

    public init(_ result: ContestSession.LogResult) {
        self.init(dupe: result.dupe,
                  newMultipliers: result.multipliers.filter { $0.countsAsMultiplier && $0.isNew }.count)
    }
}
