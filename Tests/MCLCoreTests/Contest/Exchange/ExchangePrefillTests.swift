import Foundation
import Testing
@testable import MCLCore

/// The received fields' `prefill` (N1MM's ARRL DX default power): the first matching rule's value, from the
/// definition only.
@Suite struct ExchangePrefillTests {

    /// The full DXCC list (the score check reference's `dxcc.json`); the session fixture's list has five entities.
    static func session(_ yaml: String, myCall: String) throws -> ContestSession {
        let dxcc = try DxccResolver.fromData(Data(contentsOf: ScoreCheckParityTests.dxccFile(.json)))
        return ContestSession(definition: try SessionFixture.definition(yaml), dxcc: dxcc,
                              registry: try SessionFixture.registry(dxcc), myCall: myCall, myGrid: nil)
    }

    static let yaml = """
        schemaVersion: 1
        id: prefill-test
        metadata: { name: "Prefill test" }
        bands: [20m]
        modes: [CW]
        stationClasses:
          - { id: wve, when: { entityIn: [291, 1] } }
          - { id: dx,  when: { not: { entityIn: [291, 1] } } }
        exchange:
          sent:
            - { id: rst, type: RST, source: AUTO_RST }
          received:
            - { id: rst, type: RST, required: true }
            - { id: state, type: TEXT, required: true, appliesWhen: { workedClass: wve } }
            - id: power
              type: TEXT
              required: true
              appliesWhen: { workedClass: dx }
              prefill:
                - { when: { entityIn: [54, 15] }, value: "200" }
                - { when: { continentIs: EU }, value: " 400 " }
                - { value: "100" }
        scoring: { qsoPoints: { mode: FIRST_MATCH, default: 1, rules: [] }, total: "qsoPoints" }
        dupe: { scope: PER_BAND }
        """

    @Test func theFirstMatchingRuleWins() throws {
        let session = try Self.session(Self.yaml, myCall: "K1AR")
        #expect(try session.exchangePrefill(call: "UA3AA").entries.map { "\($0.key ?? "")=\($0.value ?? "")" }
            == ["power=200"])
        #expect(try session.exchangePrefill(call: "UA9AA")["power"] == "200")
        #expect(try session.exchangePrefill(call: "DL1ABC")["power"] == "400", "trimmed")
        #expect(try session.exchangePrefill(call: "JA1AA")["power"] == "100", "a rule without when always holds")
        // A W/VE station has no power field to fill.
        #expect(try session.exchangePrefill(call: "W1AW").isEmpty)
    }

    @Test func aDefinitionWithoutPrefillFillsNothing() throws {
        let session = try Self.session("@cq-ww-cw.yaml", myCall: "K1AR")
        #expect(try session.exchangePrefill(call: "DL1ABC").isEmpty)
    }

    /// The published ARRL DX (both sides) definitions carry N1MM's default power table.
    @Test(arguments: ["arrl-dx-cw-wve.yaml", "arrl-dx-ssb-wve.yaml"])
    func arrlDxDefaultPower(file: String) throws {
        let url = PublishedContestDataTests.root.appendingPathComponent("contests/" + file)
        guard FileManager.default.fileExists(atPath: url.path) else { return }  // source tree not available
        let yaml = try String(contentsOf: url, encoding: .utf8)
        let session = try Self.session(yaml, myCall: "K1AR")
        let cases: [(String, String)] = [
            ("UA3AA", "200"), ("UA2FF", "200"), ("UA9AA", "200"), ("UN7AA", "200"), ("UR5AA", "200"),
            ("UK8AA", "200"), ("G4AA", "400"), ("GM3AA", "400"), ("GI4AA", "400"), ("GD4AA", "400"),
            ("GW4AA", "400"), ("I2AA", "500"), ("IT9AA", "500"), ("IS0AA", "500"), ("DL1ABC", "100"),
            ("JA1AA", "100"), ("KL7AA", "100"),
        ]
        for (call, power) in cases {
            let got: String? = try session.exchangePrefill(call: call)["power"]
            #expect(got == power, "\(call)")
        }
        // The DX side works W/VE: nothing to prefill.
        let dxSide = try Self.session(yaml, myCall: "OK1XOE")
        #expect(try dxSide.exchangePrefill(call: "W1AW").isEmpty)
    }
}
