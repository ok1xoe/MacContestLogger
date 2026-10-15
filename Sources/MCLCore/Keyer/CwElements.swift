import Foundation

/// One step of a keyed CW message: the key down (`true`) or up for `ms` milliseconds.
public struct CwElement: Equatable, Sendable {
    public var keyDown: Bool
    public var ms: Double

    public init(_ keyDown: Bool, _ ms: Double) {
        self.keyDown = keyDown
        self.ms = ms
    }
}

/// The exact key sequence of a CW message for keyers that form the elements themselves (DTR/RTS keying, the
/// sound-card monitor): PARIS timing (dit = 1200 / WPM ms), speed changes `<` `>` inside the message, prosigns
/// without the gap between their letters, weight and contest word spacing.
///
/// Weight (K1EL convention): `(weight − 50) / 50` dit is added to every mark and taken from the space after it,
/// so the speed does not change. The sequence starts and ends with a key-down element; characters without a Morse
/// code are skipped, spaces at the start and the end send nothing.
public enum CwElements {

    public static func sequence(_ message: CwMessage, wpm: Int, weight: Int = 50, contestSpacing: Bool = false)
        -> [CwElement] {
        var out: [CwElement] = []
        var speed = Int32(truncatingIfNeeded: wpm)
        let weightFactor: Double = Double(min(max(weight, 10), 90) - 50) / 50
        let wordDits: Double = contestSpacing ? 6 : 7
        /// Dits of space before the next mark (0 = nothing sent yet).
        var pendingGap: Double = 0
        var wordBreak = false
        var lastDelta: Double = 0
        for part in message.parts {
            let text: String
            var prosign = false
            switch part {
            case .speed(let delta):
                speed = speed &+ Int32(truncatingIfNeeded: delta)
                continue
            case .text(let t):
                text = t
            case .prosign(let letters):
                text = letters
                prosign = true
            }
            let dit: Double = 1200.0 / Double(max(5, speed))
            for (i, unit) in text.utf16.enumerated() {
                if unit == 0x20 {
                    wordBreak = true
                    continue
                }
                guard let code = CwTiming.code(unit) else { continue }
                if !out.isEmpty {
                    pendingGap = wordBreak ? wordDits : (prosign && i > 0 ? 1 : 3)
                }
                wordBreak = false
                for (j, element) in code.utf8.enumerated() {
                    if j > 0 {
                        pendingGap = 1
                    }
                    if !out.isEmpty {
                        out.append(CwElement(false, max(0, pendingGap * dit - lastDelta)))
                    }
                    let delta: Double = weightFactor * dit
                    let units: Double = element == UInt8(ascii: ".") ? 1 : 3
                    out.append(CwElement(true, max(0, units * dit + delta)))
                    lastDelta = delta
                }
            }
        }
        return out
    }

    /// The total duration in ms.
    public static func duration(_ elements: [CwElement]) -> Double {
        elements.reduce(0) { $0 + $1.ms }
    }
}
