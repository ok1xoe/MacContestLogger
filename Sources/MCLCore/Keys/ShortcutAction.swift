/// Entry window actions that can be remapped (N1MM Key Mapper). Default keys
/// match N1MM+ (see docs/keyboard-shortcuts.md). `id` is stable — it is stored in
/// `config.json` (`keyBindings`). Mirrors the Java `cz.ok1xoe.maccontestlogger.keys.ShortcutAction`;
/// the order of cases = the Java order of constants (`EnumMap`, `values()`).
public enum ShortcutAction: CaseIterable, Sendable {
    case sendCallExchange
    case tuAndLog
    case logWithoutSending
    case forceLog
    case wipe
    case wipeUndo
    case deleteLast
    case note
    case find
    case incrementNr
    case toggleEsm
    case toggleCut
    case yankScp
    case functionKeysSetup
    case help
    case `operator`
    case toggleRun
    case jumpCq
    case cqRepeat
    case cqRepeatTime
    case tune
    case splitOn
    case splitToggle
    case splitPrompt
    case previousFrequency
    case swapVfo
    case autoRunSp
    case copyToVfoB
    case ritUp
    case ritDown
    case ritClear
    case switchRadio
    case so2rStereo
    case cwKeyboard
    case passCall
    case popStack
    case rotorTurn
    case rotorLong
    case rotorStop
    case nextAntenna
    case bandUp
    case bandDown
    case nextSpotUp
    case nextSpotDown
    case nextMultUp
    case nextMultDown
    case nextSelfUp
    case nextSelfDown
    case spotIt
    case spotWithComment
    case store
    case mark
    case removeSpot
    case removeSpotBlacklist
    case dxClusterWindow
    // Swift-only actions (after the Java constants, so the Java order and indices stay).
    /// N1MM Ctrl+Alt+G / `{STACKANOTHER}`: the call field onto the call stack.
    case stackCall
    /// N1MM Alt+G: the next call from the call stack into a wiped entry window.
    case grabStack
    /// N1MM Insert (digital): an empty call field takes the call from the Grab window, then his call + exchange by
    /// Run/S&P, ESM and the dupe state. The PC Insert key is Help on a Mac.
    case insertGrab
    /// N1MM Alt+T (digital): fldigi transmits / back to receive; the TX window gets the typing.
    case toggleTx
    /// N1MM Ctrl+←/→ (two Digital Interfaces): VFO A / rig 1 and its DI1, VFO B / rig 2 and its DI2. Ctrl+arrows
    /// belong to Mission Control on a Mac, so the defaults are Cmd+Alt+←/→.
    case digitalLeft
    case digitalRight
    /// N1MM Ctrl+Y: Edit Last Contact — the last logged QSO in the edit dialog.
    case editLast
    /// N1MM Ctrl+Q: QuickEdit — the last logged QSO into the entry fields, again = one QSO back.
    case quickEditBack
    /// N1MM Ctrl+A: QuickEdit one QSO forward.
    case quickEditForward
    /// N1MM Alt+S: in split, the receive frequency back to the transmit one.
    case resetRx
    /// N1MM Alt+': the rig's filter to the other width (wide / narrow) of its mode.
    case toggleFilter
    /// N1MM Ctrl+Alt+R: CW reverse on / off (the rig's CW ↔ CWR).
    case cwReverse
    /// N1MM Ctrl+Shift+W: wipe the other entry window (SO2V / SO2R).
    case wipeOther
    /// N1MM Ctrl+Alt+Q: the last CQ frequency on any band.
    case jumpLastCq
    /// N1MM Ctrl+Alt+M: the multi-op station type Run ↔ Mult.
    case toggleStationType
    /// N1MM Alt+Z: set the pass frequency, broadcast to the other stations.
    case passFrequency
    /// N1MM Alt+A / Shift+Alt+A: the next / previous spot of the Available window into the entry window.
    case availNext
    case availPrevious
    /// N1MM Alt+= (VHF and up): the typed call and grid searched in the call history, the results in the Check window.
    case gridSearch
    /// N1MM Alt+- (VHF and up): the grid field toggles through the call history's grids and the typed one.
    case gridToggle
    /// N1MM Ctrl+Z (WAE): QTC mode on / off — the QTC window opens to receive (Europe) or send (elsewhere).
    case qtcMode
    /// N1MM Pause (SO2R / SO2V): both foci to the other window, or the transmit focus to the entry focus when they
    /// are split. A Mac has no Pause key; a PC keyboard's Pause arrives as F15.
    case focusSwap
    /// N1MM Alt+F5: frequency, mode and call swapped between the radios (SO2R) or VFOs (SO2V); the entry focus moves
    /// to the other window.
    case swapRadios
    /// N1MM Alt+F6 (SO2R): like Alt+F5 without moving the focus.
    case swapRadiosKeepFocus
    /// N1MM Ctrl+B (SO2R): Dueling CQs on / off.
    case duelingCq
    /// N1MM Ctrl+Shift+K (SO2R): Focus on Other Radio on / off.
    case focusOther
    /// N1MM Ctrl+Shift+L: the `{CTRLFx}` macro on / off.
    case toggleCtrlFx
    /// N1MM „Toggle Stereo/OTRSP Macro" (Ctrl+`): `{STEREOON}` / `{STEREOOFF}` and `{OTRSP RX}` on / off.
    case toggleStereoMacros
    /// N1MM Ctrl+Shift+↓/↑ (SO2V / SO2R): the other radio to the next spot higher / lower (Cmd on a Mac, as the
    /// active radio's spot keys).
    case otherSpotUp
    case otherSpotDown
    /// N1MM Shift+Ctrl+Alt+↓/↑: the other radio to the next multiplier spot higher / lower.
    case otherMultUp
    case otherMultDown
    /// N1MM Ctrl+Shift+PgUp/PgDn: the other radio one band up / down.
    case otherBandUp
    case otherBandDown
    /// N1MM Shift+Alt+Q: the other radio to its band's CQ frequency.
    case otherCqFrequency

    /// Row of a Java constant: name, id, label and default keys.
    private struct Spec {
        let name: String
        let id: String
        let label: String
        let defaultKeys: String
    }

    private var spec: Spec {
        switch self {
        case .sendCallExchange: Spec(name: "SEND_CALL_EXCHANGE", id: "send_call_exch", label: "Jeho volačka + výměna (F5+F2)", defaultKeys: ";")
        case .tuAndLog: Spec(name: "TU_AND_LOG", id: "tu_log", label: "TU a zapsat (F3)", defaultKeys: "'")
        case .logWithoutSending: Spec(name: "LOG_WITHOUT_SENDING", id: "log_quiet", label: "Zapsat (TU, v ESM bez vysílání)", defaultKeys: "Alt+ENTER")
        case .forceLog: Spec(name: "FORCE_LOG", id: "force_log", label: "Vynucený zápis s neplatnou výměnou", defaultKeys: "Ctrl+Alt+ENTER")
        case .wipe: Spec(name: "WIPE", id: "wipe", label: "Vymazat pole (nevratně)", defaultKeys: "Ctrl+W")
        case .wipeUndo: Spec(name: "WIPE_UNDO", id: "wipe_undo", label: "Vymazat / vrátit pole", defaultKeys: "Alt+W")
        case .deleteLast: Spec(name: "DELETE_LAST", id: "delete_last", label: "Smazat poslední QSO", defaultKeys: "Ctrl+D")
        case .note: Spec(name: "NOTE", id: "note", label: "Poznámka k QSO", defaultKeys: "Ctrl+N")
        case .find: Spec(name: "FIND", id: "find", label: "Najít volačku v deníku", defaultKeys: "Ctrl+F")
        case .incrementNr: Spec(name: "INCREMENT_NR", id: "inc_nr", label: "Číslo ve výměně +1", defaultKeys: "Ctrl+U")
        case .toggleEsm: Spec(name: "TOGGLE_ESM", id: "esm", label: "ESM zap / vyp", defaultKeys: "Ctrl+M")
        case .toggleCut: Spec(name: "TOGGLE_CUT", id: "cut", label: "Cut čísla zap / vyp", defaultKeys: "Ctrl+G")
        case .yankScp: Spec(name: "YANK_SCP", id: "yank", label: "První návrh SCP do volačky", defaultKeys: "Alt+Y")
        case .functionKeysSetup: Spec(name: "FUNCTION_KEYS_SETUP", id: "fkeys", label: "Nastavení → Function Keys", defaultKeys: "Alt+K")
        case .help: Spec(name: "HELP", id: "help", label: "Nápověda", defaultKeys: "Alt+H")
        case .operator: Spec(name: "OPERATOR", id: "operator", label: "Přihlásit operátora", defaultKeys: "Ctrl+O")
        case .toggleRun: Spec(name: "TOGGLE_RUN", id: "run", label: "Run / S&P", defaultKeys: "Alt+U")
        case .jumpCq: Spec(name: "JUMP_CQ", id: "jump_cq", label: "Zpět na CQ frekvenci", defaultKeys: "Alt+Q")
        case .cqRepeat: Spec(name: "CQ_REPEAT", id: "repeat", label: "Opakování CQ zap / vyp", defaultKeys: "Alt+R")
        case .cqRepeatTime: Spec(name: "CQ_REPEAT_TIME", id: "repeat_time", label: "Pauza mezi CQ", defaultKeys: "Ctrl+R")
        case .tune: Spec(name: "TUNE", id: "tune", label: "Ladění nosnou", defaultKeys: "Ctrl+T")
        case .splitOn: Spec(name: "SPLIT_ON", id: "split_on", label: "Split zapnout", defaultKeys: "Ctrl+S")
        case .splitToggle: Spec(name: "SPLIT_TOGGLE", id: "split_toggle", label: "Split přepnout", defaultKeys: "Ctrl+Alt+S")
        case .splitPrompt: Spec(name: "SPLIT_PROMPT", id: "split_prompt", label: "Split na frekvenci…", defaultKeys: "Alt+F7")
        case .previousFrequency: Spec(name: "PREVIOUS_FREQUENCY", id: "prev_freq", label: "Předchozí frekvence", defaultKeys: "Alt+F8")
        case .swapVfo: Spec(name: "SWAP_VFO", id: "swap_vfo", label: "Prohodit VFO A ↔ B", defaultKeys: "Alt+F10")
        case .autoRunSp: Spec(name: "AUTO_RUN_SP", id: "auto_runsp", label: "Automatika Run/S&P zap / vyp", defaultKeys: "Alt+F11")
        case .copyToVfoB: Spec(name: "COPY_TO_VFO_B", id: "copy_vfo", label: "Frekvence A → B", defaultKeys: "Alt+F12")
        case .ritUp: Spec(name: "RIT_UP", id: "rit_up", label: "RIT nahoru", defaultKeys: "Ctrl+Alt+RIGHT")
        case .ritDown: Spec(name: "RIT_DOWN", id: "rit_down", label: "RIT dolů", defaultKeys: "Ctrl+Alt+LEFT")
        case .ritClear: Spec(name: "RIT_CLEAR", id: "rit_clear", label: "RIT vypnout", defaultKeys: "Ctrl+Alt+Shift+R")
        case .switchRadio: Spec(name: "SWITCH_RADIO", id: "switch_radio", label: "SO2V/SO2R: přepnout na druhé okno (rig / VFO)", defaultKeys: "BACK_SLASH")
        case .so2rStereo: Spec(name: "SO2R_STEREO", id: "so2r_stereo", label: "SO2R: stereo poslech zap / vyp", defaultKeys: "BACK_QUOTE")
        case .cwKeyboard: Spec(name: "CW_KEYBOARD", id: "cw_keyboard", label: "Psaní CW z klávesnice", defaultKeys: "Ctrl+K")
        case .passCall: Spec(name: "PASS_CALL", id: "pass_call", label: "Předat volačku jiné stanici (síť)", defaultKeys: "Ctrl+Alt+P")
        case .popStack: Spec(name: "POP_STACK", id: "pop_stack", label: "Volačka ze zásobníku partnera", defaultKeys: "Ctrl+Alt+K")
        case .rotorTurn: Spec(name: "ROTOR_TURN", id: "rotor_turn", label: "Rotátor na volačku (krátká cesta)", defaultKeys: "Alt+J")
        case .rotorLong: Spec(name: "ROTOR_LONG", id: "rotor_long", label: "Rotátor na volačku (dlouhá cesta)", defaultKeys: "Alt+L")
        case .rotorStop: Spec(name: "ROTOR_STOP", id: "rotor_stop", label: "Rotátor zastavit", defaultKeys: "Ctrl+Alt+J")
        case .nextAntenna: Spec(name: "NEXT_ANTENNA", id: "next_antenna", label: "Další anténa pro pásmo", defaultKeys: "Ctrl+Alt+A")
        case .bandUp: Spec(name: "BAND_UP", id: "band_up", label: "Pásmo výš", defaultKeys: "Ctrl+PAGE_UP")
        case .bandDown: Spec(name: "BAND_DOWN", id: "band_down", label: "Pásmo níž", defaultKeys: "Ctrl+PAGE_DOWN")
        case .nextSpotUp: Spec(name: "NEXT_SPOT_UP", id: "spot_up", label: "Další spot výš", defaultKeys: "Cmd+DOWN")
        case .nextSpotDown: Spec(name: "NEXT_SPOT_DOWN", id: "spot_down", label: "Další spot níž", defaultKeys: "Cmd+UP")
        case .nextMultUp: Spec(name: "NEXT_MULT_UP", id: "mult_up", label: "Další násobič výš", defaultKeys: "Ctrl+Alt+DOWN")
        case .nextMultDown: Spec(name: "NEXT_MULT_DOWN", id: "mult_down", label: "Další násobič níž", defaultKeys: "Ctrl+Alt+UP")
        case .nextSelfUp: Spec(name: "NEXT_SELF_UP", id: "self_up", label: "Další vlastní spot výš", defaultKeys: "Alt+Shift+DOWN")
        case .nextSelfDown: Spec(name: "NEXT_SELF_DOWN", id: "self_down", label: "Další vlastní spot níž", defaultKeys: "Alt+Shift+UP")
        case .spotIt: Spec(name: "SPOT_IT", id: "spot", label: "Spot do clusteru", defaultKeys: "Alt+P")
        case .spotWithComment: Spec(name: "SPOT_WITH_COMMENT", id: "spot_comment", label: "Spot s komentářem", defaultKeys: "Ctrl+P")
        case .store: Spec(name: "STORE", id: "store", label: "Store do bandmapy", defaultKeys: "Alt+O")
        case .mark: Spec(name: "MARK", id: "mark", label: "Mark frekvence", defaultKeys: "Alt+M")
        case .removeSpot: Spec(name: "REMOVE_SPOT", id: "remove_spot", label: "Odstranit spot", defaultKeys: "Alt+D")
        case .removeSpotBlacklist: Spec(name: "REMOVE_SPOT_BLACKLIST", id: "remove_blacklist", label: "Odstranit spot + blacklist", defaultKeys: "Alt+Shift+D")
        case .dxClusterWindow: Spec(name: "DX_CLUSTER_WINDOW", id: "dx_window", label: "Okno DX clusteru", defaultKeys: "Ctrl+TAB")
        case .stackCall: Spec(name: "STACK_CALL", id: "stack_call", label: "Volačku do zásobníku", defaultKeys: "Ctrl+Alt+G")
        case .grabStack: Spec(name: "GRAB_STACK", id: "grab_stack", label: "Další volačka ze zásobníku", defaultKeys: "Alt+G")
        case .toggleTx: Spec(name: "TOGGLE_TX", id: "toggle_tx", label: "Digi: vysílání zap / vyp (TX okno)", defaultKeys: "Alt+T")
        case .digitalLeft: Spec(name: "DIGITAL_LEFT", id: "digital_left", label: "VFO A / rig 1: oba fokusy (digi: rozhraní 1)", defaultKeys: "Cmd+Alt+LEFT")
        case .digitalRight: Spec(name: "DIGITAL_RIGHT", id: "digital_right", label: "VFO B / rig 2: oba fokusy (digi: rozhraní 2)", defaultKeys: "Cmd+Alt+RIGHT")
        case .editLast: Spec(name: "EDIT_LAST", id: "edit_last", label: "Upravit poslední spojení", defaultKeys: "Ctrl+Y")
        case .quickEditBack: Spec(name: "QUICK_EDIT_BACK", id: "quick_edit_back", label: "QuickEdit: o QSO zpět", defaultKeys: "Ctrl+Q")
        case .quickEditForward: Spec(name: "QUICK_EDIT_FORWARD", id: "quick_edit_forward", label: "QuickEdit: o QSO vpřed", defaultKeys: "Ctrl+A")
        case .resetRx: Spec(name: "RESET_RX", id: "reset_rx", label: "Split: RX na TX frekvenci", defaultKeys: "Alt+S")
        case .toggleFilter: Spec(name: "TOGGLE_FILTER", id: "filter_width", label: "Filtr rádia: široký / úzký", defaultKeys: "Alt+QUOTE")
        case .cwReverse: Spec(name: "CW_REVERSE", id: "cw_reverse", label: "CW reverse zap / vyp", defaultKeys: "Ctrl+Alt+R")
        case .wipeOther: Spec(name: "WIPE_OTHER", id: "wipe_other", label: "Vymazat pole druhého okna", defaultKeys: "Ctrl+Shift+W")
        case .jumpLastCq: Spec(name: "JUMP_LAST_CQ", id: "jump_last_cq", label: "Na poslední CQ frekvenci (libovolné pásmo)", defaultKeys: "Ctrl+Alt+Q")
        case .toggleStationType: Spec(name: "TOGGLE_STATION_TYPE", id: "run_mult", label: "Multi-op: stanice Run / Mult", defaultKeys: "Ctrl+Alt+M")
        case .passFrequency: Spec(name: "PASS_FREQUENCY", id: "pass_freq", label: "Multi-op: pass frekvence (všem stanicím)", defaultKeys: "Alt+Z")
        case .availNext: Spec(name: "AVAIL_NEXT", id: "avail_next", label: "Další spot z okna Dostupné", defaultKeys: "Alt+A")
        case .availPrevious: Spec(name: "AVAIL_PREVIOUS", id: "avail_previous", label: "Předchozí spot z okna Dostupné", defaultKeys: "Alt+Shift+A")
        case .gridSearch: Spec(name: "GRID_SEARCH", id: "grid_search", label: "VHF: hledat volačku a lokátor v call history", defaultKeys: "Alt+EQUALS")
        case .gridToggle: Spec(name: "GRID_TOGGLE", id: "grid_toggle", label: "VHF: přepínat lokátory z call history", defaultKeys: "Alt+MINUS")
        case .qtcMode: Spec(name: "QTC_MODE", id: "qtc_mode", label: "WAE: QTC režim zap / vyp", defaultKeys: "Ctrl+Z")
        case .focusSwap: Spec(name: "FOCUS_SWAP", id: "focus_swap", label: "SO2V/SO2R: oba fokusy (RX i TX) na druhé okno (Pause)", defaultKeys: "F15")
        case .swapRadios: Spec(name: "SWAP_RADIOS", id: "swap_radios", label: "SO2V/SO2R: prohodit rádia (frekvence, mód, volačka) a fokus", defaultKeys: "Alt+F5")
        case .swapRadiosKeepFocus: Spec(name: "SWAP_RADIOS_KEEP_FOCUS", id: "swap_radios_keep", label: "SO2R: prohodit rádia bez změny fokusu", defaultKeys: "Alt+F6")
        case .duelingCq: Spec(name: "DUELING_CQ", id: "dueling_cq", label: "SO2R: Dueling CQ zap / vyp", defaultKeys: "Ctrl+B")
        case .focusOther: Spec(name: "FOCUS_OTHER", id: "focus_other", label: "SO2R: FocusOther zap / vyp", defaultKeys: "Ctrl+Shift+K")
        case .toggleCtrlFx: Spec(name: "TOGGLE_CTRLFX", id: "toggle_ctrlfx", label: "Makro {CTRLFx} zap / vyp", defaultKeys: "Ctrl+Shift+L")
        case .toggleStereoMacros: Spec(name: "TOGGLE_STEREO_MACROS", id: "toggle_stereo_macros", label: "Makra stereo / OTRSP RX zap / vyp", defaultKeys: "Ctrl+BACK_QUOTE")
        case .otherSpotUp: Spec(name: "OTHER_SPOT_UP", id: "other_spot_up", label: "Druhé rádio: další spot výš", defaultKeys: "Cmd+Shift+DOWN")
        case .otherSpotDown: Spec(name: "OTHER_SPOT_DOWN", id: "other_spot_down", label: "Druhé rádio: další spot níž", defaultKeys: "Cmd+Shift+UP")
        case .otherMultUp: Spec(name: "OTHER_MULT_UP", id: "other_mult_up", label: "Druhé rádio: další násobič výš", defaultKeys: "Ctrl+Alt+Shift+DOWN")
        case .otherMultDown: Spec(name: "OTHER_MULT_DOWN", id: "other_mult_down", label: "Druhé rádio: další násobič níž", defaultKeys: "Ctrl+Alt+Shift+UP")
        case .otherBandUp: Spec(name: "OTHER_BAND_UP", id: "other_band_up", label: "Druhé rádio: pásmo výš", defaultKeys: "Ctrl+Shift+PAGE_UP")
        case .otherBandDown: Spec(name: "OTHER_BAND_DOWN", id: "other_band_down", label: "Druhé rádio: pásmo níž", defaultKeys: "Ctrl+Shift+PAGE_DOWN")
        case .otherCqFrequency: Spec(name: "OTHER_CQ_FREQUENCY", id: "other_cq_freq", label: "Druhé rádio: na jeho CQ frekvenci", defaultKeys: "Alt+Shift+Q")
        case .insertGrab: Spec(name: "INSERT_GRAB", id: "insert_grab", label: "Insert: volačka z Grab okna + F5+F2", defaultKeys: "HELP")
        }
    }

    /// The actions v1.1.1 does not have (appended after the Java constants).
    public static let swiftOnly: Set<ShortcutAction> = [.stackCall, .grabStack, .insertGrab, .toggleTx, .digitalLeft, .digitalRight, .editLast, .quickEditBack, .quickEditForward, .resetRx, .toggleFilter, .cwReverse, .wipeOther, .jumpLastCq, .toggleStationType, .passFrequency, .availNext, .availPrevious, .gridSearch, .gridToggle, .qtcMode, .focusSwap, .swapRadios, .swapRadiosKeepFocus, .duelingCq, .focusOther, .toggleCtrlFx, .toggleStereoMacros, .otherSpotUp, .otherSpotDown, .otherMultUp, .otherMultDown, .otherBandUp, .otherBandDown, .otherCqFrequency]

    /// The Java constants in Java order (`values()`), for the parity gates.
    public static var javaCases: [ShortcutAction] {
        allCases.filter { !swiftOnly.contains($0) }
    }

    /// Java `name()` of the constant (`SEND_CALL_EXCHANGE`…).
    public var name: String { spec.name }

    /// Stable id for the configuration.
    public var id: String { spec.id }

    /// Czech label for Settings (translation via `tr()` is a UI matter).
    public var label: String { spec.label }

    /// Default keys in text form (`KeyCombo.parse`).
    public var defaultKeys: String { spec.defaultKeys }

    /// The action runs on the key **release** (Kotlin `ON_KEY_UP`, `EntryPanel.kt:1388`): the logging actions and
    /// the operator dialog, so that the released Enter does not log a second time. Both phases are consumed.
    public var onKeyUp: Bool {
        self == .logWithoutSending || self == .forceLog || self == .operator
    }

    /// Default combination. All default keys are valid (guarded by `allDefaultsAreValidAndUnique`);
    /// Java would throw `IllegalStateException` for an invalid one.
    public func defaultCombo() -> KeyCombo {
        guard let combo = KeyCombo.parse(defaultKeys) else {
            preconditionFailure("Neplatná výchozí klávesa \(defaultKeys)")
        }
        return combo
    }

    /// Action by id (exact match by UTF-16 like Java `equals`), or `nil`.
    public static func byId(_ id: String?) -> ShortcutAction? {
        guard let id else {
            return nil
        }
        for action in allCases where JavaText.equals(action.id, id) {
            return action
        }
        return nil
    }
}
