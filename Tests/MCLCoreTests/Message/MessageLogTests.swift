import Testing
@testable import MCLCore

/// Port of the Java `message/MessageLogTest` (6 tests).
@Suite struct MessageLogTests {

    private static let at: JavaInstant = JavaInstant.parseIsoInstant("2026-08-19T12:34:56Z")!

    @Test func keepsMessagesInArrivalOrder() {
        let log = MessageLog(maxEntries: 10)
        log.add(Self.at, "první")
        log.add(Self.at.plus(seconds: 60)!, "druhá")

        #expect(log.entries.map(\.text) == ["první", "druhá"])
    }

    @Test func oldestMessagesFallOutWhenTheLimitIsReached() {
        // The message window runs the whole contest; without a cap it would grow endlessly.
        let log = MessageLog(maxEntries: 2)
        log.add(Self.at, "a")
        log.add(Self.at, "b")
        log.add(Self.at, "c")

        #expect(log.entries.map(\.text) == ["b", "c"])
    }

    @Test func textForClipboardCarriesUtcTimeOfEachMessage() throws {
        let log = MessageLog(maxEntries: 10)
        log.add(Self.at, "byl jsi spotnut")

        #expect(try log.asText() == "1234Z  byl jsi spotnut")
    }

    @Test func emptyLogGivesEmptyTextAndNoEntries() throws {
        let log = MessageLog(maxEntries: 10)

        #expect(log.entries.isEmpty)
        #expect(try log.asText() == "")
    }

    @Test func clearEmptiesTheLog() {
        let log = MessageLog(maxEntries: 10)
        log.add(Self.at, "a")
        log.clear()

        #expect(log.entries.isEmpty)
    }

    @Test func blankMessageIsNotStored() {
        let log = MessageLog(maxEntries: 10)
        log.add(Self.at, "  ")
        log.add(Self.at, nil)

        #expect(log.entries.isEmpty)
    }
}

/// `MessageLog` against Java v1.1.1 (maintainer-only probe, table
/// `MessageLogMeasured`): the cap `max(1, n)`, `isBlank` (U+3000 yes, NBSP no) vs `trim` (control characters yes,
/// NBSP no), U+2028/U+0085, the time `HHmm` in UTC also for years before 1970, above 9999 and negative, `Instant.MIN`
/// (`DateTimeException`), the `\n` separator.
@Suite struct MessageLogMeasuredTests {

    /// The probe inputs verbatim (`texts`, `times`, `caps`).
    private static let texts: [String?] = [
        "  a  ", "\u{1}b\u{1}", "\u{A0}", "\u{A0}c\u{A0}", "\u{3000}", "\u{3000}d\u{3000}", "\t\n", "", nil,
        "\u{2028}", "e\u{2028}", "\u{1C}f", "\u{85}", " g\r\n",
    ]
    private static let times: [String] = [
        "2026-08-19T12:34:56Z", "1969-12-31T23:59:59.999Z", "+12026-01-01T00:07:00Z", "-0001-06-01T23:00:00Z",
        "2026-08-19T00:00:00.999999999Z",
    ]
    private static let caps: [Int] = [-3, 0, 1, 2, 5, 20]

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rawRows(MessageLogMeasured.rows, id)
    }

    private static func esc(_ text: String) -> String {
        CallHistoryMeasuredTests.esc(text)
    }

    private static func instant(_ text: String) -> JavaInstant {
        JavaInstant.parseIsoInstant(text)!
    }

    @Test func capsTrimmingAndTextMatchJava() throws {
        let rows = Self.rows("MSG")
        #expect(rows.count == Self.caps.count)
        for (cap, row) in zip(Self.caps, rows) {
            let log = MessageLog(maxEntries: cap)
            for (index, text) in Self.texts.enumerated() {
                log.add(Self.instant(Self.times[index % Self.times.count]), text)
            }
            let entries: String = log.entries.map { "[\($0.at) \(Self.esc($0.text))]" }.joined()
            #expect(row[0] == String(cap))
            #expect(entries == row[1], "cap \(cap)")
            #expect(Self.esc(try log.asText()) == row[2], "cap \(cap)")
        }
    }

    @Test func timesClearAndInstantMinMatchJava() throws {
        let log = MessageLog(maxEntries: 10)
        for time in Self.times {
            log.add(Self.instant(time), "x")
        }
        #expect(Self.esc(try log.asText()) == Self.rows("MSG.times").first?[0])

        let edge = MessageLog(maxEntries: 10)
        edge.add(JavaInstant(uncheckedSecond: JavaInstant.minSecond, nano: 0), "min")
        let text: String
        do {
            text = Self.esc(try edge.asText())
        } catch {
            text = "throws DateTimeException"
        }
        #expect(["\(edge.entries.count)", text] == Self.rows("MSG.instantMin").first)

        log.clear()
        #expect(["\(log.entries.count)", Self.esc(try log.asText())] == Self.rows("MSG.clear").first)
    }

    @Test func localDateRangeBoundsMatchJava() {
        // `LocalDate.MIN`/`MAX` as the epoch day (boundary of `JavaDateTimeException.utcEpochDay`).
        #expect(JavaLocalDate.epochDay(year: -999_999_999, month: 1, day: 1) == JavaDateTimeException.minEpochDay)
        #expect(JavaLocalDate.epochDay(year: 999_999_999, month: 12, day: 31) == JavaDateTimeException.maxEpochDay)
    }
}
