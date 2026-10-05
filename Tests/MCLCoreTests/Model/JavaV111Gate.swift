import Foundation
@testable import MCLCore

/// Runs a Java parity gate with the band table of Java v1.1.1 (160 m – 70 cm), so the frozen reference
/// fixtures, which know no band above 70 cm, keep being replayed unchanged (nothing is regenerated).
/// `MicrowaveDeltaTests` proves that without this switch the same inputs give a different, microwave-aware result.
enum JavaV111Gate {
    static func run<R>(_ body: () throws -> R) rethrows -> R {
        try Band.$javaV111Table.withValue(true, operation: body)
    }

    static func run<R>(_ body: () async throws -> R) async rethrows -> R {
        try await Band.$javaV111Table.withValue(true, operation: body)
    }
}
