import Foundation

/// One line of the DX Cluster window's text pane with how it is drawn (N1MM+ Telnet window): spot lines are
/// colour-coded by mode (CW blue, digital magenta, phone in the text colour) and a spot the spot filter does not pass
/// stays in the pane greyed out instead of disappearing. Command replies and other text are drawn plainly.
public struct ConsoleLine: Equatable, Sendable {

    /// The colour class of a line.
    public enum Tint: Equatable, Sendable {
        /// Not a spot (or a spot whose mode is unknown).
        case plain
        case cw
        case phone
        case digi
        /// A spot the spot filter hides elsewhere (band map, Available Mults).
        case filtered
    }

    public let text: String
    public let tint: Tint
    /// The spot the line carries (`nil` for any other text).
    public let spot: DxSpot?

    public init(text: String, tint: Tint = .plain, spot: DxSpot? = nil) {
        self.text = text
        self.tint = tint
        self.spot = spot
    }

    /// The pane's lines: every log line, the spot lines tinted by the mode category the band map infers and greyed
    /// when `filter` hides them.
    public static func lines(_ log: [String], filter: SpotFilter, analyzer: SpotAnalyzer?) -> [ConsoleLine] {
        log.map { line in
            guard let spot = SpotFilter.spot(inLine: line) else { return ConsoleLine(text: line) }
            if !filter.isDefault && !filter.allows(spot, analyzer: analyzer) {
                return ConsoleLine(text: line, tint: .filtered, spot: spot)
            }
            return ConsoleLine(text: line, tint: tint(analyzer?.spotModeCategory(spot)), spot: spot)
        }
    }

    static func tint(_ category: String?) -> Tint {
        switch category {
        case SpotModeCategory.cw: .cw
        case SpotModeCategory.phone: .phone
        case SpotModeCategory.digi: .digi
        default: .plain
        }
    }
}
