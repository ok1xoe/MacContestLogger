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
    /// N1MM Contest Setup → Associated Files: the call history file of this contest; empty = the global
    /// `AppConfig.callHistoryFile`. Swift-only key, written only when set.
    public var callHistoryFile: String = ""
    /// N1MM Contest Setup → Associated Files: the function key file (`.mc`) of each message set of this contest
    /// (`FunctionKeyKind` raw value → path), loaded when the contest opens. Swift-only key, written only when set.
    public var functionKeyFiles: [String: String] = [:]
    /// N1MM „start the serial number from other than 1" (the next part of a contest): the serial of the first QSO.
    /// Swift-only key, written only when it is not 1.
    public var firstSerial: Int = 1
    /// N1MM Contest Setup → Associated Files: the contest's own master.scp; empty = the global `AppConfig.scpFile`.
    /// Swift-only key, written only when set.
    public var scpFile: String = ""
    /// N1MM Contest Setup → Associated Files: the goal file of this contest, loaded into the Info window's goals when
    /// the contest opens. Swift-only key, written only when set.
    public var goalFile: String = ""

    enum CodingKeys: String, CodingKey {
        case category, sentExchange, operators, soapbox, startedAt, endedAt, tour, skeds, bonusStations
        case callHistoryFile, functionKeyFiles, firstSerial, scpFile, goalFile
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
        callHistoryFile = c.value(.callHistoryFile, default: d.callHistoryFile)
        functionKeyFiles = c.value(.functionKeyFiles, default: d.functionKeyFiles)
        firstSerial = max(1, c.value(.firstSerial, default: d.firstSerial))
        scpFile = c.value(.scpFile, default: d.scpFile)
        goalFile = c.value(.goalFile, default: d.goalFile)
    }

    /// The synthesized encoding, except that an empty `callHistoryFile` / `functionKeyFiles` is left out (the setup v1.1.1 writes).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(category, forKey: .category)
        try c.encode(sentExchange, forKey: .sentExchange)
        try c.encode(operators, forKey: .operators)
        try c.encode(soapbox, forKey: .soapbox)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(tour, forKey: .tour)
        try c.encode(skeds, forKey: .skeds)
        try c.encode(bonusStations, forKey: .bonusStations)
        if !callHistoryFile.isEmpty {
            try c.encode(callHistoryFile, forKey: .callHistoryFile)
        }
        if !functionKeyFiles.isEmpty {
            try c.encode(functionKeyFiles, forKey: .functionKeyFiles)
        }
        if firstSerial != 1 {
            try c.encode(firstSerial, forKey: .firstSerial)
        }
        if !scpFile.isEmpty {
            try c.encode(scpFile, forKey: .scpFile)
        }
        if !goalFile.isEmpty {
            try c.encode(goalFile, forKey: .goalFile)
        }
    }
}
