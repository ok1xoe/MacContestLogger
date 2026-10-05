import Foundation
import Testing
@testable import MCLCore

/// `ContestDupeChecker` and `Tour.session` against the table measured on Java (`DupeMeasured`,
/// maintainer-only probe, JDK 21.0.2). There is no Java test for
/// `ContestDupeChecker` or `Tour.session`.
@Suite struct DupeMeasuredTests {

    private static func definition(scope: String) throws -> ContestDefinition {
        let yaml: String
        switch scope {
        case "~": yaml = "{}"
        case "NODUPE": yaml = "{dupe: {}}"
        default: yaml = "{dupe: {scope: \(scope)}}"
        }
        return try ContestDefinitionLoader.load(Data(yaml.utf8))
    }

    private static func context(_ call: String?, _ band: String?, _ mode: String?, _ qth: String?) -> QsoContext {
        QsoContext(call: call, band: band, mode: mode, received: nil, workedEntity: nil, ownEntity: nil,
                   workedClass: nil, ownQth: qth)
    }

    @Test(arguments: DupeMeasured.rows)
    func dupeTableMatchesJava(row: DupeMeasured.Row) throws {
        var checker = ContestDupeChecker(definition: try Self.definition(scope: row.scope))
        if let tour = row.tour {
            let parsed = Tour.parse(tour)
            #expect(parsed != nil, "tour \(tour)")
            checker.tour = parsed
        }
        var actual: [Bool] = []
        for step in row.steps {
            switch step {
            case let .add(call, band, mode, qth, at):
                checker.add(Self.context(call, band, mode, qth), atEpochSecond: at)
            case let .dupe(call, band, mode, qth, at):
                actual.append(checker.isDupe(Self.context(call, band, mode, qth), atEpochSecond: at))
            case .reset:
                checker.reset()
            }
        }
        #expect(actual == row.java)
    }

    @Test(arguments: DupeMeasured.sessions)
    func sessionTableMatchesJava(row: DupeMeasured.SessionRow) {
        let parsed = row.tour.flatMap { Tour.parse($0) }
        guard let tour = parsed else {
            #expect(row.java == .empty)
            return
        }
        let actual = DupeMeasured.SessionOutcome.session(tour.startMinute, tour.durationMinutes,
                                                         tour.session(epochSecond: row.epochSecond))
        #expect(actual == row.java)
    }

    /// Java `Instant.getEpochSecond()` is a floor of seconds (`Instant.ofEpochSecond(-1, 5e8)` =
    /// −0.5 s → −1); `Date` is meant to compute the floor the same way.
    @Test func dateOverloadFloorsToSeconds() throws {
        let tour = try #require(Tour.parse("1200/60"))
        #expect(tour.session(at: Date(timeIntervalSince1970: 46_799.999)) == 0)
        #expect(tour.session(at: Date(timeIntervalSince1970: 46_800)) == 1)
        #expect(tour.session(at: Date(timeIntervalSince1970: -0.5)) == tour.session(epochSecond: -1))
        #expect(tour.session(at: Date(timeIntervalSince1970: 43_199.9)) == -1)
    }

    /// `Tour` has no public initializer — the only way is `parse`, which keeps `durationMinutes`
    /// at least at `minDuration`, so `session` never divides by zero.
    @Test func parsedToursAlwaysHaveDurationAtLeastMinimum() {
        for text in ["0000/5", "1200/0005", "2359/9999", "0000/1440"] {
            let tour = Tour.parse(text)
            #expect((tour?.durationMinutes ?? Tour.minDuration) >= Tour.minDuration, "\(text)")
        }
        #expect(Tour.parse("1200/4") == nil)
        #expect(Tour.parse("1200/0004") == nil)
        #expect(Tour.parse("1200/0000") == nil)
    }

    /// Values from the table outside it: the default scope value and independence of copies (value semantics).
    @Test func copiesDoNotShareState() {
        var original = ContestDupeChecker(scope: .PER_BAND)
        let context = Self.context("OK1AA", "20m", "CW", nil)
        var copy = original
        original.add(context, atEpochSecond: nil)
        #expect(original.isDupe(context, atEpochSecond: nil))
        #expect(!copy.isDupe(context, atEpochSecond: nil))
        copy.add(context, atEpochSecond: nil)
        original.reset()
        #expect(copy.isDupe(context, atEpochSecond: nil))
        #expect(!original.isDupe(context, atEpochSecond: nil))
    }
}
