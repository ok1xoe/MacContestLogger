import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `TourTest` (4 tests) and `ContestPeriodsTest` (4 tests), `contest/runtime`.
/// The times of the Java tests (`Instant.parse`) are epoch seconds here; 2026-11-28T00:00:00Z = 1 795 824 000.
@Suite struct TourTests {

    /// 2026-11-28T00:00:00Z as epoch seconds (measured with `Instant.parse` on JDK 21).
    static let day28: Int64 = 1_795_824_000

    /// `Instant.parse("2026-11-<day>T<h>:<m>:<s>Z")` as epoch seconds.
    static func at(day: Int64, _ hour: Int64, _ minute: Int64, _ second: Int64 = 0) -> Int64 {
        day28 + (day - 28) * 86_400 + hour * 3600 + minute * 60 + second
    }

    static func tour(_ start: Int, _ duration: Int) throws -> Tour {
        try Tour(startMinute: start, durationMinutes: duration)
    }

    // MARK: - TourTest

    /// Note: `parse` is already covered by `TourParseTests`; here 1:1 like the Java test.
    @Test func parsesN1mmFormat() throws {
        #expect(Tour.parse("1200/30") == (try Self.tour(12 * 60, 30)))
        #expect(Tour.parse("2100/0100") == (try Self.tour(21 * 60, 60)))
        #expect(Tour.parse("000/120") == (try Self.tour(0, 120)))
        #expect(try Self.tour(12 * 60, 30).format() == "1200/30")
    }

    @Test func rejectsInvalid() {
        #expect(Tour.parse("1200/3") == nil)   // min. 5 minutes
        #expect(Tour.parse("2500/30") == nil)
        #expect(Tour.parse("1260/30") == nil)
        #expect(Tour.parse("599") == nil)      // a plain report is not a TOUR
        #expect(Tour.parse(nil) == nil)
    }

    @Test func sessionsFollowEachOther() throws {
        let t = try #require(Tour.parse("1200/30"))
        let s1 = t.session(epochSecond: Self.at(day: 28, 12, 0))

        #expect(t.session(epochSecond: Self.at(day: 28, 12, 29, 59)) == s1)
        #expect(t.session(epochSecond: Self.at(day: 28, 12, 30)) == s1 + 1)
        #expect(t.session(epochSecond: Self.at(day: 28, 11, 59)) == s1 - 1)
        #expect(try t.sessionStart(epochSecond: Self.at(day: 28, 12, 45)) == Self.at(day: 28, 12, 30))
    }

    @Test func sessionsCrossMidnight() throws {
        let t = try #require(Tour.parse("2300/60"))

        #expect(t.session(epochSecond: Self.at(day: 28, 23, 30)) != t.session(epochSecond: Self.at(day: 29, 0, 30)))
        #expect(try t.sessionStart(epochSecond: Self.at(day: 29, 0, 30)) == Self.at(day: 29, 0, 0))
    }

    // MARK: - ContestPeriodsTest

    static func def(_ period: String) throws -> ContestDefinition {
        let yaml = DefinitionEditing.template("p", "P")
            .replacingOccurrences(of: "period: { durationHours: 24 }", with: period)
        return try #require(DefinitionEditing.check(yaml, fileId: "p", knownSets: []).definition)
    }

    @Test func sessionsFromDefinition() throws {
        let d = try Self.def(#"period: { durationHours: 4, sessions: { start: "1200", minutes: 60 } }"#)

        #expect(Tour.fromDefinition(d) == (try Self.tour(12 * 60, 60)))
        #expect(Tour.fromDefinition(try Self.def("period: { durationHours: 4 }")) == nil)
    }

    @Test func setupOverridesDefinitionAndOffDisables() throws {
        let d = try Self.def(#"period: { durationHours: 4, sessions: { start: "1200", minutes: 60 } }"#)

        #expect(Tour.effective("", d) == (try Self.tour(12 * 60, 60)))   // empty = by definition
        #expect(Tour.effective("1800/30", d) == (try Self.tour(18 * 60, 30)))   // TOUR takes precedence
        #expect(Tour.effective(Tour.off, d) == nil)   // NOTOUR also turns off the session from the definition
        #expect(Tour.effective("", try Self.def("period: { durationHours: 4 }")) == nil)
    }

    @Test func invalidSessionsAreReported() {
        let yaml = DefinitionEditing.template("p", "P")
            .replacingOccurrences(of: "period: { durationHours: 24 }",
                                  with: #"period: { durationHours: 4, sessions: { start: "25xx", minutes: 2 } }"#)
        let check = DefinitionEditing.check(yaml, fileId: "p", knownSets: [])
        #expect(check.hasErrors)
        #expect(check.issues[0].message.contains("period.sessions"), "\(check.issues)")
        #expect(!DefinitionEditing.check(DefinitionEditing.template("p", "P"), fileId: "p", knownSets: []).hasErrors)
    }

    @Test func sessionEndIsNextStart() throws {
        let t = try Self.tour(12 * 60, 30)
        let at = Self.at(day: 28, 12, 40)
        #expect(try t.sessionStart(epochSecond: at) == Self.at(day: 28, 12, 30))
        #expect(try t.sessionEnd(epochSecond: at) == Self.at(day: 28, 13, 0))
    }
}

/// Edges of the public API that the Java test does not cover.
@Suite struct TourEdgeTests {

    @Test func errorMessagesAreJavaTexts() {
        #expect(Tour.TourError.startOutOfRange.description == "Začátek sezení mimo 00:00–23:59")
        #expect(Tour.TourError.durationTooShort.description == "Sezení musí trvat aspoň 5 minut")
        #expect(Tour.TourError.instantOutOfRange.description == "Instant exceeds minimum or maximum instant")
    }

    /// A duration of zero would crash `session` with a division by zero — init must reject it.
    @Test func zeroDurationIsRejectedNotTrapped() {
        #expect(throws: Tour.TourError.durationTooShort) { try Tour(startMinute: 0, durationMinutes: 0) }
        #expect(throws: Tour.TourError.durationTooShort) { try Tour(startMinute: 0, durationMinutes: Int.min) }
        #expect(throws: Tour.TourError.startOutOfRange) { try Tour(startMinute: Int.max, durationMinutes: 30) }
    }

    /// `sessionEnd` = start + `60L * duration` (Java `long`). The Swift duration is an `Int` and may
    /// exceed the Java `int`; the multiplication therefore wraps like a `long` instead of trapping on overflow.
    /// Up to `Int32.max` (Java can have no more) the result is exactly the Java one.
    @Test func sessionEndDoesNotTrapOnHugeDuration() throws {
        let javaMax = try Tour(startMinute: 0, durationMinutes: Int(Int32.max))
        #expect(try javaMax.sessionEnd(epochSecond: 0) == 60 * Int64(Int32.max))
        let huge = try Tour(startMinute: 0, durationMinutes: Int.max)
        #expect(try huge.sessionEnd(epochSecond: 0) == JavaMath.multiplyLong(60, Int64.max))
    }

    @Test func formatIsAsciiRegardlessOfLocale() throws {
        let text = try Tour(startMinute: 12 * 60, durationMinutes: 30).format()
        #expect(text.unicodeScalars.allSatisfy { $0.isASCII })
    }

    @Test func dateWrappersFloorFractions() throws {
        let t = try Tour(startMinute: 720, durationMinutes: 30)
        // 1969-12-31T11:59:59.5Z: epochSecond −43201 → session −49, start 11:30, end 12:00
        let date = Date(timeIntervalSince1970: -43_200.5)
        #expect(t.session(at: date) == -49)
        #expect(try t.sessionStart(at: date) == Date(timeIntervalSince1970: -45_000))
        #expect(try t.sessionEnd(at: date) == Date(timeIntervalSince1970: -43_200))
    }
}
