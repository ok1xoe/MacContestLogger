import Foundation

/// Contest sessions for the `TOUR` command (N1MM): some contests allow working
/// the same station again in each session. The notation `1200/30` = sessions start at
/// 12:00 UTC and last 30 minutes.
///
/// Port of Java `contest/runtime/Tour.java`. Time is everywhere UTC in epoch seconds (Java
/// `Instant.getEpochSecond()`, floor of seconds); `Date` is just a wrapper. An instant outside the range of
/// Java `Instant` makes `sessionStart`/`sessionEnd` fail with an error like Java
/// (`DateTimeException`).
public struct Tour: Equatable, Sendable {

    /// Shortest allowed session (N1MM), Java `MIN_DURATION`.
    public static let minDuration = 5

    /// Session start in minutes since UTC midnight (0–1439).
    public let startMinute: Int
    /// Session length in minutes (at least `minDuration`).
    public let durationMinutes: Int

    /// A value in the contest settings that turns sessions off even against the definition (`NOTOUR`).
    public static let off = "OFF"

    /// `Tour` errors — the constructor's Java `IllegalArgumentException` (texts verbatim)
    /// and `DateTimeException` from `Instant`.
    public enum TourError: Error, Equatable, Sendable, CustomStringConvertible {
        case startOutOfRange
        case durationTooShort
        case instantOutOfRange

        public var description: String {
            switch self {
            case .startOutOfRange: return "Začátek sezení mimo 00:00–23:59"
            case .durationTooShort: return "Sezení musí trvat aspoň \(Tour.minDuration) minut"
            case .instantOutOfRange: return "Instant exceeds minimum or maximum instant"
            }
        }
    }

    /// Java compact constructor: a start outside 0–1439 and a length below `minDuration`
    /// are errors (texts as in Java; the start is checked first). A length of at least
    /// `minDuration` also protects `session` from division by zero.
    public init(startMinute: Int, durationMinutes: Int) throws(TourError) {
        if startMinute < 0 || startMinute >= 24 * 60 {
            throw .startOutOfRange
        }
        if durationMinutes < Tour.minDuration {
            throw .durationTooShort
        }
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
    }

    /// Internal constructor for `parse`, which has already checked the ranges.
    private init(checkedStart: Int, duration: Int) {
        self.startMinute = checkedStart
        self.durationMinutes = duration
    }

    /// Java `(\d{1,2})(\d{2})/(\d{1,4})` — `\d` is ASCII only in Java.
    private static let pattern: JavaRegex = {
        do {
            return try JavaRegex(#"(\d{1,2})(\d{2})/(\d{1,4})"#)
        } catch {
            preconditionFailure("pevný vzor sezení musí jít zkompilovat: \(error)")
        }
    }()

    /// `hhmm/mm` or `hhmm/hhmm` (N1MM, example `1200/30`) after Java `trim()`.
    /// A three-digit or shorter length = minutes, four digits = hhmm. An invalid notation,
    /// an hour above 23, a minute above 59 or a length below `minDuration` → `nil`.
    public static func parse(_ text: String?) -> Tour? {
        guard let text else { return nil }
        guard let match = pattern.wholeMatch(JavaText.trim(text)),
              let hhText = match.group(1), let mmText = match.group(2), let d = match.group(3),
              let hh = number(hhText), let mm = number(mmText)
        else { return nil }
        let duration: Int
        if d.utf16.count == 4 {
            let units = Array(d.utf16)
            guard let hours = number(String(decoding: units[0..<2], as: UTF16.self)),
                  let minutes = number(String(decoding: units[2...], as: UTF16.self))
            else { return nil }
            duration = hours * 60 + minutes
        } else {
            guard let minutes = number(d) else { return nil }
            duration = minutes
        }
        if hh > 23 || mm > 59 || duration < minDuration {
            return nil
        }
        return Tour(checkedStart: hh * 60 + mm, duration: duration)
    }

    /// Java `Integer.parseInt` over a group from the pattern — ASCII digits only,
    /// so it never fails; `nil` would mean a defect in the pattern.
    private static func number(_ digits: String) -> Int? {
        JavaInteger.parseInt(digits).map { Int($0) }
    }

    /// Number of the session that an instant given as epoch seconds belongs to (Java
    /// `Instant.getEpochSecond()` is a floor of seconds, so negative times before 1970
    /// also fall into the previous second):
    /// `floorDiv(floorDiv(epochSecond, 60) - startMinute, durationMinutes)`.
    /// Sessions follow one another continuously from the anchor `startMinute` on the day 1970-01-01, before it
    /// the numbers are negative; a length of 1440 is parsed as `hhmm` (14:40 = 880 minutes), not as a day.
    public func session(epochSecond: Int64) -> Int64 {
        let minutes = JavaMath.floorDiv(epochSecond, 60)
        return JavaMath.floorDiv(minutes - Int64(startMinute), Int64(durationMinutes))
    }

    /// The same for `Date`: the fraction of a second is dropped by floor (`Instant.ofEpochSecond(-1, 5e8)`
    /// = −0.5 s has `getEpochSecond()` −1), not by truncation toward zero.
    public func session(at date: Date) -> Int64 {
        session(epochSecond: Tour.epochSecond(of: date))
    }
}

// MARK: - definition, settings, session boundaries, writing

extension Tour {

    /// Session by the contest definition (`period.sessions`), otherwise `nil`. Java
    /// `parse(start ?: "" + "/" + minutes ?: "")`: `minutes` is a number, so
    /// `1440` is parsed as `hhmm` (14:40 = 880 minutes), not as a day.
    public static func fromDefinition(_ definition: ContestDefinition?) -> Tour? {
        guard let sessions = definition?.period?.sessions else { return nil }
        let start = sessions.start ?? ""
        let minutes = sessions.minutes.map { String($0) } ?? ""
        return parse(start + "/" + minutes)
    }

    /// Session for a contest: the stored setting (the TOUR command) takes precedence, `off`
    /// (`equalsIgnoreCase`, **without** trimming spaces) turns it off, an empty or invalid
    /// setting silently falls back to the definition.
    public static func effective(_ setupTour: String?, _ definition: ContestDefinition?) -> Tour? {
        if let setup = setupTour, equalsOff(setup) {
            return nil
        }
        if let setup = setupTour, !JavaText.isBlank(setup), let tour = parse(setup) {
            return tour
        }
        return fromDefinition(definition)
    }

    /// Java `"OFF".equalsIgnoreCase(text)` — `OFF` contains only the letters `O` and `F`,
    /// no other character converts to them in upper/lower case, so ASCII is enough.
    private static func equalsOff(_ text: String) -> Bool {
        let units = Array(text.utf16)
        guard units.count == 3 else { return false }
        let expected: [UInt16] = [0x4F, 0x46, 0x46]
        for index in 0..<3 {
            var unit = units[index]
            if unit >= 0x61 && unit <= 0x7A { unit -= 0x20 }
            if unit != expected[index] { return false }
        }
        return true
    }

    /// Smallest and largest `Instant.getEpochSecond()` (`-1000000000-01-01T00:00:00Z`
    /// and `+1000000000-12-31T23:59:59Z`).
    static let minInstantSecond: Int64 = -31_557_014_167_219_200
    static let maxInstantSecond: Int64 = 31_556_889_864_403_199

    private static func checkedInstant(_ epochSecond: Int64) throws(TourError) -> Int64 {
        if epochSecond < minInstantSecond || epochSecond > maxInstantSecond {
            throw .instantOutOfRange
        }
        return epochSecond
    }

    /// Start of the session that an instant (epoch seconds) belongs to:
    /// `(session * duration + start) * 60` with Java `long` wrapping.
    /// Outside the `Instant` range an error like `Instant.ofEpochSecond`.
    public func sessionStart(epochSecond: Int64) throws(TourError) -> Int64 {
        let number = session(epochSecond: epochSecond)
        let minutes = JavaMath.addLong(JavaMath.multiplyLong(number, Int64(durationMinutes)), Int64(startMinute))
        return try Tour.checkedInstant(JavaMath.multiplyLong(minutes, 60))
    }

    /// End of the session (= start of the next): `sessionStart + 60L * duration` seconds,
    /// outside the `Instant` range an error like `Instant.plusSeconds`. Multiplied with Java `long`
    /// (wrapping): the Swift length is an `Int` and may exceed Java `int`, where `60 *`
    /// would overflow and crash the process; up to `Int32.max` the result is exactly Java's.
    public func sessionEnd(epochSecond: Int64) throws(TourError) -> Int64 {
        let start = try sessionStart(epochSecond: epochSecond)
        let length = JavaMath.multiplyLong(60, Int64(durationMinutes))
        return try Tour.checkedInstant(JavaMath.addLong(start, length))
    }

    /// `sessionStart` for `Date` (the fraction of a second is dropped by floor).
    public func sessionStart(at date: Date) throws(TourError) -> Date {
        let second = try sessionStart(epochSecond: Tour.epochSecond(of: date))
        return Date(timeIntervalSince1970: Double(second))
    }

    /// `sessionEnd` for `Date`.
    public func sessionEnd(at date: Date) throws(TourError) -> Date {
        let second = try sessionEnd(epochSecond: Tour.epochSecond(of: date))
        return Date(timeIntervalSince1970: Double(second))
    }

    static func epochSecond(of date: Date) -> Int64 {
        JavaMath.d2l(date.timeIntervalSince1970.rounded(.down))
    }

    /// Back to the `hhmm/mm` notation (Java `%02d%02d/%d`). **ASCII digits**; Java
    /// takes the default locale and e.g. in `ar_EG` writes Arabic-Indic digits
    /// (a deliberate divergence from Java v1.1.1).
    public func format() -> String {
        Tour.twoDigits(startMinute / 60) + Tour.twoDigits(startMinute % 60) + "/" + String(durationMinutes)
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0" + String(value) : String(value)
    }
}
