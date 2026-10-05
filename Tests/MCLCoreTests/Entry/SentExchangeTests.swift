import Foundation
import Testing
@testable import MCLCore

/// Definitions shared by the entry-form tests.
enum EntryFixtures {

    static let cqww = """
        schemaVersion: 1
        id: test-cqww
        metadata: { name: "Test CQ WW" }
        bands: [80m, 40m, 20m]
        modes: [CW]
        exchange:
          sent:
            - { id: rst,  type: RST,     source: AUTO_RST }
            - { id: zone, type: CQ_ZONE, source: FROM_STATION }
          received:
            - { id: rst,  type: RST,     required: true }
            - { id: zone, type: CQ_ZONE, required: true }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 1 }
          total: "qsoPoints"
        dupe: { scope: PER_BAND }
        """

    /// Rover / county line (`ROVER_QTH`), two modes.
    static let qsoParty = """
        schemaVersion: 1
        id: test-qp
        metadata: { name: "Test QSO Party" }
        bands: [80m, 40m, 20m]
        modes: [CW, SSB]
        exchange:
          sent:
            - { id: rst, type: RST,  source: AUTO_RST }
            - { id: qth, type: TEXT, source: ROVER_QTH }
          received:
            - { id: rst,  type: RST,  required: true }
            - { id: cnty, type: TEXT, required: true }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 1 }
          total: "qsoPoints"
        dupe: { scope: PER_BAND_MODE }
        """

    /// Serial number, a station value and a manual field; `nr` is received.
    static let serial = """
        schemaVersion: 1
        id: test-serial
        metadata: { name: "Test Serial" }
        bands: [80m, 40m, 20m]
        modes: [CW, SSB]
        exchange:
          sent:
            - { id: rst,    type: RST,    source: AUTO_RST }
            - { id: nr,     type: SERIAL, source: AUTO_SERIAL }
            - { id: name,   type: TEXT,   source: FROM_STATION }
            - { id: manual, type: TEXT,   source: MANUAL }
          received:
            - { id: rst,  type: RST,    required: true }
            - { id: nr,   type: SERIAL, required: true }
            - { id: name, type: TEXT,   required: true }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 1 }
          total: "qsoPoints"
        dupe: { scope: PER_BAND_MODE }
        """

    /// No sent fields at all.
    static let noSent = """
        schemaVersion: 1
        id: test-nosent
        metadata: { name: "Test No Sent" }
        bands: [20m]
        modes: [CW]
        exchange:
          sent: []
          received:
            - { id: rst, type: RST, required: true }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 1 }
          total: "qsoPoints"
        dupe: { scope: PER_BAND }
        """

    static func definition(_ yaml: String) throws -> ContestDefinition {
        try SessionFixture.definition(yaml)
    }

    static func setup(_ values: [String: String]) -> ContestSetup {
        var setup = ContestSetup()
        setup.sentExchange = values
        return setup
    }

    static func received(_ definition: ContestDefinition) -> [ContestDefinition.ExchangeField] {
        (definition.exchange?.received ?? []).compactMap { $0 }
    }
}

/// `SentExchange` per the source `ui/AppState.kt:3781-3810` (`sentExchangeText`, `sentExchangeFlat`) —
/// outside the gate, hence an exhaustive case table.
@Suite struct SentExchangeTests {

    private func text(_ yaml: String?, _ setup: [String: String]?, _ mode: Mode = .cw, serial: Int = 7,
                      roverQth: String = "", countyLine: [String] = []) throws -> String {
        let definition = try yaml.map { try EntryFixtures.definition($0) }
        return SentExchange.text(definition: definition, setup: setup.map { EntryFixtures.setup($0) }, mode: mode,
                                 serial: serial, roverQth: roverQth, countyLine: countyLine)
    }

    private func flat(_ yaml: String?, _ setup: [String: String]?, _ mode: Mode = .cw, serial: Int = 7,
                      rstSent: String = "", ownQth: String? = nil) throws -> String? {
        let definition = try yaml.map { try EntryFixtures.definition($0) }
        return SentExchange.flat(definition: definition, setup: setup.map { EntryFixtures.setup($0) }, mode: mode,
                                 serial: serial, rstSent: rstSent, ownQth: ownQth)
    }

    // MARK: - text (KA:3781-3790)

    @Test func textWithoutContestIsEmpty() throws {
        #expect(try text(nil, ["zone": "15"]) == "")
    }

    @Test func textJoinsNonBlankDefaults() throws {
        #expect(try text(EntryFixtures.cqww, ["zone": "15"]) == "599 15")
        #expect(try text(EntryFixtures.cqww, ["zone": "15"], .ssb) == "59 15")
        // A missing setup or a blank station value drops out (Kotlin `isNotBlank`, NBSP is blank in Kotlin).
        #expect(try text(EntryFixtures.cqww, nil) == "599")
        #expect(try text(EntryFixtures.cqww, ["zone": "  "]) == "599")
        #expect(try text(EntryFixtures.cqww, ["zone": "\u{00A0}"]) == "599")
        // U+0085 is not blank for Kotlin.
        #expect(try text(EntryFixtures.cqww, ["zone": "\u{0085}"]) == "599 \u{0085}")
        // Values are not trimmed.
        #expect(try text(EntryFixtures.cqww, ["zone": " 15 "]) == "599  15 ")
    }

    @Test func textUsesSerialAndSkipsManual() throws {
        #expect(try text(EntryFixtures.serial, ["name": "TOM"], serial: 42) == "599 42 TOM")
        #expect(try text(EntryFixtures.serial, ["name": "TOM"], .ssb, serial: 1) == "59 1 TOM")
    }

    @Test func textCountyLineJoinsCountiesWithSlash() throws {
        #expect(try text(EntryFixtures.qsoParty, nil, roverQth: "ESX", countyLine: ["DAD", "JEF"]) == "599 DAD/JEF")
        #expect(try text(EntryFixtures.qsoParty, nil, countyLine: ["DAD"]) == "599 DAD")
    }

    @Test func textRoverQthOtherwise() throws {
        #expect(try text(EntryFixtures.qsoParty, nil, roverQth: "ESX") == "599 ESX")
        // The configured rover QTH is used as is (not trimmed).
        #expect(try text(EntryFixtures.qsoParty, nil, roverQth: " ESX ") == "599  ESX ")
        #expect(try text(EntryFixtures.qsoParty, nil) == "599")
    }

    @Test func textNoSentFieldsIsEmpty() throws {
        #expect(try text(EntryFixtures.noSent, nil) == "")
    }

    // MARK: - flat (KA:3797-3810)

    @Test func flatWithoutContestIsNil() throws {
        #expect(try flat(nil, ["zone": "15"]) == nil)
    }

    @Test func flatNoSentFieldsIsNil() throws {
        #expect(try flat(EntryFixtures.noSent, nil) == nil)
    }

    @Test func flatUsesActuallySentRst() throws {
        #expect(try flat(EntryFixtures.cqww, ["zone": "15"]) == "599 15")
        #expect(try flat(EntryFixtures.cqww, ["zone": "15"], rstSent: "579") == "579 15")
        #expect(try flat(EntryFixtures.cqww, ["zone": "15"], .ssb) == "59 15")
        // Blank sent RST (Kotlin `isNotBlank`) → the mode default.
        #expect(try flat(EntryFixtures.cqww, ["zone": "15"], rstSent: "  ") == "599 15")
        #expect(try flat(EntryFixtures.cqww, ["zone": "15"], rstSent: "\t") == "599 15")
        #expect(try flat(EntryFixtures.cqww, ["zone": "15"], rstSent: "\u{00A0}") == "599 15")
    }

    @Test func flatRemovesWhitespaceInsideValues() throws {
        #expect(try flat(EntryFixtures.cqww, ["zone": "15"], rstSent: " 5 7 9 ") == "579 15")
        #expect(try flat(EntryFixtures.cqww, ["zone": " 1 5 "]) == "599 15")
        #expect(try flat(EntryFixtures.cqww, ["zone": "1\t\n5"]) == "599 15")
        // Java `\s` is ASCII only: an inner NBSP stays; a leading/trailing one goes with Kotlin `trim`.
        #expect(try flat(EntryFixtures.cqww, ["zone": "1\u{00A0}5"]) == "599 1\u{00A0}5")
        #expect(try flat(EntryFixtures.cqww, ["zone": "\u{00A0}15\u{00A0}"]) == "599 15")
        // U+0085 is neither Kotlin whitespace nor Java `\s`.
        #expect(try flat(EntryFixtures.cqww, ["zone": "\u{0085}"]) == "599 \u{0085}")
    }

    @Test func flatEmptyValuesHoldPositionWithDash() throws {
        #expect(try flat(EntryFixtures.cqww, nil) == "599 -")
        #expect(try flat(EntryFixtures.cqww, ["zone": ""]) == "599 -")
        #expect(try flat(EntryFixtures.cqww, ["zone": "\u{00A0}"]) == "599 -")
        #expect(try flat(EntryFixtures.serial, nil, serial: 42) == "599 42 - -")
        #expect(try flat(EntryFixtures.serial, ["name": "TOM"], serial: 42) == "599 42 TOM -")
    }

    @Test func flatRoverQthPerCopy() throws {
        #expect(try flat(EntryFixtures.qsoParty, nil, ownQth: "ESX") == "599 ESX")
        #expect(try flat(EntryFixtures.qsoParty, nil, ownQth: "ES X") == "599 ESX")
        #expect(try flat(EntryFixtures.qsoParty, nil, ownQth: nil) == "599 -")
        #expect(try flat(EntryFixtures.qsoParty, nil, .ssb, ownQth: "DAD") == "59 DAD")
    }
}
