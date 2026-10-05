/// Which entry field has the focus; it selects the Kotlin key handlers in front of the shared `keys`
/// (`EP:1012-1024`, `EP:1096-1153`).
public enum EntryKeyField: Equatable, Sendable {
    /// "Čas UTC" in POSTCONTEST: only `keys`.
    case time
    /// The call field: its own space handler, then `fieldKeys(0)`, then `keys`.
    case call
    /// Any other field (index > 0): `fieldKeys(i)`, then `keys`.
    case exchange
}

/// The entry state the key routing depends on (the values Kotlin's `keys` reads at the moment of the event).
public struct EntryKeyContext: Sendable {
    public var bindings: KeyBindings
    public var field: EntryKeyField
    /// Text of the call field (for the space bar: commands with an argument keep the space).
    public var callText: String
    /// Mode is CW (`PgUp`/`PgDn` change the CW speed).
    public var isCw: Bool
    /// `esmActive` (ESM on, mode with messages, not POSTCONTEST).
    public var esmActive: Bool
    /// `state.lastSentKeys.isNotEmpty()`.
    public var hasLastSent: Bool
    /// `state.stopSending()` would stop something (keyer sending or recording); always `false` without a keyer.
    public var isSending: Bool
    /// Highlighted suggestion (`scpPick`, `-1` = none).
    public var scpPick: Int
    /// Number of suggestions shown.
    public var suggestionCount: Int
    /// `parseCommand() != null`: the call field holds a command.
    public var hasCommand: Bool

    public init(
        bindings: KeyBindings,
        field: EntryKeyField = .call,
        callText: String = "",
        isCw: Bool = false,
        esmActive: Bool = false,
        hasLastSent: Bool = false,
        isSending: Bool = false,
        scpPick: Int = -1,
        suggestionCount: Int = 0,
        hasCommand: Bool = false
    ) {
        self.bindings = bindings
        self.field = field
        self.callText = callText
        self.isCw = isCw
        self.esmActive = esmActive
        self.hasLastSent = hasLastSent
        self.isSending = isSending
        self.scpPick = scpPick
        self.suggestionCount = suggestionCount
        self.hasCommand = hasCommand
    }
}

/// What a released Enter does (`EP:974-985`), in Kotlin's order.
public enum EntryEnterStep: Equatable, Sendable {
    /// Take the highlighted suggestion (`takeSuggestion(scpPick)`).
    case takeSuggestion(Int)
    /// `logQso(ctrlEnter:)`: the call field holds a command (Ctrl+Enter = split), or a plain log
    /// (`ctrlEnter` is then always `false`).
    case logQso(ctrlEnter: Bool)
    /// `esmEnter()`.
    case esm
}

/// What a released Esc does (`EP:970`, `EP:992-993`), in Kotlin's order.
public enum EntryEscapeStep: Equatable, Sendable {
    /// `stopSending()` stopped the keyer or a recording.
    case stopSending
    /// `scpPick = -1`.
    case cancelSuggestion
    /// `wipe()`.
    case wipe
}

/// The routing result for one AWT key event. Everything except `passThrough` consumes the event.
public indirect enum EntryKeyDecision: Equatable, Sendable {
    /// Not handled: the field gets the event (`false` in Kotlin).
    case passThrough
    /// Swallowed without an action (`true` in Kotlin).
    case consume
    /// A Shift key changed `shiftHeld` (Kotlin sets it before routing); the routing result follows.
    case shiftHeld(Bool, then: EntryKeyDecision)
    /// A remappable shortcut on its firing phase.
    case action(ShortcutAction)
    /// F1–F12 pressed: index 0–11; `shift` = message from the opposite set, `ctrlShift` = record (phone).
    case functionKey(Int, shift: Bool, ctrlShift: Bool)
    /// `PgUp`/`PgDn` in CW: `+1`/`-1` steps of `cwSpeedStep`.
    case cwSpeed(Int)
    /// Enter released.
    case enter(ctrl: Bool, step: EntryEnterStep)
    /// Esc released.
    case escape(EntryEscapeStep)
    /// `=` pressed in ESM with something sent before: repeat the last sent keys.
    case resendLast
    /// ↑/↓ with suggestions: `scpPick` moves by `by` to `to` (clamped like Kotlin: `-1…count-1`).
    case scpMove(by: Int, to: Int)
    /// ↑/↓ without suggestions: tune the rig (`-1` for ↑, `+1` for ↓) — not available without a rig.
    case tune(Int)
    /// Tab / Shift+Tab / space in exchange fields (`fieldKeys`): move the focus.
    case focusMove(by: Int, skipReports: Bool)
    /// Space in the call field (`jumpToExchange()`).
    case jumpToExchange
}

/// Routing of the entry window keys: Kotlin `EntryPanel` `keys` (`EP:940-1005`) behind the field handlers
/// `fieldKeys` (`EP:1012-1024`) and the call field's space bar (`EP:1109-1118`), evaluated in that order on
/// the AWT event (`AwtKeyCodes.translateForLayout`). Key identity is Compose's: code and location, so a stroke at
/// the `NUMPAD` location is not Enter; the layout layer promotes the keypad Enter to the standard location before
/// routing. Shortcuts match by code only (`KeyCombo`).
///
/// The one rule beyond Kotlin: an event with Command that no binding resolves passes through to the
/// system and the menus (⌘Q, ⌘C…). Unbound Ctrl/Alt combinations pass through like in Kotlin.
public enum EntryKeyRouter {

    public static func route(_ stroke: AwtKeyStroke, context: EntryKeyContext) -> EntryKeyDecision {
        let pressed: Bool = stroke.phase == .pressed
        switch context.field {
        case .call:
            if let decision = callSpace(stroke, context: context) {
                return decision
            }
            if let decision = fieldKeys(stroke, index: 0) {
                return decision
            }
        case .exchange:
            if let decision = fieldKeys(stroke, index: 1) {
                return decision
            }
        case .time:
            break
        }
        let isShiftKey: Bool = stroke.vk == AwtKeyCodes.vkShift
            && (stroke.composeLocation == AwtKeyCodes.keyLocationLeft
                || stroke.composeLocation == AwtKeyCodes.keyLocationRight)
        let decision: EntryKeyDecision = keys(stroke, pressed: pressed, context: context)
        return isShiftKey ? .shiftHeld(pressed, then: decision) : decision
    }

    /// The call field's own space handler.
    private static func callSpace(_ stroke: AwtKeyStroke, context: EntryKeyContext) -> EntryKeyDecision? {
        guard stroke.isKey(AwtKeyCodes.vkSpace) else {
            return nil
        }
        if CallFieldCommands.isArgumentKeyword(firstWord(context.callText)) {
            return nil
        }
        return stroke.phase == .pressed ? .jumpToExchange : .consume
    }

    /// `call.trim().uppercase().substringBefore(' ')`.
    static func firstWord(_ call: String) -> String {
        let upper: String = JavaText.toUpperCase(KotlinText.trim(call))
        let units: [UInt16] = Array(upper.utf16)
        let end: Int = units.firstIndex(of: 0x20) ?? units.count
        return String(decoding: units[..<end], as: UTF16.self)
    }

    /// Kotlin `fieldKeys(index)` before `keys`.
    private static func fieldKeys(_ stroke: AwtKeyStroke, index: Int) -> EntryKeyDecision? {
        let pressed: Bool = stroke.phase == .pressed
        if stroke.isKey(AwtKeyCodes.vkTab) && !stroke.isControlDown {
            return pressed ? .focusMove(by: stroke.isShiftDown ? -1 : 1, skipReports: false) : .consume
        }
        if stroke.isKey(AwtKeyCodes.vkSpace) && index > 0 {
            return pressed ? .focusMove(by: 1, skipReports: true) : .consume
        }
        return nil
    }

    /// Kotlin `keys`, steps 1–10.
    private static func keys(_ stroke: AwtKeyStroke, pressed: Bool, context: EntryKeyContext) -> EntryKeyDecision {
        // 1. Remappable shortcut: both phases consumed, the action on its phase.
        let combo = KeyCombo(
            ctrl: stroke.isControlDown, alt: stroke.isAltDown, shift: stroke.isShiftDown,
            meta: stroke.isMetaDown, keyCode: stroke.vk
        )
        if let shortcut = context.bindings.resolve(combo) {
            let onRelease: Bool = shortcut.onKeyUp
            return pressed != onRelease ? .action(shortcut) : .consume
        }
        // Unbound Command combinations belong to the system and the menus.
        if stroke.isMetaDown {
            return .passThrough
        }
        // 2.–3. F1–F12: message on press, release swallowed.
        if let index = functionKeyIndex(stroke) {
            guard pressed else {
                return .consume
            }
            let ctrlShift: Bool = stroke.isControlDown && stroke.isShiftDown
            return .functionKey(index, shift: stroke.isShiftDown, ctrlShift: ctrlShift)
        }
        let released: Bool = !pressed
        // 4. PgUp/PgDn: CW speed.
        if context.isCw && pressed && stroke.isKey(AwtKeyCodes.vkPageUp) {
            return .cwSpeed(1)
        }
        if context.isCw && pressed && stroke.isKey(AwtKeyCodes.vkPageDown) {
            return .cwSpeed(-1)
        }
        // 5. Esc first stops sending.
        let isEscape: Bool = stroke.isKey(AwtKeyCodes.vkEscape)
        if released && isEscape && context.isSending {
            return .escape(.stopSending)
        }
        // 6. Enter on release: suggestion → command → ESM → log.
        if released && stroke.isKey(AwtKeyCodes.vkEnter) {
            return .enter(ctrl: stroke.isControlDown, step: enterStep(ctrl: stroke.isControlDown, context: context))
        }
        // 7. "=" in ESM repeats the last sent message.
        if context.esmActive && stroke.isKey(AwtKeyCodes.vkEquals) {
            return pressed && context.hasLastSent ? .resendLast : .consume
        }
        // 8. Esc on release: cancel the highlighted suggestion, else wipe.
        if released && isEscape {
            return .escape(context.scpPick >= 0 ? .cancelSuggestion : .wipe)
        }
        // 9.–10. Arrows: suggestions, else tuning.
        return arrows(stroke, pressed: pressed, context: context)
    }

    private static func arrows(_ stroke: AwtKeyStroke, pressed: Bool, context: EntryKeyContext) -> EntryKeyDecision {
        guard pressed else {
            return .passThrough
        }
        let down: Bool = stroke.isKey(AwtKeyCodes.vkDown)
        let up: Bool = stroke.isKey(AwtKeyCodes.vkUp)
        if context.suggestionCount > 0 {
            if down {
                return .scpMove(by: 1, to: min(context.scpPick + 1, context.suggestionCount - 1))
            }
            if up {
                return .scpMove(by: -1, to: max(context.scpPick - 1, -1))
            }
        }
        if up {
            return .tune(-1)
        }
        if down {
            return .tune(1)
        }
        return .passThrough
    }

    private static func enterStep(ctrl: Bool, context: EntryKeyContext) -> EntryEnterStep {
        if context.scpPick >= 0 {
            return .takeSuggestion(context.scpPick)
        }
        if context.hasCommand {
            return .logQso(ctrlEnter: ctrl)
        }
        if context.esmActive {
            return .esm
        }
        return .logQso(ctrlEnter: false)
    }

    /// `FUNCTION_KEYS.indexOf(e.key)`: F1–F12 at the standard location.
    static func functionKeyIndex(_ stroke: AwtKeyStroke) -> Int? {
        guard stroke.composeLocation == AwtKeyCodes.keyLocationStandard,
              stroke.vk >= AwtKeyCodes.vkF1, stroke.vk <= AwtKeyCodes.vkF12 else {
            return nil
        }
        return Int(stroke.vk - AwtKeyCodes.vkF1)
    }
}
