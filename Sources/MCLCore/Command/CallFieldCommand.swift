/// A text command typed into the call field instead of a callsign and confirmed with Enter (N1MM+ style "Callsign Box
/// Text Commands" and DXLog "Text commands"). Recognised by `CallFieldCommands.parse`; execution is up to the UI.
/// Mirrors the Java `sealed interface command.CallFieldCommand` (33 records) — a record = a case, its
/// components = associated values with the same names.
public enum CallFieldCommand: Equatable, Sendable {

    /// QSY to an absolute frequency (already converted from a relative/partial entry).
    case qsy(freqHz: Int64)
    /// Frequency of the second VFO (B) — N1MM notation with a leading slash (`/14030`).
    case otherVfo(freqHz: Int64)
    /// Split: transmit on the second VFO. A frequency confirmed with Ctrl+Enter is the transmit one (N1MM);
    /// `SPLIT` without a frequency (`txFreqHz = 0`) leaves the second VFO as it is.
    case split(txFreqHz: Int64)
    /// Split off (`NOSPLIT`/`SPLITOFF`).
    case splitOff
    /// Macro script `SCRIPT name` — lines of the file `scripts/<name>.txt` as commands.
    case runScript(name: String)
    /// RIT: absolute offset in Hz (`RIT 120`, `RIT -50`); 0 = off (`NORIT`/`RITCLEAR`).
    case rit(offsetHz: Int32)
    /// Swap VFO A↔B (`SWAP`, DXLog).
    case swapVfo
    /// Switch the operating mode (CW, SSB/USB/LSB, RTTY, FT8…).
    case changeMode(mode: Mode)
    /// Operator login (`OPON`/`LOGIN`); empty = ask with a dialog.
    case login(operator: String)
    /// Delete all QSOs of the current logbook (`WIPELOG`/`CLEARLOG`) — after confirmation.
    case wipeLog
    /// Show the program version (`VERSION`/`VER`).
    case version
    /// Export the logbook to ADIF (`EXPORT`).
    case exportAdif
    /// Export the logbook to Cabrillo (`WRITELOG`/`MAKELOG`).
    case exportCabrillo
    /// Import QSOs from ADIF/Cabrillo (`IMPORT`).
    case importLog
    /// Turn ESM on (`ESM`/`ESMON`, DXLog).
    case esmOn
    /// Turn ESM off (`NOESM`/`ESMOFF`, DXLog).
    case esmOff
    /// Turn automatic Run/S&P switching by CQ frequency on (`AUTORSP`) / off (`NOAUTRSP`), DXLog.
    case autoRunSp(enabled: Bool)
    /// `TOUR hhmm/mm` — contest session (N1MM). Without an argument the content of the Snt field is taken; if there is
    /// nothing there either, shows the current setting.
    case setTour(params: String)
    /// `NOTOUR`/`TOUROFF` — no sessions, dupes for the whole contest.
    case tourOff
    /// `BONUS [callsigns]` — list of bonus stations (QSO party); a dialog without an argument.
    case bonusStations(calls: String)
    /// `ROVERQTH [county]` — my current county (rover, N1MM); a dialog without an argument.
    case roverQth(county: String)
    /// `COUNTYLINE [counties]` — county line: the QSO is logged for each county; a dialog without an argument.
    case countyLine(counties: String)
    /// `NOCOUNTYLINE` — end of county-line mode.
    case countyLineOff
    /// `SPOTME [comment]` — spot the own station to the DX cluster (DXLog).
    case spotMe(comment: String)
    /// Program action.
    case appAction(action: Action)
    /// Turning an option on / off.
    case toggle(setting: Setting, on: Bool)
    /// Cut numbers: `FULLABBREV`, `PROABBREV`, `SEMIABBREV` (DXLog) set the style, `NOABBREV` turns it off
    /// (`style = nil`, Java `null`).
    case cutNumbers(style: CutStyle?)
    /// Open Settings on a tab (`MSGS`, `WKEY`, `NETCONFIG`).
    case openSettingsTab(tabKey: String)
    /// Manual score recalculation (`RESCORE`).
    case rescore
    /// Open Settings (`SETUP`).
    case openSetup
    /// Turn on network logbook synchronisation (`NETON`/`NET`).
    case networkOn
    /// Turn off network logbook synchronisation (`NETOFF`/`NONET`).
    case networkOff
    /// The entry looks like a command (typically a number = frequency), but cannot be executed. It must not be logged
    /// as a callsign — the UI only shows `message`.
    case invalid(message: String)

    /// Program actions from the DXLog / N1MM text commands (BCLOG, COPYLOG, BYE…); `rawValue` = Java name.
    public enum Action: String, CaseIterable, Sendable {
        /// `BCLOG` — broadcast the whole logbook once via UDP broadcast.
        case broadcastLog = "BROADCAST_LOG"
        /// `BYE`/`EXIT`/`QUIT` — quit the program (with confirmation).
        case exit = "EXIT"
        /// `EXITNOW`/`QUITNOW` — quit without asking.
        case exitNow = "EXIT_NOW"
        /// `CLEARLOGNOW` — delete the logbook without confirmation.
        case wipeLogNow = "WIPE_LOG_NOW"
        /// `CLOSE` — close the contest (free logging).
        case closeContest = "CLOSE_CONTEST"
        /// `NEW` — new contest.
        case newContest = "NEW_CONTEST"
        /// `OPEN` — open a contest.
        case openContest = "OPEN_CONTEST"
        /// `COPYLOG` — database backup with the time in the name.
        case copyLog = "COPY_LOG"
        /// `RELOAD`/`RELOADNOW` — reload the contest definitions and open the contest.
        case reload = "RELOAD"
        /// `REOPEN`/`REOPENNOW` — refresh the logbook and recalculate the score.
        case reopen = "REOPEN"
        /// `DEBUGCAT` — CAT communication window.
        case debugCat = "DEBUG_CAT"
        /// `RESET` — reconnect the rig and the CW key.
        case resetInterfaces = "RESET_INTERFACES"
        /// `BEACONS` — load a beacon file into the bandmap (N1MM).
        case loadBeacons = "LOAD_BEACONS"
        /// `OPOFF`/`LOGOUT` — log the operator out (back to the station callsign).
        case logout = "LOGOUT"
    }

    /// Switchable option; `rawValue` = Java name.
    public enum Setting: String, CaseIterable, Sendable {
        /// `RPT`/`NORPT` — CQ repeat (N1MM Alt+R).
        case cqRepeat = "CQ_REPEAT"
        /// `WORKDUPE`/`NOWORKDUPE` — ESM: work a dupe in Run as a new QSO.
        case workDupes = "WORK_DUPES"
        /// `AUTORELOAD`/`NOAUTORELOAD` — open the last contest right at startup.
        case autoReload = "AUTO_RELOAD"
        /// `POSTCONTEST`/`NOPOSTCONTEST` — after-the-fact entry of a paper log (DXLog).
        case postContest = "POST_CONTEST"
    }
}
