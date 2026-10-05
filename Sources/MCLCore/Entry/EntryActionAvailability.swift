/// The area of the app that makes an entry-window action work. The local area does the local part
/// of everything it can; actions of another area show `tr("Zatím nedostupné")` and never log a QSO.
public enum EntryArea: String, CaseIterable, Sendable {
    /// Works locally, without hardware or network.
    case local
    /// Needs the rig over CAT, rotator, antennas or SO2R.
    case radio
    /// Needs the CW / voice keyer itself.
    case keyer
    /// Needs DX cluster spots or the bandmap.
    case spots
    /// Needs the station network or UDP broadcast.
    case network
    /// Opens a window or a menu action of another subsystem; the app decides by `MenuModel.isImplemented`.
    case windows
}

/// The kinds of call-field commands: the 33 cases of `CallFieldCommand` and the `Overflow` the parser throws
/// (shown as an invalid entry, L11) — 34 in all.
public enum EntryCommandKind: String, CaseIterable, Sendable {
    case qsy, otherVfo, split, splitOff, runScript, rit, swapVfo, changeMode, login, wipeLog, version, exportAdif
    case exportCabrillo, importLog, esmOn, esmOff, autoRunSp, setTour, tourOff, bonusStations, roverQth, countyLine
    case countyLineOff, spotMe, appAction, toggle, cutNumbers, openSettingsTab, rescore, openSetup, networkOn
    case networkOff, invalid, overflow

    /// The kind of a parsed command.
    public init(_ command: CallFieldCommand) {
        switch command {
        case .qsy: self = .qsy
        case .otherVfo: self = .otherVfo
        case .split: self = .split
        case .splitOff: self = .splitOff
        case .runScript: self = .runScript
        case .rit: self = .rit
        case .swapVfo: self = .swapVfo
        case .changeMode: self = .changeMode
        case .login: self = .login
        case .wipeLog: self = .wipeLog
        case .version: self = .version
        case .exportAdif: self = .exportAdif
        case .exportCabrillo: self = .exportCabrillo
        case .importLog: self = .importLog
        case .esmOn: self = .esmOn
        case .esmOff: self = .esmOff
        case .autoRunSp: self = .autoRunSp
        case .setTour: self = .setTour
        case .tourOff: self = .tourOff
        case .bonusStations: self = .bonusStations
        case .roverQth: self = .roverQth
        case .countyLine: self = .countyLine
        case .countyLineOff: self = .countyLineOff
        case .spotMe: self = .spotMe
        case .appAction: self = .appAction
        case .toggle: self = .toggle
        case .cutNumbers: self = .cutNumbers
        case .openSettingsTab: self = .openSettingsTab
        case .rescore: self = .rescore
        case .openSetup: self = .openSetup
        case .networkOn: self = .networkOn
        case .networkOff: self = .networkOff
        case .invalid: self = .invalid
        }
    }
}

/// Which area makes each entry-window action and call-field command work.
public enum EntryActionAvailability {

    /// A remappable shortcut (`runShortcut`, `EP:873-938`).
    public static func area(of action: ShortcutAction) -> EntryArea {
        switch action {
        case .sendCallExchange, .tuAndLog, .logWithoutSending, .forceLog, .wipe, .wipeUndo, .deleteLast, .note,
             .find, .incrementNr, .toggleEsm, .toggleCut, .yankScp, .operator, .toggleRun, .cqRepeat, .cqRepeatTime,
             .autoRunSp:
            return .local
        case .functionKeysSetup, .help:
            return .windows
        case .jumpCq, .tune, .splitOn, .splitToggle, .splitPrompt, .previousFrequency, .swapVfo, .copyToVfoB, .ritUp,
             .ritDown, .ritClear, .switchRadio, .so2rStereo, .rotorTurn, .rotorLong, .rotorStop, .nextAntenna, .bandUp,
             .bandDown:
            return .radio
        case .cwKeyboard:
            return .keyer
        case .nextSpotUp, .nextSpotDown, .nextMultUp, .nextMultDown, .nextSelfUp, .nextSelfDown, .spotIt,
             .spotWithComment, .store, .mark, .removeSpot, .removeSpotBlacklist, .dxClusterWindow:
            return .spots
        case .passCall, .popStack:
            return .network
        }
    }

    /// A command kind; `appAction` as a whole is local (its actions differ, see `area(of: Action)`).
    public static func area(of kind: EntryCommandKind) -> EntryArea {
        switch kind {
        case .qsy, .runScript, .changeMode, .login, .wipeLog, .version, .exportAdif, .exportCabrillo, .esmOn, .esmOff,
             .autoRunSp, .setTour, .tourOff, .bonusStations, .roverQth, .countyLine, .countyLineOff, .appAction,
             .toggle, .cutNumbers, .rescore, .invalid, .overflow:
            return .local
        case .importLog, .openSettingsTab, .openSetup:
            return .windows
        case .otherVfo, .split, .splitOff, .rit, .swapVfo:
            return .radio
        case .spotMe:
            return .spots
        case .networkOn, .networkOff:
            return .network
        }
    }

    /// A program action (`EP:400-416`). RELOAD/REOPEN work without the network.
    public static func area(of action: CallFieldCommand.Action) -> EntryArea {
        switch action {
        case .exit, .exitNow, .wipeLogNow, .closeContest, .newContest, .openContest, .copyLog, .reload, .reopen,
             .logout:
            return .local
        case .broadcastLog:
            return .network
        case .debugCat, .resetInterfaces:
            return .radio
        case .loadBeacons:
            return .spots
        }
    }

    /// The area works in this build: the local actions, the rig's (`.radio`), the keyer's
    /// (`.keyer`), the spots' (`.spots`) and the network's (`.network`).
    public static func isAvailable(_ area: EntryArea) -> Bool {
        area == .local || area == .radio || area == .keyer || area == .spots || area == .network
    }

    /// A parsed command.
    public static func area(of command: CallFieldCommand) -> EntryArea {
        if case .appAction(let action) = command {
            return area(of: action)
        }
        return area(of: EntryCommandKind(command))
    }
}
