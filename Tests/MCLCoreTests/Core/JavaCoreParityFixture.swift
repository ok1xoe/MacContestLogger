import Darwin
import Foundation
import Testing
@testable import MCLCore

/// Helpers of the gates `JavaCoreParityTests` and `JavaCoreParityBTests`: replay of a reference item
/// a maintainer-only probe (input rows from the reference, outputs computed by Swift in `*CoreParitySections`), the state
/// between the item's rows and field reading.
enum JavaCoreParityFixture {

    typealias Entry = JavaYamlParityTests.ReferenceFile
    typealias F = JavaIoParityFixture
    typealias Rows = [(String, [String])]

    struct Malformed: Error, CustomStringConvertible {
        let text: String
        var description: String { "malformed reference input: \(text)" }
    }

    /// State of one item between its rows (ESM script, SCP database, history, tracker, message log; log
    /// and statistics snapshot, pileup simulator) and a temporary directory for synthetic files (deleted by `cleanup`).
    /// Lives on one gate thread.
    final class Ctx {
        var esm: EsmProgress = .empty
        var esmScript: String = ""
        var scp: ScpDatabase = .empty()
        var history: CallHistory = .empty
        var tracker = RunModeTracker()
        var trackerScript: String = ""
        var messages = MessageLog(maxEntries: 1)
        var qsos: [Qso] = []
        var stats: ContestStats = .of([])
        var simulator: PileupSimulator?
        private var directory: String?

        /// The item's temporary directory (`mkdtemp`), created on first use.
        func temporaryDirectory() throws -> String {
            if let directory { return directory }
            let template: String = FileManager.default.temporaryDirectory.path + "/mcl-core-gate.XXXXXX"
            var bytes: [CChar] = Array(template.utf8CString)
            guard let made = mkdtemp(&bytes) else {
                throw Malformed(text: "mkdtemp selhal: \(errno)")
            }
            let path = String(cString: made)
            directory = path
            return path
        }

        func cleanup() {
            if let directory {
                try? FileManager.default.removeItem(atPath: directory)
            }
        }
    }

    static func compute(_ name: String, _ path: String, _ fields: [String], _ ctx: Ctx) throws -> Rows {
        if EntryCoreParitySections.handles(name) {
            return try EntryCoreParitySections.compute(name, path, fields, ctx)
        }
        if DataCoreParitySections.handles(name) {
            return try DataCoreParitySections.compute(name, path, fields, ctx)
        }
        if MiscCoreParitySections.names.contains(name) {
            return try MiscCoreParitySections.compute(name, path, fields, ctx)
        }
        if StatCoreParitySections.names.contains(name) {
            return try StatCoreParitySections.compute(name, path, fields, ctx)
        }
        if GoalCoreParitySections.names.contains(name) {
            return try GoalCoreParitySections.compute(name, path, fields, ctx)
        }
        if ToolCoreParitySections.names.contains(name) {
            return try ToolCoreParitySections.compute(name, path, fields, ctx)
        }
        if I18nCoreParitySections.names.contains(name) {
            return try I18nCoreParitySections.compute(name, path, fields, ctx)
        }
        throw Malformed(text: "unknown item \(name)")
    }

    /// Replays an item: after each input row of the reference the outputs computed by Swift. A Swift error at a row
    /// = the output row `SWIFT ERROR`, not a crash of the whole gate.
    static func replay(_ java: Entry) -> Entry {
        let ctx = Ctx()
        defer { ctx.cleanup() }
        var lines: [String] = []
        lines.reserveCapacity(java.lines.count)
        for line in java.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count >= 2, fields[1] == "in" else { continue }
            lines.append(line)
            let inputs: [String] = Array(fields.dropFirst(2))
            do {
                for (outPath, out) in try compute(java.relative, fields[0], inputs, ctx) {
                    lines.append(F.line(outPath, "out", out))
                }
            } catch {
                lines.append(F.line(fields[0], "out", ["SWIFT ERROR", String(describing: error)]))
            }
        }
        let sum: String = F.checksum(definition: nil, registry: "", lines: lines)
        return Entry(relative: java.relative, sha256: sum, lines: lines)
    }

    /// Replays all items — each on its own thread (not in the shared pool), concurrently at most as many
    /// as there are cores (CI 3), so the rest of the suite is not starved. Order of results = order of the reference.
    static func replayAll(_ reference: [Entry]) async throws -> [Entry] {
        let width: Int = max(2, ProcessInfo.processInfo.activeProcessorCount)
        return try await withThrowingTaskGroup(of: (Int, Entry).self) { group in
            var results = [Entry?](repeating: nil, count: reference.count)
            for (index, entry) in reference.enumerated() {
                if index >= width, let (done, replayed) = try await group.next() {
                    results[done] = replayed
                }
                group.addTask {
                    let replayed = try await JavaNetParityFixture.onGateThread(entry.relative) { replay(entry) }
                    return (index, replayed)
                }
            }
            for try await (index, entry) in group {
                results[index] = entry
            }
            return results.compactMap { $0 }
        }
    }

    // MARK: - Pole

    /// Text po `tx` (`~` = `nil`).
    static func text(_ field: String) -> String? {
        F.untx(field)
    }

    static func int(_ field: String) throws -> Int {
        guard let value = Int(field) else { throw Malformed(text: field) }
        return value
    }

    static func int32(_ field: String) throws -> Int32 {
        guard let value = Int32(field) else { throw Malformed(text: field) }
        return value
    }

    static func int64(_ field: String) throws -> Int64 {
        guard let value = Int64(field) else { throw Malformed(text: field) }
        return value
    }

    static func bool(_ field: String) -> Bool {
        field == "1"
    }

    static func b(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    /// An instant `epochSeconds, nanoseconds`.
    static func instant(_ seconds: String, _ nanos: String) throws -> JavaInstant {
        guard let value = JavaInstant.ofEpochSecond(try int64(seconds), try int64(nanos)) else {
            throw Malformed(text: "\(seconds) \(nanos)")
        }
        return value
    }

    static func fields(_ instant: JavaInstant) -> [String] {
        [String(instant.epochSecond), String(instant.nano)]
    }

    static func bytes(hex: String) throws -> [UInt8] {
        let digits: [UInt8] = Array(hex.utf8)
        guard digits.count % 2 == 0 else { throw Malformed(text: hex) }
        var out: [UInt8] = []
        out.reserveCapacity(digits.count / 2)
        var index = 0
        while index < digits.count {
            let pair = String(decoding: digits[index...(index + 1)], as: UTF8.self)
            guard let byte = UInt8(pair, radix: 16) else { throw Malformed(text: hex) }
            out.append(byte)
            index += 2
        }
        return out
    }

    /// A list `count, element…` from index `start`; returns the elements (after `untx`) and the index after the list.
    static func list(_ fields: [String], from start: Int) throws -> (items: [String], next: Int) {
        guard start < fields.count else { throw Malformed(text: "list past the end of the row") }
        let count: Int = try int(fields[start])
        guard start + count < fields.count else { throw Malformed(text: "list past the end of the row") }
        let items: [String] = fields[(start + 1)..<(start + 1 + count)].map { text($0) ?? "" }
        return (items, start + 1 + count)
    }

    /// Writes bytes into a file (overwrites).
    static func write(_ bytes: [UInt8], to path: String) throws {
        try Data(bytes).write(to: URL(fileURLWithPath: path))
    }

    /// `"THROW <class>: <message>"` as `CoreRefGen.run`.
    static func thrown(_ javaClass: String, _ message: String?) -> String {
        "THROW \(javaClass): \(message ?? "null")"
    }

    /// The result of a call as `CoreRefGen.run`: a value, or a Java exception (`ArithmeticException`,
    /// `IllegalArgumentException`) with a message. Another Swift error is a gate defect, not a result.
    static func run(_ body: () throws -> String) throws -> String {
        do {
            return try body()
        } catch let error as JavaArithmeticError {
            return thrown("ArithmeticException", error.message)
        } catch let error as JavaIllegalArgumentError {
            return thrown("IllegalArgumentException", error.message)
        }
    }

    /// An instant `epochSeconds, nanoseconds`, or `nil` for `~, ~`.
    static func optionalInstant(_ seconds: String, _ nanos: String) throws -> JavaInstant? {
        seconds == "~" ? nil : try instant(seconds, nanos)
    }

    /// An instant from `epochMilli` (a log QSO in the reference).
    static func instant(millis field: String) throws -> JavaInstant {
        let ms: Int64 = try int64(field)
        let second: Int64 = JavaMath.floorDiv(ms, 1000)
        guard let value = JavaInstant.ofEpochSecond(second, (ms - second * 1000) * 1_000_000) else {
            throw Malformed(text: field)
        }
        return value
    }

    /// A double from bits (`Long.toHexString(Double.doubleToRawLongBits(…))`).
    static func double(bits field: String) throws -> Double {
        guard let raw = UInt64(field, radix: 16) else { throw Malformed(text: field) }
        return Double(bitPattern: raw)
    }

    /// A float from bits (`Integer.toHexString(Float.floatToRawIntBits(…))`).
    static func float(bits field: String) throws -> Float {
        guard let raw = UInt32(field, radix: 16) else { throw Malformed(text: field) }
        return Float(bitPattern: raw)
    }

    /// Java `List.toString()` of numbers: `[1, 2]`.
    static func javaList(_ values: [Int]) -> String {
        "[" + values.map { String($0) }.joined(separator: ", ") + "]"
    }
}
