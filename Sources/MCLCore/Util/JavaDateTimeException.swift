/// Java `java.time.DateTimeException` from arithmetic over `Instant`/`LocalDate` that callers
/// in Java do not catch (result outside the `Instant` range or conversion of an instant outside the `LocalDateTime` range,
/// years ±999,999,999). Thrown by `SkedPlanner` and `MessageLog.asText` — only for instants at the edges of
/// the range, which normal operation (`JavaInstant.now()`, sked time from `parseTime`) does not produce.
public struct JavaDateTimeException: Error, Equatable, Sendable {
    public init() {}

    /// Epoch day of the instant, if its date in UTC lies within the `LocalDate` range
    /// (`LocalDate.ofEpochDay`, Java's `LocalDate.MIN`…`LocalDate.MAX`).
    static func utcEpochDay(_ instant: JavaInstant) throws(JavaDateTimeException) -> Int64 {
        let day: Int64 = JavaInstant.floorDiv(instant.epochSecond, 86_400)
        guard day >= minEpochDay, day <= maxEpochDay else {
            throw JavaDateTimeException()
        }
        return day
    }

    /// `LocalDate.MIN.toEpochDay()` (−999 999 999-01-01).
    static let minEpochDay: Int64 = -365_243_219_162
    /// `LocalDate.MAX.toEpochDay()` (+999 999 999-12-31).
    static let maxEpochDay: Int64 = 365_241_780_471
}
