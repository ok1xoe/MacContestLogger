import Testing
@testable import MCLCore

/// The Java validation types (`validation/*.java`) have no tests of their own — they are
/// value records without behaviour. The only logic is the assignment to a bucket by
/// score (`ScoreBucket.of`), hence that one is tested; for `ValidationClassification`
/// the exact `rawValue` strings are additionally verified, because they end up in the CSV reports
/// of the `scoreCheck` tool and must match the Java constants literally.
@Suite struct ValidationTypesTests {
    @Test func scoreBucketBoundaries() {
        #expect(ScoreBucket.of(0) == .zero)
        #expect(ScoreBucket.of(-5) == .zero)
        #expect(ScoreBucket.of(10_000) == .b1To10k)
        #expect(ScoreBucket.of(10_001) == .b10kTo100k)
        #expect(ScoreBucket.of(1_000_000) == .b100kTo1M)
        #expect(ScoreBucket.of(2_000_000) == .b1MTo2M)
        #expect(ScoreBucket.of(5_000_000) == .b2MTo5M)
        #expect(ScoreBucket.of(10_000_000) == .b5MTo10M)
        #expect(ScoreBucket.of(10_000_001) == .b10MPlus)
    }

    @Test func scoreBucketLabelsMatchJavaReports() {
        // These labels group the CSV reports that are compared with the Java ones.
        // The hyphen in "1–10k" etc. is an en dash (U+2013), not a hyphen-minus (U+002D).
        #expect(ScoreBucket.zero.rawValue == "0")
        #expect(ScoreBucket.b1To10k.rawValue == "1\u{2013}10k")
        #expect(ScoreBucket.b10kTo100k.rawValue == "10\u{2013}100k")
        #expect(ScoreBucket.b100kTo1M.rawValue == "100k\u{2013}1M")
        #expect(ScoreBucket.b1MTo2M.rawValue == "1\u{2013}2M")
        #expect(ScoreBucket.b2MTo5M.rawValue == "2\u{2013}5M")
        #expect(ScoreBucket.b5MTo10M.rawValue == "5\u{2013}10M")
        #expect(ScoreBucket.b10MPlus.rawValue == "10M+")
        #expect(ScoreBucket.missing.rawValue == "(missing)")
        #expect(ScoreBucket.b1To10k.label == ScoreBucket.b1To10k.rawValue)
    }

    @Test func validationClassificationRawValuesMatchJavaConstantNames() {
        // `dominantDifference`/the reports assemble strings from these names —
        // they must match the names of the Java enum constants literally.
        #expect(ValidationClassification.ok.rawValue == "OK")
        #expect(ValidationClassification.close.rawValue == "CLOSE")
        #expect(ValidationClassification.failed.rawValue == "FAILED")
        #expect(ValidationClassification.claimedZero.rawValue == "CLAIMED_ZERO")
        #expect(ValidationClassification.claimedMissing.rawValue == "CLAIMED_MISSING")
        #expect(ValidationClassification.parseError.rawValue == "PARSE_ERROR")
    }

    @Test func validationResultHelpers() {
        let breakdown = ContestScoreBreakdown(
            qsoPoints: 100,
            dxccMultipliers: 5,
            zoneMultipliers: 3,
            totalMultipliers: 8,
            totalScore: 800
        )
        let parseErrorResult = ValidationResult(
            callsign: "OK1XOE",
            software: "MacContestLogger",
            category: "SOAB",
            scoreBucket: .missing,
            continent: "EU",
            dxcc: "OK",
            claimedScore: nil,
            calculatedScore: 0,
            deltaPoints: nil,
            deltaPercent: nil,
            ratio: nil,
            classification: .parseError,
            extremeRatio: false,
            converterExport: false,
            relevantFailed: false,
            calculatedBreakdown: breakdown,
            inputFile: "log.cbr",
            errorMessage: "boom"
        )
        #expect(parseErrorResult.isParseError)
        #expect(parseErrorResult.absDeltaPercent().isNaN)

        let okResult = ValidationResult(
            callsign: "OK1XOE",
            software: "MacContestLogger",
            category: "SOAB",
            scoreBucket: .b1To10k,
            continent: "EU",
            dxcc: "OK",
            claimedScore: 1_000,
            calculatedScore: 950,
            deltaPoints: -50,
            deltaPercent: -5.0,
            ratio: 0.95,
            classification: .close,
            extremeRatio: false,
            converterExport: false,
            relevantFailed: false,
            calculatedBreakdown: breakdown,
            inputFile: "log.cbr",
            errorMessage: nil
        )
        #expect(!okResult.isParseError)
        #expect(okResult.absDeltaPercent() == 5.0)
    }
}
