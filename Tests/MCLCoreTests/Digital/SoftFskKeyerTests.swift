import Foundation
@testable import MCLCore
import Testing

/// The built-in FSK keyer (MMTTY EXTFSK, RYRY's soft FSK) on a fake line with a virtual clock: the bit timing of
/// every edge, the start/stop bits, the polarity, the end of the modulator and a broken line. Nothing real opens.
@Suite struct SoftFskKeyerTests {

    /// A clock whose sleeps only move virtual time.
    final class VirtualClock: FskClock, @unchecked Sendable {
        private let lock = NSLock()
        private var time: UInt64 = 1_000_000_000

        func now() -> UInt64 {
            lock.withLock { time }
        }

        func sleep(untilNanos deadline: UInt64) {
            lock.withLock { time = max(time, deadline) }
        }
    }

    /// The line's levels with their virtual times.
    final class Line: CwKeyLines, @unchecked Sendable {
        private let lock = NSLock()
        private let clock: VirtualClock
        private var log: [(UInt64, Bool)] = []
        var failAfter: Int?
        let hasPtt = false

        init(clock: VirtualClock) {
            self.clock = clock
        }

        func setKey(_ down: Bool) throws {
            try lock.withLock {
                if let limit = failAfter, log.count >= limit {
                    throw ByteTransportError("line broken")
                }
                log.append((clock.now(), down))
            }
        }

        func setPtt(_ on: Bool) throws {}

        func close() {}

        var edges: [(UInt64, Bool)] {
            lock.withLock { log }
        }
    }

    /// The codes once, then the end.
    final class Codes: @unchecked Sendable {
        private let lock = NSLock()
        private var codes: [UInt8]

        init(_ codes: [UInt8]) {
            self.codes = codes
        }

        func next() -> (codes: [UInt8], finished: Bool) {
            lock.withLock {
                let out = codes
                codes = []
                return (out, true)
            }
        }
    }

    static func run(_ codes: [UInt8], invert: Bool = false, failAfter: Int? = nil)
        -> (edges: [(UInt64, Bool)], keyer: SoftFskKeyer, ended: Bool) {
        let clock = VirtualClock()
        let line = Line(clock: clock)
        line.failAfter = failAfter
        let source = Codes(codes)
        let done = DispatchSemaphore(value: 0)
        let keyer = SoftFskKeyer(lines: line, baud: 50, stopBits: 1.5, invert: invert, clock: clock,
                                 source: { source.next() }, onEnd: { done.signal() })
        try? keyer.start()
        let ended: Bool = done.wait(timeout: .now() + .seconds(30)) == .success
        keyer.stop()
        return (line.edges, keyer, ended)
    }

    @Test func bitsAreTimedFromTheCharacterStart() throws {
        // MMTTY order 0b00011 → ITA2 0b11000: start (space), 0, 0, 0, 1, 1, stop (mark).
        let (edges, keyer, ended) = Self.run([0b00011])
        #expect(ended)
        #expect(keyer.charactersSent == 1)
        // Idle mark, start bit (space = key down), mark for bits 4-5 at 4 × 20 ms, the line stays mark.
        let levels: [Bool] = edges.map(\.1)
        #expect(Array(levels.prefix(3)) == [false, true, false], "\(levels)")
        #expect(levels.dropFirst(3).allSatisfy { !$0 }, "mark after the character, at the end and after stop")
        let start: UInt64 = edges[1].0
        #expect(edges[2].0 - start == 4 * 20_000_000, "the first mark bit after start + 3 space bits")
    }

    @Test func charactersFollowEachOtherAfterOneAndAHalfStopBits() throws {
        let (edges, keyer, _) = Self.run([0b11111, 0b11111])
        #expect(keyer.charactersSent == 2)
        let starts: [UInt64] = edges.filter(\.1).map(\.0)
        #expect(starts.count == 2)
        #expect(starts[1] - starts[0] == 150_000_000, "(1 + 5 + 1.5) bits of 20 ms")
    }

    @Test func invertedPolarityAndABrokenLine() throws {
        let (edges, _, _) = Self.run([0b00000], invert: true)
        #expect(edges.first?.1 == true, "idle mark = active line when inverted")
        let (_, keyer, ended) = Self.run([0b00000, 0b00000], failAfter: 2)
        #expect(ended, "a broken line ends the transmission")
        #expect(keyer.lastError != nil)
        #expect(SoftFskKeyer.reverse5(0b00001) == 0b10000)
    }
}
