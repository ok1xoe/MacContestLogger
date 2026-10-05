import Foundation
import Testing
@testable import MCLCore

/// `cat/HamlibRigListTest.listNeverEmpty` (runs `rigctl -l` — only a list printout, controls nothing; without
/// hamlib the fallback list) + parsing of process output over a stand-in binary and the fallback list.
@Suite(.ioSafetyNet) struct HamlibRigListProcessTests {

    @Test func listNeverEmpty() async {
        #expect(await onOwnThread { HamlibRigList.list() }.isEmpty == false)
    }

    static let fallback = [
        RigModel(number: 1, mfg: "Hamlib", model: "Dummy"),
        RigModel(number: 2, mfg: "Hamlib", model: "NET rigctl"),
    ]

    /// An unrunnable binary and output without a single model → the Java fallback list.
    @Test func fallbackWithoutHamlib() async throws {
        let empty = try FakeDaemon("echo ' Rig #  Mfg  Model  Version'; exit 1")
        let missing: [RigModel] = await onOwnThread { HamlibRigList.list(binary: "/nonexistent/rigctl") }
        let none: [RigModel] = await onOwnThread { HamlibRigList.list(binary: empty.path) }
        #expect(missing == Self.fallback)
        #expect(none == Self.fallback)
    }

    /// Process output (stdout and stderr) goes row by row through `parseLine`: the hamlib 4.7.1 fixture → 311 models
    /// in file order, argument `-l`.
    @Test func parsesProcessOutput() async throws {
        let url = try #require(Bundle.module.url(forResource: "hamlib-rigctl-l-4.7.1", withExtension: "txt"))
        let daemon = try FakeDaemon("""
            [ "$*" = "-l" ] || exit 2
            cat '\(url.path)'
            echo '  9999  Stderr  Model-X  1.0  Stable' >&2
            """)
        let models: [RigModel] = await onOwnThread { HamlibRigList.list(binary: daemon.path) }
        let expected: [RigModel] = try HamlibRigListFixture.lines().compactMap(HamlibRigList.parseLine)
            + [RigModel(number: 9999, mfg: "Stderr", model: "Model-X")]
        #expect(models.count == 312)
        #expect(models == expected)
    }
}
