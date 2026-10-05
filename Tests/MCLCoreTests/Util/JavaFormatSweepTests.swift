import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// A sweep of `%.1f` / `%9.1f` (`LogExports`) and `%.6f` (`AdifWriter`) over frequencies
/// 0–30 MHz and the neighbourhoods of 50, 144 and 432 MHz in 10 Hz steps against the Java reference
/// (`JavaFormatSweepReference`, probe `ProbeFormat sweep`): SHA-256 of 1 MHz chunks
/// and a fingerprint of the whole over them. Every tenth Hz ends in 50 and there Java (HALF_UP over the decimal
/// expansion) and C `printf` diverge — see `printfDivergesFromReference`.
@Suite struct JavaFormatSweepTests {

    /// One-row formatters — swappable, so it can be shown that the gate goes red.
    struct Formatters: Sendable {
        let oneDecimal: @Sendable (Double) -> String
        let nineWide: @Sendable (Double) -> String
        let sixDecimals: @Sendable (Double) -> String
    }

    /// `%.1f` and `%.6f` without a width go straight through `fixed` (the pattern is then not parsed
    /// again for every value — `format` with them gives the same, see `JavaFormatTests`);
    /// `%9.1f` goes the whole way through `format`, so the sweep also guards alignment.
    static let java = Formatters(
        oneDecimal: { JavaFormat.fixed($0, precision: 1) },
        nineWide: { JavaFormat.format("%9.1f", .double($0)) },
        sixDecimals: { JavaFormat.fixed($0, precision: 6) })

    static func line(_ hz: Int, _ formatters: Formatters) -> String {
        let khz = Double(hz) / 1000.0
        let mhz = Double(hz) / 1_000_000.0
        var text = String(hz)
        text += "\t" + formatters.oneDecimal(khz)
        text += "\t" + formatters.nineWide(khz)
        text += "\t" + formatters.sixDecimals(mhz)
        return text + "\n"
    }

    struct Chunk: Sendable {
        let from: Int
        let to: Int
        let count: Int
        let sha256: String
    }

    struct Digest {
        var count = 0
        var total = ""
        var chunks: [Chunk] = []
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { byte in
            let text = String(byte, radix: 16)
            return byte < 16 ? "0" + text : text
        }.joined()
    }

    /// Chunks as in the probe: in every range of 1 MHz from its start.
    static func chunkRanges(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        let step = JavaFormatSweepReference.step
        let size = JavaFormatSweepReference.chunk
        var out: [ClosedRange<Int>] = []
        for range in ranges {
            for start in stride(from: range.lowerBound, through: range.upperBound, by: size) {
                out.append(start...min(start + size - step, range.upperBound))
            }
        }
        return out
    }

    static func hashChunk(_ range: ClosedRange<Int>, _ formatters: Formatters) -> Chunk {
        var hasher = SHA256()
        var count = 0
        for hz in stride(from: range.lowerBound, through: range.upperBound, by: JavaFormatSweepReference.step) {
            hasher.update(data: Data(line(hz, formatters).utf8))
            count += 1
        }
        return Chunk(from: range.lowerBound, to: range.upperBound, count: count, sha256: hex(hasher.finalize()))
    }

    /// Chunks are computed concurrently; the whole is a SHA-256 over their fingerprints (`hex + "\n"`)
    /// in order — like `ProbeFormat sweep`.
    static func digest(_ ranges: [ClosedRange<Int>], _ formatters: Formatters) async -> Digest {
        let parts = chunkRanges(ranges)
        let chunks: [Chunk] = await withTaskGroup(of: (Int, Chunk).self) { group in
            for (index, range) in parts.enumerated() {
                group.addTask { (index, hashChunk(range, formatters)) }
            }
            var collected: [(Int, Chunk)] = []
            for await result in group {
                collected.append(result)
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var total = SHA256()
        var result = Digest()
        for chunk in chunks {
            total.update(data: Data((chunk.sha256 + "\n").utf8))
            result.count += chunk.count
        }
        result.chunks = chunks
        result.total = hex(total.finalize())
        return result
    }

    /// Chunks whose SHA-256 does not match Java — tracking down: `ProbeFormat lines FROM TO`.
    static func mismatchedChunks(_ digest: Digest) -> [String] {
        let reference = JavaFormatSweepReference.chunks
        var out: [String] = []
        for (index, chunk) in digest.chunks.enumerated() {
            let expected = index < reference.count ? reference[index].sha256 : "<missing>"
            if chunk.sha256 != expected {
                out.append(String(chunk.from) + "..." + String(chunk.to))
            }
        }
        return out
    }

    @Test func firstHalfLinesMatchJava() {
        let lines = [50, 150, 250, 350, 450, 550, 650, 750, 850, 950, 1050, 1150].map { Self.line($0, Self.java) }
        #expect(lines == JavaFormatSweepReference.firstHalfLines)
    }

    @Test func sweepMatchesJavaReference() async {
        let digest = await Self.digest(JavaFormatSweepReference.ranges, Self.java)
        #expect(digest.count == JavaFormatSweepReference.totalCount)
        #expect(digest.chunks.count == JavaFormatSweepReference.chunks.count)
        let mismatched = Self.mismatchedChunks(digest)
        #expect(mismatched.isEmpty, "mismatched chunks (Hz): \(mismatched.prefix(10))")
        #expect(digest.total == JavaFormatSweepReference.totalSha256)
    }

    /// A check that the gate can go red: C `printf` (`String(format:)`) on the
    /// chunk 14.0–15.0 MHz does **not** match the reference (`%.1f` of 14025.05 gives 14025.0).
    /// `String(format:)` is here deliberately — as a negative check, not an implementation.
    @Test func printfDivergesFromReference() async {
        let printf = Formatters(
            oneDecimal: { String(format: "%.1f", $0) },
            nineWide: { String(format: "%9.1f", $0) },
            sixDecimals: { String(format: "%.6f", $0) })
        let range = 14_000_000...14_999_990
        let digest = await Self.digest([range], printf)
        let reference = JavaFormatSweepReference.chunks.first { $0.from == range.lowerBound }
        #expect(reference != nil)
        #expect(digest.chunks.first?.sha256 != reference?.sha256)
        #expect(String(format: "%.1f", 14025.05) == "14025.0")
        let javaDigest = await Self.digest([range], Self.java)
        #expect(javaDigest.chunks.first?.sha256 == reference?.sha256)
    }
}
