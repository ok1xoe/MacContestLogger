import CryptoKit
import Foundation
import Testing

/// The real output of `rigctl -l` from hamlib 4.7.1 (`Fixtures/hamlib-rigctl-l-4.7.1.txt`, 312 rows
/// including the header, `-text`) — the input of `HamlibRigList.parseLine` and `RigScanner.buildCandidates`.
/// Java results over it: a maintainer-only probe
/// (rows `RL.parseLine`, `RS.*`).
enum HamlibRigListFixture {

    static func data() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "hamlib-rigctl-l-4.7.1", withExtension: "txt"))
        return try Data(contentsOf: url)
    }

    /// Rows like Java `Files.readAllLines` (UTF-8, without a trailing empty row).
    static func lines() throws -> [String] {
        let text = String(decoding: try data(), as: UTF8.self)
        var lines: [String] = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines
    }
}

@Suite struct HamlibRigListFixtureTests {

    /// Bytes exactly as at measurement (no conversion of line endings).
    @Test func fixtureIsTheMeasuredFile() throws {
        let digest: String = SHA256.hash(data: try HamlibRigListFixture.data()).map { byte in
            let text = String(byte, radix: 16)
            return byte < 16 ? "0" + text : text
        }.joined()
        #expect(digest == "4b1118f75e3d3fd0066b45fba75f118c371fb8e91d89ca4f64b66d9f84c8937f")
        let lines = try HamlibRigListFixture.lines()
        #expect(lines.count == 312)
        #expect(lines.first?.hasPrefix(" Rig #  Mfg") == true)
    }
}
