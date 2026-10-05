import Foundation
import MCLCore

/// The entry window's key handling behind the AppKit monitor, without AppKit: the monitor copies each
/// `NSEvent` into a `MacKeyEvent` and says where the focus is; this turns it into the AWT event JDK 21 would deliver
/// (`AwtKeyCodes.translateForLayout`: JDK 21 translation plus the layout rules), routes it like Kotlin's `keys`/`fieldKeys` (`EntryKeyRouter`) and runs the decision
/// (`EntryModel.handle`). Enter, Esc and the logging shortcuts therefore act on the key's release, as in Kotlin.
///
/// - Previous flags: JDK keeps the flags of the last `flagsChanged` in a static (`sPreviousNSFlags`) and reads the
///   changed modifier from `previous ^ current`. Every `flagsChanged` the app receives updates it here, also while
///   the entry fields do not have the focus.
/// - A release is routed only when the entry saw the key's press. A press that went elsewhere (a dialog's default
///   button closed the dialog on the press, a menu key equivalent) would otherwise reach the call field as a lone
///   release and log a QSO. Kotlin's dialogs act on the release themselves, so this never fires there.
/// - L12: while the entry takes no input, what the router would act on is swallowed without an action.
/// - Marked text (a dead key, press-and-hold, an input method): JDK's `AWTView keyDown` hands the key to the input
///   system first and delivers no `KEY_PRESSED` while text is marked, so Kotlin's `keys` never sees those presses.
///   The monitor runs before the text system, so a field with marked text is `.composing`: nothing is routed and the
///   press is not recorded, so its release (after the composition was committed) is not routed either.
@MainActor
public final class EntryKeyFlow {

    /// Where the key event goes.
    public enum Target: Equatable, Sendable {
        /// An entry field of the main window has the focus (the main window is the key window).
        case entry(EntryKeyField)
        /// An entry field whose editor holds marked text (a composition in progress): the text system's key.
        case composing(EntryKeyField)
        /// Anything else: another window, the frequency field, no field.
        case elsewhere
    }

    /// JDK `sPreviousNSFlags`: the modifier flags of the last `flagsChanged` event.
    public private(set) var previousModifierFlags: UInt = 0
    /// Key codes whose press the entry saw and whose release is still to come.
    private var pressed: Set<UInt16> = []
    private let entry: EntryModel

    public init(entry: EntryModel) {
        self.entry = entry
    }

    /// Handles one event; `true` = consumed (the monitor drops it), `false` = AppKit delivers it as usual.
    public func process(_ event: MacKeyEvent, target: Target) -> Bool {
        var event: MacKeyEvent = event
        let inEntry: EntryKeyField?
        if case .entry(let field) = target {
            inEntry = field
        } else {
            inEntry = nil
        }
        switch event.kind {
        case .flagsChanged:
            event.previousModifierFlags = previousModifierFlags
            previousModifierFlags = event.modifierFlags
        case .keyDown:
            if inEntry != nil {
                pressed.insert(event.keyCode)
            } else {
                pressed.remove(event.keyCode)
            }
        case .keyUp:
            let seen: Bool = pressed.remove(event.keyCode) != nil
            if !seen {
                return false
            }
        }
        guard let field = inEntry, let stroke = AwtKeyCodes.translateForLayout(event) else {
            // JDK delivers no AWT event for an unknown dead key: the text system still gets the key.
            return false
        }
        let decision: EntryKeyDecision = EntryKeyRouter.route(stroke, context: entry.keyContext(field: field))
        guard entry.acceptsInput else {
            return Self.consumes(decision)
        }
        return entry.handle(decision)
    }

    /// The main window stopped being the key window: the keys held now are released elsewhere.
    public func reset() {
        pressed.removeAll()
    }

    /// Whether `decision` consumes the event (everything but a pass-through; a Shift change passes on what follows).
    static func consumes(_ decision: EntryKeyDecision) -> Bool {
        switch decision {
        case .passThrough:
            return false
        case .shiftHeld(_, let then):
            return consumes(then)
        default:
            return true
        }
    }
}
