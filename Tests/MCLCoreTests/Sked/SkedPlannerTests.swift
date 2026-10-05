import Testing
@testable import MCLCore

/// Port of the Java `sked/SkedPlannerTest` (3 tests).
@Suite struct SkedPlannerTests {

    static func instant(_ text: String) -> JavaInstant {
        JavaInstant.parseIsoInstant(text)!
    }

    private static let now = instant("2026-11-28T14:00:00Z")

    private static func sked(_ call: String, _ at: String) -> SkedEntry {
        SkedEntry(call: call, freqHz: 14_025_000, mode: "CW", atUtc: at, note: "")
    }

    @Test func timeOnlyIsNextOccurrence() throws {
        #expect(try SkedPlanner.parseTime("1430", now: Self.now) == Self.instant("2026-11-28T14:30:00Z"))
        #expect(try SkedPlanner.parseTime("0900", now: Self.now) == Self.instant("2026-11-29T09:00:00Z"),
                "already passed → tomorrow")
        #expect(try SkedPlanner.parseTime("13:58", now: Self.now) == Self.instant("2026-11-28T13:58:00Z"),
                "a moment ago → today")
        #expect(try SkedPlanner.parseTime("2026-11-30 0100", now: Self.now) == Self.instant("2026-11-30T01:00:00Z"))
        #expect(try SkedPlanner.parseTime("2500", now: Self.now) == nil)
    }

    @Test func dueWindowAndPast() throws {
        let s = Self.sked("DL1ABC", "2026-11-28T14:00:30Z")

        #expect(try SkedPlanner.isDue(s, now: Self.now), "30 s ahead")
        #expect(try SkedPlanner.isDue(s, now: Self.now.plus(seconds: 4 * 60)!), "4 min po")
        #expect(try !SkedPlanner.isDue(s, now: Self.now.plus(seconds: -5 * 60)!), "5 min ahead, not yet")
        #expect(try SkedPlanner.isPast(s, now: Self.now.plus(seconds: 10 * 60)!))
    }

    @Test func nextIgnoresPastAndSorts() throws {
        let skeds = [
            Self.sked("LATER", "2026-11-28T16:00:00Z"),
            Self.sked("OLD", "2026-11-28T12:00:00Z"),
            Self.sked("SOON", "2026-11-28T14:10:00Z"),
        ]

        #expect(try SkedPlanner.next(skeds, now: Self.now)?.call == "SOON")
        #expect(SkedPlanner.sorted(skeds).map(\.call) == ["OLD", "SOON", "LATER"])
    }
}

/// `SkedPlanner` against Java v1.1.1 (maintainer-only probe, table
/// `SkedMeasured`): `parseTime` for 9 "now" values (incl. the `Instant` range edges where Java throws
/// `DateTimeException`) × 47 texts, `at` (`Instant.parse`: offsets, nanoseconds, `24:00`, leap
/// second, lowercase `t`/`z`), `isDue`/`isPast` bounds at nanoseconds and with overflow, `sorted`/`next`.
@Suite struct SkedMeasuredTests {

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rawRows(SkedMeasured.rows, id)
    }

    private static func optional(_ instant: JavaInstant?) -> String {
        instant.map { "Optional[\($0)]" } ?? "Optional.empty"
    }

    private static func run(_ body: () throws(JavaDateTimeException) -> String) -> String {
        do {
            return try body()
        } catch {
            return "throws DateTimeException"
        }
    }

    private static func sked(_ call: String, _ at: String) -> SkedEntry {
        SkedEntry(call: call, freqHz: 14_025_000, mode: "CW", atUtc: at, note: "")
    }

    private static func check(_ id: String, expectedCount: Int, _ actual: ([String]) -> [String]) {
        let rows: [[String]] = Self.rows(id)
        #expect(rows.count == expectedCount, "\(id)")
        var mismatches = 0
        for row in rows {
            let got: [String] = actual(row)
            let want: [String] = Array(row.suffix(got.count))
            if got != want {
                mismatches += 1
                if mismatches <= 15 {
                    Issue.record("\(id) \(row): Swift \(got)")
                }
            }
        }
        #expect(mismatches == 0, "\(id): \(mismatches) mismatches")
    }

    @Test func parseTimeMatchesJava() {
        Self.check("SKED.parse", expectedCount: 423) { row in
            let now: JavaInstant = SkedPlannerTests.instant(row[0])
            let text: String? = row[1] == "null" ? nil : ProbeRows.unescape(row[1])
            return [Self.run { () throws(JavaDateTimeException) -> String in
                Self.optional(try SkedPlanner.parseTime(text, now: now))
            }]
        }
    }

    @Test func atMatchesJavaInstantParse() {
        Self.check("SKED.at", expectedCount: 19) { row in
            [Self.optional(SkedPlanner.at(Self.sked("X", ProbeRows.unescape(row[0]))))]
        }
    }

    @Test func dueAndPastMatchJava() {
        Self.check("SKED.due", expectedCount: 12) { row in
            let sked = Self.sked("X", row[0])
            let now: JavaInstant = SkedPlannerTests.instant(row[1])
            let due: String = Self.run { () throws(JavaDateTimeException) -> String in
                String(try SkedPlanner.isDue(sked, now: now))
            }
            let past: String = Self.run { () throws(JavaDateTimeException) -> String in
                String(try SkedPlanner.isPast(sked, now: now))
            }
            return [due, past]
        }
    }

    @Test func sortedAndNextMatchJava() {
        let now: JavaInstant = SkedPlannerTests.instant("2026-11-28T14:00:00Z")
        Self.check("SKED.list", expectedCount: 7) { row in
            let spec: String = row[0]
            let skeds: [SkedEntry] = spec.isEmpty ? [] : spec.split(separator: ";").map { item in
                let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                return Self.sked(String(parts[0]), String(parts[1]))
            }
            let sorted = "[" + SkedPlanner.sorted(skeds).map(\.call).joined(separator: ", ") + "]"
            let next: String = Self.run { () throws(JavaDateTimeException) -> String in
                try SkedPlanner.next(skeds, now: now).map { "Optional[\($0.call)]" } ?? "Optional.empty"
            }
            return [sorted, next]
        }
    }
}
