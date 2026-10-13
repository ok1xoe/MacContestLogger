/// A programmable button of the band map (N1MM Logger+ Bandmap "radio control buttons", up to 36): a label and a
/// command, each with toggle states separated by `|` (a click runs the current state and moves to the next one; the
/// label shows the current state).
///
/// A state's command is a sequence of steps, run in order:
/// - `{CAT <rigctld command>}` — a raw `rigctld` command, checked by `PluginCatPolicy` (no PTT, no transmit);
/// - a control macro that never transmits: `{WIPE}`, `{RUN}`, `{S&P}`, `{CLEARRIT}`/`{RITCLEAR}`,
///   `{CQFREQ}`/`{ALT-Q}`, `{NOSPLIT}`, `{CLRSTACK}`;
/// - any other text — a call field text command (`CW`, `USB`, `14025`, `+2`, `SPLIT`, `NOSPLIT`, `SWAP`, `RIT 100`,
///   `/14030`…), run without clearing the call field; `;` separates several (`14025;CW`).
///
/// Message macros that would key the transmitter are refused, so a button never transmits.
public enum BandmapButtonCommand {

    /// One step of a state.
    public enum Step: Equatable, Sendable {
        case cat(String)
        case macro(CwMessage.Action)
        case text(String)
        /// A macro a band map button may not run (it would transmit or is unknown).
        case refused(String)
    }

    /// The control macros a button may run.
    static let macros: [String: CwMessage.Action] = [
        "{WIPE}": .wipe, "{RUN}": .run, "{S&P}": .searchAndPounce, "{CLEARRIT}": .clearRit, "{RITCLEAR}": .clearRit,
        "{CQFREQ}": .cqFrequency, "{ALT-Q}": .jumpCq, "{NOSPLIT}": .splitOff, "{CLRSTACK}": .clearStack,
    ]

    /// The `|`-separated states, each trimmed; at least one (an empty text is one empty state).
    public static func states(_ text: String) -> [String] {
        text.split(separator: "|", omittingEmptySubsequences: false).map { JavaText.trim(String($0)) }
    }

    /// The label of state `index` (a label with fewer states than the command keeps its last one).
    public static func label(_ label: String, state index: Int) -> String {
        let all: [String] = states(label)
        return all[Swift.min(Swift.max(index, 0), all.count - 1)]
    }

    /// How many states the button cycles through (the command's).
    public static func stateCount(_ command: String) -> Int {
        states(command).count
    }

    /// The steps of one state: `{…}` groups and the text between them (blank text is skipped).
    public static func steps(_ state: String) -> [Step] {
        var steps: [Step] = []
        var rest: Substring = Substring(state)
        while !rest.isEmpty {
            guard let open = rest.firstIndex(of: "{") else {
                appendText(rest, to: &steps)
                break
            }
            appendText(rest[..<open], to: &steps)
            guard let close = rest[open...].firstIndex(of: "}") else {
                steps.append(.refused(String(rest[open...])))
                break
            }
            let macro = String(rest[open...close])
            rest = rest[rest.index(after: close)...]
            steps.append(step(macro))
        }
        return steps
    }

    /// Text between the macros: `;` separates several text commands.
    private static func appendText(_ text: Substring, to steps: inout [Step]) {
        for part in text.split(separator: ";", omittingEmptySubsequences: true) {
            let trimmed: String = JavaText.trim(String(part))
            if !trimmed.isEmpty {
                steps.append(.text(trimmed))
            }
        }
    }

    private static func step(_ macro: String) -> Step {
        let inner: String = String(macro.dropFirst().dropLast())
        let upper: String = inner.uppercased()
        if upper.hasPrefix("CAT ") {
            return .cat(JavaText.trim(String(inner.dropFirst(4))))
        }
        if let action = macros["{" + upper + "}"] {
            return .macro(action)
        }
        return .refused(macro)
    }
}

/// The band map's Wide/Narrow filter button (N1MM): the rig's passband compared with the configured widths of the
/// mode.
public enum FilterWidthToggle {

    /// The rig reports a passband nearer to the narrow width than to the wide one (a passband of 0 = the rig's
    /// default: wide).
    public static func isNarrow(passbandHz: Int64, wide: Int, narrow: Int) -> Bool {
        guard passbandHz > 0, wide != narrow else { return false }
        return abs(passbandHz - Int64(narrow)) < abs(passbandHz - Int64(wide))
    }

    /// The `rigctld` command that switches to the other width, `nil` without a rig mode.
    public static func command(rawMode: String, passbandHz: Int64, wide: Int, narrow: Int) -> String? {
        let mode: String = JavaText.trim(rawMode).uppercased()
        guard !mode.isEmpty else { return nil }
        let target: Int = isNarrow(passbandHz: passbandHz, wide: wide, narrow: narrow) ? wide : narrow
        return "M " + mode + " " + String(target)
    }
}
