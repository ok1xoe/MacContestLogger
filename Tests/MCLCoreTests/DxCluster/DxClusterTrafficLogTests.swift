import Foundation
import os
import Testing
@testable import MCLCore

/// `dxcluster/DxClusterTrafficLog` (the Java test has none): a ring buffer, row shape, listeners and the Java
/// exception on negative capacity.
@Suite struct DxClusterTrafficLogTests {

    @Test func ringBufferKeepsLastLinesWithPrefixes() throws {
        let log = DxClusterTrafficLog(maxLines: 2, clock: { Date(timeIntervalSince1970: 0) })
        try log.tx("SH/DX")
        try log.rx("DX de OK1ABC: 14025.0 OH2AS")
        try log.info("připojeno")
        let lines = log.snapshot()
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("  DX de OK1ABC: 14025.0 OH2AS"))
        #expect(lines[1].hasSuffix("  \u{00B7} připojeno"))
        // `HH:mm:ss` of local time + two spaces.
        let stamp = String(CatTrafficLog.timestamp(Date(timeIntervalSince1970: 0), timeZone: .current).prefix(8))
        #expect(lines[1].hasPrefix(stamp + "  "))
        try log.tx("BYE")
        #expect(log.snapshot()[1].hasSuffix("  \u{00BB} BYE"))
        log.clear()
        #expect(log.snapshot().isEmpty)
    }

    @Test func notifiesListenersUntilRemoved() throws {
        let log = DxClusterTrafficLog()
        let hits = OSAllocatedUnfairLock(initialState: 0)
        let id = log.addListener { hits.withLock { $0 += 1 } }
        try log.rx("a")
        try log.rx("b")
        log.removeListener(id)
        try log.rx("c")
        #expect(hits.withLock { $0 } == 2)
        #expect(log.maxLines == 1000)
    }

    /// Java: `addLast`, then `removeFirst` on an empty queue → `NoSuchElementException`, the buffer empty.
    @Test func negativeCapacityThrowsLikeJava() throws {
        let log = DxClusterTrafficLog(maxLines: -1)
        #expect(throws: JavaNoSuchElementError.self) { try log.rx("x") }
        #expect(log.snapshot().isEmpty)
        let zero = DxClusterTrafficLog(maxLines: 0)
        try zero.rx("x")
        #expect(zero.snapshot().isEmpty)
    }
}
