import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `QsoMarksTest` (2 cases) + labels by UTF-16.
@Suite struct QsoMarksTests {

    static func qso(_ id: Int64, _ minute: Int, _ call: String, _ hz: Int, _ exch: String) -> Qso {
        ScoreBreakdownTests.qso(minute, call, hz, exch, id: id)
    }

    @Test func marksNewMultipliersOnFirstQsoOnly() throws {
        let s = try SessionFixture.session("@cq-ww-ssb.yaml")

        // The order in the list is deliberately reversed — marks follow the QSO time.
        let m = QsoMarks.compute(s, [
            Self.qso(3, 2, "DL1ABC", 14_220_000, "59 14"),
            Self.qso(2, 1, "DL2XYZ", 14_210_000, "59 14"),
            Self.qso(1, 0, "W1AW", 14_200_000, "59 5"),
        ])

        let w1 = try #require(m[1])
        #expect(w1.newMults.count == 2, "W1AW: zone 5 + country W")
        #expect(w1.newMults[0] == "5")
        #expect(w1.newMults[1] == "K", "a country is reported by prefix, not by the internal entity number")
        #expect(try #require(m[2]).isMultiplier, "DL2XYZ: first zone 14 and country DL")
        let dl1 = try #require(m[3])
        #expect(!dl1.isMultiplier, "DL1ABC: nothing new")
        #expect(dl1.points > 0)
        #expect(!dl1.dupe)
    }

    @Test func qsoInAModeTheContestDoesNotHaveHasZeroPointsAndNoMultiplier() throws {
        // CQ WW SSB has modes: [SSB]. A CW QSO does not belong here, so the log must not
        // show points or a new multiplier for it — otherwise the Points and Mult columns would claim something
        // different from the score, which has not counted it since PR #131.
        let s = try SessionFixture.session("@cq-ww-ssb.yaml")
        var foreign = Self.qso(1, 0, "W1AW", 14_200_000, "59 5")
        foreign.mode = .cw // the contest is phone
        let m = QsoMarks.compute(s, [foreign])

        let mark = try #require(m[1])
        #expect(mark.points == 0)
        #expect(mark.newMults.isEmpty)
        #expect(!mark.isMultiplier)
    }

    /// Text of the "Mult" column = values separated by a space (Java `String.join(" ", …)`).
    @Test func multTextJoinsWithSpace() {
        #expect(QsoMarks.Mark(points: 1, dupe: false, newMults: ["14", "DL"]).multText == "14 DL")
        #expect(QsoMarks.Mark(points: 1, dupe: false, newMults: []).multText == "")
    }

    /// Controller decision: labels are a Java map by UTF-16, not a Swift dictionary.
    /// A set with values `K` (prefix `KK`) and KELVIN SIGN (prefix `KELVIN`): `FixedMultiplierSet`
    /// holds both (keys by UTF-16) and so do the labels, so each value gets
    /// its own prefix as in Java — table `ViewsMeasuredTests`, row `M kelvin`. A dictionary would
    /// merge both values and give one of them a foreign label.
    @Test func labelsAreKeyedByUtf16() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let set = "id: kelvin_set\nkind: FIXED\nkeyType: TEXT\nenumerable: true\nvalues:\n"
            + "  - { key: K, attributes: { prefix: KK } }\n  - { key: \"\u{212A}\", attributes: { prefix: KELVIN } }\n"
        try Data(set.utf8).write(to: dir.appendingPathComponent("s.yaml"))
        let dxcc = try SessionFixture.dxcc()
        let registry = try SessionFixture.registry(dxcc).loadDir(dir)
        let def = try SessionFixture.definition("{id: kv, modes: [CW], exchange: {received: [{id: rst, type: RST}, "
            + "{id: k, type: TEXT}]}, multipliers: [{id: m, set: kelvin_set, from: k, scope: PER_BAND}], "
            + "scoring: {qsoPoints: {default: 1}}}")
        let s = ContestSession(definition: def, dxcc: dxcc, registry: registry, myCall: "OK1XOE")

        let labels = s.multiplierLabels(setId: "kelvin_set")
        #expect(labels["\u{212A}"] == "KELVIN")
        #expect(labels["K"] == "KK", "K and KELVIN SIGN are different keys")

        var a = Self.qso(1, 0, "DL1ABC", 14_025_000, "599 \u{212A}")
        a.mode = .cw
        var b = Self.qso(2, 1, "DL2ABC", 7_025_000, "599 K")
        b.mode = .cw
        let m = QsoMarks.compute(s, [a, b])
        #expect(m[1]?.multText == "KELVIN")
        #expect(m[2]?.multText == "KK", "the foreign KELVIN label does not leak")
    }
}
