import Foundation
import Testing

/// Shared fixture `Fixtures/dxcc-test.json` — a verbatim copy of the Java
/// `src/test/resources/dxcc-test.json` (5 entities: OK, W, VE, DL and a deleted XX).
///
/// The single copy for `DxccResolverTests` and `MultiplierSetRegistryTests`,
/// so that two versions of the same thing do not drift apart over time.
enum DxccTestFixture {
    static func data() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "dxcc-test", withExtension: "json"))
        return try Data(contentsOf: url)
    }
}
