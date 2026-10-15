import Foundation

/// A station of the network as the N1MM multi-user macros see it (`{PASS …}`, `{PASSMSG …}`).
public struct MacroPassTarget: Equatable, Sendable {
    public var station: String
    public var freqHz: Int
    /// The pass frequency it announced (Alt+Z), 0 = none.
    public var passHz: Int
    /// A run station (Run mode or a RUN station type).
    public var run: Bool

    public init(station: String, freqHz: Int, passHz: Int, run: Bool) {
        self.station = station
        self.freqHz = freqHz
        self.passHz = passHz
        self.run = run
    }

    /// Where a passed station goes: the pass frequency, else the station's own frequency.
    public var targetHz: Int {
        passHz > 0 ? passHz : freqHz
    }
}

/// The target of `{PASS x}` / `{PASSMSG x}` (N1MM): `x` is a station name, or a frequency in kHz that names a band —
/// then the run station on that band, else the first one with a pass frequency, else the first one on it.
public enum MultiUserMacro {

    public static func target(_ argument: String, in targets: [MacroPassTarget]) -> MacroPassTarget? {
        let arg: String = KotlinText.trim(argument)
        guard !arg.isEmpty else { return nil }
        if let named = targets.first(where: { $0.station.caseInsensitiveCompare(arg) == .orderedSame }) {
            return named
        }
        guard let khz = Int64(arg), khz > 0, khz <= Int64(Int32.max) / 1000,
              let band = Band.from(frequencyHz: Int(khz * 1000)) else { return nil }
        let onBand: [MacroPassTarget] = targets.filter { Band.from(frequencyHz: $0.freqHz) == band }
        return onBand.first(where: \.run) ?? onBand.first(where: { $0.passHz > 0 }) ?? onBand.first
    }

    /// The `{PASS …}` text: the target frequency rounded to the kHz, `""` when unknown.
    public static func passText(_ hz: Int) -> String {
        MacroFrequency.text(Int64(hz), round: true, r: false)
    }

    /// `{MESSAGE}`'s text: (`to`, text). A first word `-` = all (dropped); a first word naming a station = that
    /// station (dropped); otherwise all with the whole text.
    public static func messageTarget(_ text: String, stations: [String]) -> (to: String, text: String) {
        let trimmed: String = KotlinText.trim(text)
        let parts: [Substring] = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return ("", "") }
        let rest: String = parts.count > 1 ? KotlinText.trim(String(parts[1])) : ""
        if first == "-" {
            return ("", rest)
        }
        if let station = stations.first(where: { $0.caseInsensitiveCompare(String(first)) == .orderedSame }) {
            return (station, rest)
        }
        return ("", trimmed)
    }
}

/// Texts of the multi-user macros.
public enum NetworkMacroTexts {
    public static let noTargetKey = "{PASSMSG}: v síti není stanice %s"
}
