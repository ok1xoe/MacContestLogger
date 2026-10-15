import Foundation
import Testing
@testable import MCLCore

/// The built-in QSO parties (CQP, FQP, NEQP): in-state / out-of-state by the ARRL section, who may be worked,
/// county aliases of the state multiplier, and the section list editing of the contest dialog.
@Suite struct QsoPartyDefinitionsTests {

    private static let at = Date(timeIntervalSince1970: 1_795_867_500)

    private static func session(_ id: String, myCall: String, section: String?) throws -> ContestSession {
        let dxcc = try SessionFixture.dxcc()
        let root: URL = PublishedContestDataTests.root
        let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(root.appendingPathComponent("multipliers"))
        let definition = try ContestDefinitionLoader.loadFile(root.appendingPathComponent("contests/\(id).yaml"))
        return ContestSession(definition: definition, dxcc: dxcc, registry: registry, myCall: myCall,
                              mySection: section)
    }

    @discardableResult
    private static func log(_ session: ContestSession, _ call: String, _ fields: (String, String)...,
                            band: String = "20m", mode: String = "CW") throws -> ContestSession.LogResult {
        var raw = JavaLinkedMap<String>()
        for (key, value) in fields {
            raw.put(key, value)
        }
        return try session.log(call: call, band: band, mode: mode, receivedRaw: raw, at: at)
    }

    @Test func cqpOutOfStateCountsCountiesAndWorksCaliforniaOnly() throws {
        let session = try Self.session("california-qso-party", myCall: "W1AW", section: "CT")
        try Self.log(session, "K6ABC", ("nr", "1"), ("qth", "ALAM"))
        try Self.log(session, "K6XYZ", ("nr", "2"), ("qth", "SDIE"), band: "40m")
        let notWorkable = try Self.log(session, "W2XYZ", ("nr", "3"), ("qth", "NY"))
        #expect(!notWorkable.workable)
        let score = try session.score()
        #expect(score.multTotal == 2)
        #expect(score.qsoPoints == 6)
    }

    @Test func cqpInStateCountsStatesAndTheFirstCountyAsCalifornia() throws {
        let session = try Self.session("california-qso-party", myCall: "K6ABC", section: "SCV")
        try Self.log(session, "W1AW", ("nr", "1"), ("qth", "CT"))
        try Self.log(session, "K6XYZ", ("nr", "2"), ("qth", "ALAM"))
        try Self.log(session, "K6QQQ", ("nr", "3"), ("qth", "SDIE"))
        try Self.log(session, "W3DC", ("nr", "4"), ("qth", "DC"))
        try Self.log(session, "W3MD", ("nr", "5"), ("qth", "MD"))
        try Self.log(session, "DL1ABC", ("nr", "6"), ("qth", "DX"))
        // CT, CA (two counties), MD (DC counts as MD); DX is no multiplier but scores.
        let score = try session.score()
        #expect(score.multTotal == 3)
        #expect(score.qsoPoints == 18)
    }

    @Test func neqpCountsCountiesOutsideAndStatesInside() throws {
        let outside = try Self.session("new-england-qso-party", myCall: "W2XYZ", section: "ENY")
        try Self.log(outside, "W1ABC", ("rst", "599"), ("qth", "MAMID"))
        try Self.log(outside, "W1ABD", ("rst", "59"), ("qth", "CTCAP"), mode: "SSB")
        #expect(try outside.score().multTotal == 2)
        #expect(try outside.score().qsoPoints == 3)
        let inside = try Self.session("new-england-qso-party", myCall: "W1ABC", section: "EMA")
        try Self.log(inside, "W1XYZ", ("rst", "599"), ("qth", "MAESS"))
        try Self.log(inside, "W1XYY", ("rst", "599"), ("qth", "MA"))
        try Self.log(inside, "DL1ABC", ("rst", "599"), ("qth", "DX"))
        // MA (county and state are one multiplier) + Germany.
        #expect(try inside.score().multTotal == 2)
    }

    @Test func fqpPowerFactorAndMobileCounties() throws {
        let session = try Self.session("florida-qso-party", myCall: "W1AW", section: "CT")
        session.setPowerCategory("QRP")
        try Self.log(session, "K4ABC", ("rst", "599"), ("qth", "ALC"))
        // A mobile in another county is a new station.
        let moved = try Self.log(session, "K4ABC", ("rst", "599"), ("qth", "BAK"))
        #expect(!moved.dupe)
        let score = try session.score()
        #expect(score.multTotal == 2)
        #expect(score.total == 4 * 2 * 3)
    }

    @Test func partyMessageFollowsTheSection() throws {
        let definition = try ContestDefinitionLoader.loadFile(
            PublishedContestDataTests.root.appendingPathComponent("contests/california-qso-party.yaml"))
        #expect(QsoPartyStatus.message(definition, section: "scv", ownEntity: 291)
                    == ContestMessage("QSO party: stanice ve státě (sekce %s)", .string("SCV")))
        #expect(QsoPartyStatus.message(definition, section: "CT", ownEntity: 291)
                    == ContestMessage("QSO party: stanice mimo stát (sekce %s)", .string("CT")))
        #expect(QsoPartyStatus.message(definition, section: "", ownEntity: 291)
                    == ContestMessage("QSO party: v datech stanice chybí ARRL sekce — počítám tě jako stanici mimo stát"))
        #expect(QsoPartyStatus.message(definition, section: "CT", ownEntity: 503) == ContestMessage(
            "QSO party: stanice mimo USA a Kanadu má v datech stanice ARRL sekci „DX“, ne „%s“ — oprav ji",
            .string("CT")))
        #expect(QsoPartyStatus.message(definition, section: "DX", ownEntity: 503)
                    == ContestMessage("QSO party: stanice mimo stát (sekce %s)", .string("DX")))
        var plain = definition
        plain.inState = nil
        #expect(QsoPartyStatus.message(plain, section: "SCV", ownEntity: 291) == nil)
    }

    @Test func sectionListIsEditedAndRestored() throws {
        let multipliers: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sections-\(UUID().uuidString)").appendingPathComponent("multipliers")
        defer { try? FileManager.default.removeItem(at: multipliers.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: multipliers, withIntermediateDirectories: true)
        let source: URL = PublishedContestDataTests.root.appendingPathComponent("multipliers")
        for name in ["fqp_counties.yaml", "fqp_counties.csv", "fqp_qth.yaml", "dxcc_entities.yaml"] {
            try FileManager.default.copyItem(at: source.appendingPathComponent(name),
                                             to: multipliers.appendingPathComponent(name))
        }
        let definition = try ContestDefinitionLoader.loadFile(
            PublishedContestDataTests.root.appendingPathComponent("contests/florida-qso-party.yaml"))
        // Only CSV-backed sets are editable (fqp_qth is inline, dxcc_entities external).
        #expect(SectionListFile.editableSets(definition, multipliersDir: multipliers) == ["fqp_counties"])
        let text: String = try SectionListFile.read("fqp_counties", multipliersDir: multipliers)
        #expect(text.hasPrefix("ALC,Alachua\nBAK,Baker\n"))
        #expect(!SectionListFile.hasBackup("fqp_counties", multipliersDir: multipliers))
        #expect(throws: SectionListFile.Failure.self) {
            try SectionListFile.save("fqp_counties", text: "# nothing\n", multipliersDir: multipliers)
        }
        #expect(try SectionListFile.save("fqp_counties", text: text + "XYZ;New county\n", multipliersDir: multipliers) == 68)
        #expect(SectionListFile.hasBackup("fqp_counties", multipliersDir: multipliers))
        #expect(try SectionListFile.read("fqp_counties", multipliersDir: multipliers).hasSuffix("XYZ,New county\n"))
        #expect(try SectionListFile.restore("fqp_counties", multipliersDir: multipliers))
        #expect(try SectionListFile.read("fqp_counties", multipliersDir: multipliers) == text)
        #expect(!SectionListFile.hasBackup("fqp_counties", multipliersDir: multipliers))
        #expect(try !SectionListFile.restore("fqp_counties", multipliersDir: multipliers))
    }
}
