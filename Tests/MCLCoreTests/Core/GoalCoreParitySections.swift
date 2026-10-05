import Foundation
import Testing
@testable import MCLCore

/// Swift side of the `goal.*` sections of the Java parity suite (maintainer-only probe): `GoalFileParser`,
/// `GoalSet.goalFor`/`hoursOf`, `GoalsFromLog.derive`, `GoalFileWriter` a `GoalFileIO.readLines`.
enum GoalCoreParitySections {

    typealias Ctx = JavaCoreParityFixture.Ctx
    typealias Rows = JavaCoreParityFixture.Rows
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture

    static let names: [String] = ["goal.PARSE", "goal.TIME", "goal.DERIVE", "goal.FMT", "goal.READ"]

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        switch name {
        case "goal.PARSE": return [(path, try parse(f))]
        case "goal.TIME": return [(path, try time(f))]
        case "goal.DERIVE": return [(path, try derive(f))]
        case "goal.FMT": return [(path, path.hasPrefix("c/") ? try fromConfig(f) : try format(f))]
        case "goal.READ": return [(path, try read(f, ctx))]
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    /// `new TreeMap<>(map).toString()`.
    static func sorted(_ map: [Int32: Int32]) -> String {
        let parts: [String] = map.keys.sorted().map { "\($0)=\(map[$0] ?? 0)" }
        return "{" + parts.joined(separator: ", ") + "}"
    }

    /// `count, element…` after `tx`.
    static func list(_ items: [String]) -> [String] {
        [String(items.count)] + items.map { F.tx($0) }
    }

    /// A map `count, key, value…` from index `start`.
    static func map(_ f: [String], from start: Int) throws -> [Int32: Int32] {
        let count: Int = try X.int(f[start])
        guard start + 2 * count < f.count else { throw X.Malformed(text: "map past the end of the row") }
        var out: [Int32: Int32] = [:]
        for index in 0..<count {
            let key: Int32 = try X.int32(f[start + 1 + 2 * index])
            out[key] = try X.int32(f[start + 2 + 2 * index])
        }
        return out
    }

    /// `THROW <class>` without a message like `GoalSections.run`.
    static func run(_ body: () throws(JavaDateTimeException) -> String) -> String {
        do {
            return try body()
        } catch {
            return "THROW DateTimeException"
        }
    }

    static func parse(_ f: [String]) throws -> [String] {
        let band: String? = X.text(f[0])
        let lines: [String] = try X.list(f, from: 1).items
        let result: GoalImport = GoalFileParser.parse(lines, band)
        return [sorted(result.goals.entries)] + list(result.ignoredLines) + list(result.bands)
    }

    static func time(_ f: [String]) throws -> [String] {
        let start: JavaInstant? = try X.optionalInstant(f[0], f[1])
        let when: JavaInstant? = try X.optionalInstant(f[2], f[3])
        let duration: Int32 = try X.int32(f[4])
        let goals = GoalSet.of(try map(f, from: 5))
        let goal: String = run { () throws(JavaDateTimeException) -> String in String(try goals.goalFor(start, when)) }
        let hours: String = run { () throws(JavaDateTimeException) -> String in
            X.javaList(try GoalSet.hoursOf(start, duration).map { Int($0) })
        }
        return [goal, hours]
    }

    static func derive(_ f: [String]) throws -> [String] {
        let start: JavaInstant? = try X.optionalInstant(f[0], f[1])
        let band: Band? = f[2] == "~" ? nil : Band.from(adif: f[2])
        let count: Int = try X.int(f[3])
        guard 4 + 3 * count == f.count else { throw X.Malformed(text: "goals log") }
        var log: [Qso] = []
        for index in 0..<count {
            let base: Int = 4 + 3 * index
            var q = Qso()
            q.call = "DL1ABC"
            q.timestampUtc = f[base] == "~" ? nil : try X.instant(millis: f[base]).date
            q.band = f[base + 1] == "~" ? nil : Band.from(adif: f[base + 1])
            q.deleted = X.bool(f[base + 2])
            log.append(q)
        }
        return [run { () throws(JavaDateTimeException) -> String in
            sorted(try GoalsFromLog.derive(log, start, band).entries)
        }]
    }

    static func format(_ f: [String]) throws -> [String] {
        let goals = GoalSet.of(try map(f, from: 0))
        let config: [String: Int] = GoalFileWriter.toConfigMap(goals)
        let keys: [String] = config.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
        let pairs: [String] = keys.map { "\($0)=\(config[$0] ?? 0)" }
        return list(GoalFileWriter.format(goals)) + [F.tx(GoalFileWriter.toText(goals)), pairs.joined(separator: ",")]
    }

    static func fromConfig(_ f: [String]) throws -> [String] {
        let count: Int = try X.int(f[0])
        guard 1 + 2 * count == f.count else { throw X.Malformed(text: "goals configuration") }
        var stored: [String: Int] = [:]
        for index in 0..<count {
            stored[X.text(f[1 + 2 * index]) ?? ""] = try X.int(f[2 + 2 * index])
        }
        return [sorted(GoalFileWriter.fromConfigMap(stored).entries)]
    }

    static func read(_ f: [String], _ ctx: Ctx) throws -> [String] {
        let file: String = try ctx.temporaryDirectory() + "/goals-read.txt"
        try X.write(try X.bytes(hex: f[0]), to: file)
        defer { try? FileManager.default.removeItem(atPath: file) }
        do throws(JavaIOError) {
            return list(try GoalFileIO.readLines(file))
        } catch {
            let simple: String = error.javaClass.components(separatedBy: ".").last ?? error.javaClass
            return [F.tx(X.thrown(simple, error.message))]
        }
    }
}
