import Foundation

/// A CW message prepared for transmission: a sequence of parts (text, prosign, speed change) + actions the
/// program should perform (N1MM `{LOG}`, `{WIPE}`…). Each keyer converts the parts its own way — Winkeyer handles prosigns
/// and speed changes inside a message, CAT only plain text. Mirrors the Java record `keyer.CwMessage`.
public struct CwMessage: Equatable, Sendable {

    /// Part of a message (Java sealed `Part`).
    public enum Part: Equatable, Sendable {
        /// Text to transmit (uppercase, only transmittable characters).
        case text(String)
        /// Prosign as a letter pair without a space (AR, SK, AS, BT).
        case prosign(String)
        /// Speed change by the given number of WPM from this point of the message (N1MM `<` and `>`). Java `int`:
        /// keyers compute with it in 32 bits with overflow like Java.
        case speed(Int)
    }

    /// Program actions from control macros; `rawValue` = Java constant name.
    public enum Action: String, Equatable, Sendable, CaseIterable {
        case log = "LOG"
        case wipe = "WIPE"
        case run = "RUN"
        case searchAndPounce = "SEARCH_AND_POUNCE"
        case clearRit = "CLEAR_RIT"
        case cqFrequency = "CQ_FREQUENCY"
        case splitOff = "SPLIT_OFF"
        /// `{SOCALLSTACK}`: exchange the call field with the call stack (Run only).
        case soCallStack = "SO_CALL_STACK"
        /// `{STACKANOTHER}`: push the call field onto the call stack (Run only).
        case stackAnother = "STACK_ANOTHER"
        /// `{CLRSTACK}`: clear the call stack.
        case clearStack = "CLEAR_STACK"
        /// `{LOGTHENPOP}` / `{LOGTHENNEXT}`: log the QSO, then the next call from the stack into the call field. Never
        /// produced by `CwMessageBuilder` — `FunctionKeyRouter` splits the message at the macro.
        case logThenPop = "LOG_THEN_POP"
        /// `{GRAB}`: the highlighted call of the Digital Interface's Grab window into the call field.
        case grab = "GRAB"
        /// `{DELALL}` / `{DELTOP}` / `{DELSEL}`: delete the Grab window / its top / its highlighted call.
        case grabDeleteAll = "GRAB_DELETE_ALL"
        case grabDeleteTop = "GRAB_DELETE_TOP"
        case grabDeleteSelected = "GRAB_DELETE_SELECTED"
        /// `{SCQ}`: resume calling CQ (the CQ repeat on, in Run).
        case resumeCq = "RESUME_CQ"
        /// Digital `{TX}` / `{RX}`: transmit on / back to receive (a message keeps fldigi transmitting when it has
        /// `{TX}` without `{RX}`). Ignored in CW and SSB.
        case digitalTx = "DIGITAL_TX"
        case digitalRx = "DIGITAL_RX"
        /// Digital `{CLRRX}` / `{CLRTX}`: clear the Digital Interface's RX window / fldigi's TX buffer.
        case clearRx = "CLEAR_RX"
        case clearTx = "CLEAR_TX"
        /// `{ALT-T}`: toggle transmit / receive (digital), `{ALT-Q}`: back to the CQ frequency (Alt+Q).
        case toggleTx = "TOGGLE_TX"
        case jumpCq = "JUMP_CQ"
        /// Digital `{ALIGN}`: the received signal moved to the alignment frequency (the Align button).
        case align = "ALIGN"
        /// Digital `{ENABLEAFC}` / `{DISABLEAFC}`, `{ENABLENET}` / `{DISABLENET}` (fldigi: Lock off / on).
        case afcOn = "AFC_ON"
        case afcOff = "AFC_OFF"
        case netOn = "NET_ON"
        case netOff = "NET_OFF"
        /// `{SPOTME}` (N1MM): spot my own station to the DX cluster on the entry window's frequency (Swift-only).
        case spotMe = "SPOT_ME"
    }

    /// Message parts in transmission order.
    public let parts: [Part]
    /// Actions from control macros.
    public let actions: [Action]
    /// Unrecognised macros (to be reported; not transmitted).
    public let unknownMacros: [String]

    public init(parts: [Part], actions: [Action] = [], unknownMacros: [String] = []) {
        self.parts = parts
        self.actions = actions
        self.unknownMacros = unknownMacros
    }

    /// Nothing to transmit (no text and no prosign — even empty text counts as "something", as in Java).
    public var isEmpty: Bool {
        !parts.contains { part in
            switch part {
            case .text, .prosign: true
            case .speed: false
            }
        }
    }

    /// A line break (`{ENTERLF}`, a line of `{FILE:…}`): `.text("\n")`, kept by the digital modes, a space for CW
    /// (`withoutNewlines`).
    public static let newline: Part = .text("\n")

    /// The message with the line breaks as spaces (CW keyers).
    public var withoutNewlines: CwMessage {
        CwMessage(parts: parts.map { $0 == Self.newline ? .text(" ") : $0 }, actions: actions,
                  unknownMacros: unknownMacros)
    }

    /// The message as plain text — for keyers without prosigns and speed changes (CAT) and for display. A prosign is
    /// written as a letter pair separated by a space from its surroundings; finally Java `trim()` (characters ≤ U+0020) and
    /// collapsing runs of spaces U+0020.
    public func plainText() -> String {
        var units: [UInt16] = []
        for part in parts {
            switch part {
            case .text(let text):
                units.append(contentsOf: text.utf16)
            case .prosign(let letters):
                if let last = units.last, last != 0x20 {
                    units.append(0x20)
                }
                units.append(contentsOf: letters.utf16)
                units.append(0x20)
            case .speed:
                break
            }
        }
        let trimmed = Array(JavaText.trim(JavaChar.string(units)).utf16)
        var out: [UInt16] = []
        out.reserveCapacity(trimmed.count)
        for unit in trimmed where !(unit == 0x20 && out.last == 0x20) {
            out.append(unit)
        }
        return JavaChar.string(out)
    }
}
