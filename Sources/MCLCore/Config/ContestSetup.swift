import Foundation

/// Saved setup of one contest (category + sent exchange + operators/soapbox).
public struct ContestSetup: Codable, Equatable, Sendable {
    public var category: [String: String] = [:]
    public var sentExchange: [String: String] = [:]
    public var operators: String = ""
    public var soapbox: String = ""
    public var startedAt: String = ""
    public var endedAt: String = ""
    /// TOUR session (`hhmm/mm`); empty = no session. N1MM forgets it after a restart, we do not.
    public var tour: String = ""
    /// Skeds (arranged contacts) of this contest.
    public var skeds: [SkedEntry] = []
    /// Bonus stations (N1MM BONUS) of this contest.
    public var bonusStations: [String] = []

    enum CodingKeys: String, CodingKey {
        case category, sentExchange, operators, soapbox, startedAt, endedAt, tour, skeds, bonusStations
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ContestSetup()
        category = c.value(.category, default: d.category)
        sentExchange = c.value(.sentExchange, default: d.sentExchange)
        operators = c.value(.operators, default: d.operators)
        soapbox = c.value(.soapbox, default: d.soapbox)
        startedAt = c.value(.startedAt, default: d.startedAt)
        endedAt = c.value(.endedAt, default: d.endedAt)
        tour = c.value(.tour, default: d.tour)
        skeds = c.value(.skeds, default: d.skeds)
        bonusStations = c.value(.bonusStations, default: d.bonusStations)
    }
}
