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
