import Foundation

/// Log category by the size of the claimed (`claimed`) score.
///
/// Port of `validation/ScoreBucket.java`. `rawValue` is also the label used
/// in the CSV reports of the `scoreCheck` tool (consumed) — so it must
/// be literally identical to the Java `label()` strings, including the en dash (U+2013)
/// instead of hyphen-minus in "1–10k" etc.
public enum ScoreBucket: String, CaseIterable, Sendable {
    case zero = "0"
    case b1To10k = "1–10k"
    case b10kTo100k = "10–100k"
    case b100kTo1M = "100k–1M"
    case b1MTo2M = "1–2M"
    case b2MTo5M = "2–5M"
    case b5MTo10M = "5–10M"
    case b10MPlus = "10M+"
    case missing = "(missing)"

    public var label: String { rawValue }

    /// Assigns the claimed score to a category; `claimed <= 0` is `.zero`.
    public static func of(_ claimed: Int64) -> ScoreBucket {
        switch claimed {
        case ..<1: .zero
        case ...10_000: .b1To10k
        case ...100_000: .b10kTo100k
        case ...1_000_000: .b100kTo1M
        case ...2_000_000: .b1MTo2M
        case ...5_000_000: .b2MTo5M
        case ...10_000_000: .b5MTo10M
        default: .b10MPlus
        }
    }
}

/// Breakdown of a contest score (from the unchanged contest engine). Cabrillo `CLAIMED-SCORE`
/// usually carries only the total score, so this breakdown is available only for the
/// **calculated** score.
///
/// Port of `validation/ContestScoreBreakdown.java`.
public struct ContestScoreBreakdown: Sendable, Equatable {
    public let qsoPoints: Int64
    public let dxccMultipliers: Int
    public let zoneMultipliers: Int
    public let totalMultipliers: Int
    public let totalScore: Int64

    public init(
        qsoPoints: Int64,
        dxccMultipliers: Int,
        zoneMultipliers: Int,
        totalMultipliers: Int,
        totalScore: Int64
    ) {
        self.qsoPoints = qsoPoints
        self.dxccMultipliers = dxccMultipliers
        self.zoneMultipliers = zoneMultipliers
        self.totalMultipliers = totalMultipliers
        self.totalScore = totalScore
    }
}

/// Diagnostic breakdown of the difference between the calculated and the claimed score.
/// `claimedBreakdown` is usually `nil` (Cabrillo carries only the total claimed score);
/// the difference flags and `dominantDifference` are therefore derived heuristically for now.
///
/// Port of `validation/ContestScoreDiff.java`.
public struct ContestScoreDiff: Sendable, Equatable {
    public let callsign: String
    public let category: String
    public let scoreBucket: String
    public let continent: String
    public let dxcc: String
    public let software: String
    public let claimedScore: Int64?
    public let calculatedScore: Int64
    public let deltaPoints: Int64?
    public let deltaPercent: Double?
    public let ratio: Double?
    public let calculatedBreakdown: ContestScoreBreakdown?
    public let claimedBreakdown: ContestScoreBreakdown?
    public let qsoPointsDiffer: Bool?
    public let dxccMultipliersDiffer: Bool?
    public let zoneMultipliersDiffer: Bool?
    public let totalMultipliersDiffer: Bool?
    public let dominantDifference: String?
    public let inputFile: String

    public init(
        callsign: String,
        category: String,
        scoreBucket: String,
        continent: String,
        dxcc: String,
        software: String,
        claimedScore: Int64?,
        calculatedScore: Int64,
        deltaPoints: Int64?,
        deltaPercent: Double?,
        ratio: Double?,
        calculatedBreakdown: ContestScoreBreakdown?,
        claimedBreakdown: ContestScoreBreakdown?,
        qsoPointsDiffer: Bool?,
        dxccMultipliersDiffer: Bool?,
        zoneMultipliersDiffer: Bool?,
        totalMultipliersDiffer: Bool?,
        dominantDifference: String?,
        inputFile: String
    ) {
        self.callsign = callsign
        self.category = category
        self.scoreBucket = scoreBucket
        self.continent = continent
        self.dxcc = dxcc
        self.software = software
        self.claimedScore = claimedScore
        self.calculatedScore = calculatedScore
        self.deltaPoints = deltaPoints
        self.deltaPercent = deltaPercent
        self.ratio = ratio
        self.calculatedBreakdown = calculatedBreakdown
        self.claimedBreakdown = claimedBreakdown
        self.qsoPointsDiffer = qsoPointsDiffer
        self.dxccMultipliersDiffer = dxccMultipliersDiffer
        self.zoneMultipliersDiffer = zoneMultipliersDiffer
        self.totalMultipliersDiffer = totalMultipliersDiffer
        self.dominantDifference = dominantDifference
        self.inputFile = inputFile
    }
}

/// Primary classification of a log during validation. `.ok`/`.close`/`.failed` apply only
/// to logs with `claimed > 0`; other states are set apart.
///
/// Port of `validation/ValidationClassification.java`. `rawValue` must be literally
/// the name of the Java constant — it is written into the `scoreCheck` reports.
public enum ValidationClassification: String, Sendable {
    case ok = "OK"
    case close = "CLOSE"
    case failed = "FAILED"
    case claimedZero = "CLAIMED_ZERO"
    case claimedMissing = "CLAIMED_MISSING"
    case parseError = "PARSE_ERROR"
}

/// Result of validating one log. The score is computed by the unchanged contest engine;
/// this structure holds only the comparison and metadata for reporting.
///
/// Port of `validation/ValidationResult.java`.
/// - `deltaPoints`: `calculatedScore - claimedScore` (`nil` when `claimed` is missing)
/// - `deltaPercent`: relative deviation in % (`nil` when `claimed` is `nil` or 0)
/// - `ratio`: `calculatedScore / claimedScore` (`nil` when `claimed` is `nil` or 0)
public struct ValidationResult: Sendable, Equatable {
    public let callsign: String
    public let software: String
    public let category: String
    public let scoreBucket: ScoreBucket
    public let continent: String
    public let dxcc: String
    public let claimedScore: Int64?
    public let calculatedScore: Int64
    public let deltaPoints: Int64?
    public let deltaPercent: Double?
    public let ratio: Double?
    public let classification: ValidationClassification
    public let extremeRatio: Bool
    public let converterExport: Bool
    public let relevantFailed: Bool
    public let calculatedBreakdown: ContestScoreBreakdown
    public let inputFile: String
    public let errorMessage: String?

    public init(
        callsign: String,
        software: String,
        category: String,
        scoreBucket: ScoreBucket,
        continent: String,
        dxcc: String,
        claimedScore: Int64?,
        calculatedScore: Int64,
        deltaPoints: Int64?,
        deltaPercent: Double?,
        ratio: Double?,
        classification: ValidationClassification,
        extremeRatio: Bool,
        converterExport: Bool,
        relevantFailed: Bool,
        calculatedBreakdown: ContestScoreBreakdown,
        inputFile: String,
        errorMessage: String?
    ) {
        self.callsign = callsign
        self.software = software
        self.category = category
        self.scoreBucket = scoreBucket
        self.continent = continent
        self.dxcc = dxcc
        self.claimedScore = claimedScore
        self.calculatedScore = calculatedScore
        self.deltaPoints = deltaPoints
        self.deltaPercent = deltaPercent
        self.ratio = ratio
        self.classification = classification
        self.extremeRatio = extremeRatio
        self.converterExport = converterExport
        self.relevantFailed = relevantFailed
        self.calculatedBreakdown = calculatedBreakdown
        self.inputFile = inputFile
        self.errorMessage = errorMessage
    }

    public var isParseError: Bool { classification == .parseError }

    /// Absolute value of the relative deviation (`Double.nan` when not available).
    public func absDeltaPercent() -> Double {
        guard let deltaPercent else { return .nan }
        return abs(deltaPercent)
    }
}
