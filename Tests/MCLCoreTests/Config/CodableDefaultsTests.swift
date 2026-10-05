import Foundation
import Testing
@testable import MCLCore

private struct Sample: Codable, Equatable {
    var host: String = "localhost"
    var port: Int = 7300
    var enabled: Bool = false

    enum CodingKeys: String, CodingKey { case host, port, enabled }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = c.value(.host, default: Sample().host)
        port = c.value(.port, default: Sample().port)
        enabled = c.value(.enabled, default: Sample().enabled)
    }
}

@Suite struct CodableDefaultsTests {
    @Test func missingKeysFallBackToDefaults() throws {
        let json = Data(#"{"host":"cluster.local"}"#.utf8)
        let s = try JSONDecoder().decode(Sample.self, from: json)
        #expect(s.host == "cluster.local")
        #expect(s.port == 7300)
        #expect(s.enabled == false)
    }

    @Test func wrongTypeFallsBackToDefaultInsteadOfThrowing() throws {
        let json = Data(#"{"port":"nesmysl"}"#.utf8)
        let s = try JSONDecoder().decode(Sample.self, from: json)
        #expect(s.port == 7300)
    }

    @Test func unknownKeysAreIgnored() throws {
        let json = Data(#"{"host":"a","zrusenaVolba":123}"#.utf8)
        let s = try JSONDecoder().decode(Sample.self, from: json)
        #expect(s.host == "a")
    }

    @Test func explicitNullFallsBackToDefault() throws {
        let json = Data(#"{"host":null}"#.utf8)
        let s = try JSONDecoder().decode(Sample.self, from: json)
        #expect(s.host == "localhost")
    }
}
