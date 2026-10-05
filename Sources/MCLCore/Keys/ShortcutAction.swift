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
        case .ritClear: Spec(name: "RIT_CLEAR", id: "rit_clear", label: "RIT vypnout", defaultKeys: "Ctrl+Alt+R")
        case .switchRadio: Spec(name: "SWITCH_RADIO", id: "switch_radio", label: "SO2V/SO2R: přepnout na druhé okno (rig / VFO)", defaultKeys: "BACK_SLASH")
        case .so2rStereo: Spec(name: "SO2R_STEREO", id: "so2r_stereo", label: "SO2R: stereo poslech zap / vyp", defaultKeys: "BACK_QUOTE")
        case .cwKeyboard: Spec(name: "CW_KEYBOARD", id: "cw_keyboard", label: "Psaní CW z klávesnice", defaultKeys: "Ctrl+K")
        case .passCall: Spec(name: "PASS_CALL", id: "pass_call", label: "Předat volačku jiné stanici (síť)", defaultKeys: "Ctrl+Alt+P")
        case .popStack: Spec(name: "POP_STACK", id: "pop_stack", label: "Volačka ze zásobníku partnera", defaultKeys: "Ctrl+Alt+K")
        case .rotorTurn: Spec(name: "ROTOR_TURN", id: "rotor_turn", label: "Rotátor na volačku (krátká cesta)", defaultKeys: "Alt+J")
        case .rotorLong: Spec(name: "ROTOR_LONG", id: "rotor_long", label: "Rotátor na volačku (dlouhá cesta)", defaultKeys: "Ctrl+Alt+J")
        case .rotorStop: Spec(name: "ROTOR_STOP", id: "rotor_stop", label: "Rotátor zastavit", defaultKeys: "Alt+L")
        case .nextAntenna: Spec(name: "NEXT_ANTENNA", id: "next_antenna", label: "Další anténa pro pásmo", defaultKeys: "Ctrl+Alt+A")
        case .bandUp: Spec(name: "BAND_UP", id: "band_up", label: "Pásmo výš", defaultKeys: "Ctrl+PAGE_UP")
        case .bandDown: Spec(name: "BAND_DOWN", id: "band_down", label: "Pásmo níž", defaultKeys: "Ctrl+PAGE_DOWN")
        case .nextSpotUp: Spec(name: "NEXT_SPOT_UP", id: "spot_up", label: "Další spot výš", defaultKeys: "Ctrl+DOWN")
        case .nextSpotDown: Spec(name: "NEXT_SPOT_DOWN", id: "spot_down", label: "Další spot níž", defaultKeys: "Ctrl+UP")
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
        }
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
