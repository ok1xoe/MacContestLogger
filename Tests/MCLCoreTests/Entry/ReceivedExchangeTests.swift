import Foundation
import Testing
@testable import MCLCore

/// `ReceivedExchange.flat` per the source `ui/AppState.kt:3366-3368` (`flatExchange`).
@Suite struct ReceivedExchangeTests {

    private func flat(_ pairs: [(String?, String?)]) throws -> String? {
        let fields = EntryFixtures.received(try EntryFixtures.definition(EntryFixtures.cqww))
        return ReceivedExchange.flat(fields: fields, received: JavaLinkedMap(pairs))
    }

    @Test func joinsTrimmedValuesInFieldOrder() throws {
        #expect(try flat([("rst", "599"), ("zone", "15")]) == "599 15")
        // Field order, not map order; values trimmed (Kotlin `trim`).
        #expect(try flat([("zone", " 15 "), ("rst", "\u{00A0}599")]) == "599 15")
    }

    @Test func skipsMissingBlankAndNilValues() throws {
        #expect(try flat([("rst", "599")]) == "599")
        #expect(try flat([("rst", "  "), ("zone", "15")]) == "15")
        #expect(try flat([("rst", nil), ("zone", "15")]) == "15")
        #expect(try flat([("other", "X"), ("zone", "15")]) == "15")
    }

    @Test func nothingIsNil() throws {
        #expect(try flat([]) == nil)
        #expect(try flat([("rst", ""), ("zone", "\u{2003}")]) == nil)
    }

    @Test func noFieldsIsNil() {
        #expect(ReceivedExchange.flat(fields: [], received: JavaLinkedMap([("rst", "599")])) == nil)
    }
}
