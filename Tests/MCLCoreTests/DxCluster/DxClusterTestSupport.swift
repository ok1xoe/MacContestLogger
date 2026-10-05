import Foundation
import os

/// Java `Instant.parse("…Z")` for tests of the `dxcluster/` package (whole UTC seconds only).
func dxInstant(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: iso) else {
        preconditionFailure("invalid instant in test: \(iso)")
    }
    return date
}

/// An adjustable clock (Java `AtomicReference<Instant>` + `now::get`).
final class DxTestClock: Sendable {
    private let current: OSAllocatedUnfairLock<Date>

    init(_ iso: String) {
        current = OSAllocatedUnfairLock(initialState: dxInstant(iso))
    }

    var now: Date { current.withLock { $0 } }

    func set(_ date: Date) {
        current.withLock { $0 = date }
    }

    func set(_ iso: String) {
        set(dxInstant(iso))
    }

    /// A time source for `SpotBuffer`.
    var source: @Sendable () -> Date {
        { [self] in self.now }
    }
}

/// The test's temporary directory (Java `@TempDir`), deleted after use.
func withDxTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-dxcluster-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}
