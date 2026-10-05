import Foundation
import Testing
@testable import MCLCore

/// Port of `hamqth/GridDatabaseTest` (2).
@Suite struct GridDatabaseTests {

    private func parse(_ csv: String) -> GridDatabase {
        GridDatabase.fromCsv(Data(csv.utf8))
    }

    @Test func looksUpGridCaseInsensitive() {
        let db = parse("znacka;lokator;pocet\nOK1XOE;JO70;5\nDL1ABC;JO60ab;2\n")
        #expect(db.grid("ok1xoe") == "JO70")
        #expect(db.grid("DL1ABC") == "JO60ab")
        #expect(db.grid("N0BODY") == nil)
        #expect(db.grid(nil) == nil)
    }

    @Test func skipsBomAndBlankLinesAndMissingGrid() {
        let db = parse("\u{FEFF}znacka;lokator;pocet\n\nW1AW;FN31;9\nBADROW\nXX;;3\n")
        #expect(db.grid("W1AW") == "FN31")
        #expect(db.grid("BADROW") == nil)
        #expect(db.grid("XX") == nil, "an empty locator is not added")
        #expect(db.size == 1)
    }
}
