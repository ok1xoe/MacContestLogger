import Foundation
import Testing
@testable import MCLCore

/// Swift side of the sections `run.*`, `sked.*`, `msg.*`, `macro.*` of the Java parity suite (maintainer-only probe).
enum MiscCoreParitySections {

    typealias Ctx = JavaCoreParityFixture.Ctx
    typealias Rows = JavaCoreParityFixture.Rows
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture

    static let names: [String] = ["run.EVT", "sked.PARSE", "sked.AT", "sked.LIST", "msg.LOG", "macro.LOAD"]

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        switch name {
        case "run.EVT": return try runMode(path, f, ctx)
        case "sked.PARSE": return try skedParse(path, f)
        case "sked.AT": return try skedAt(path, f)
        case "sked.LIST": return try skedList(path, f)
        case "msg.LOG": return try messageLog(path, f, ctx)
        case "macro.LOAD": return try macroLoad(path, f, ctx)
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    // MARK: - run

    /// Index into `allCases`; index `count` = Java `null`.
    static func element<T>(_ all: [T], _ field: String) throws -> T? {
        let index: Int = try X.int(field)
        guard index >= 0, index <= all.count else { throw X.Malformed(text: field) }
        return index == all.count ? nil : all[index]
    }

    static func runMode(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if path.hasPrefix("tol/") {
            let mode: Mode? = try element(Mode.allCases, f[0])
            return [(path, [String(RunModeTracker.toleranceHz(mode))])]
        }
        let script: String = path.split(separator: "/").prefix(2).joined(separator: "/")
        if script != ctx.trackerScript {
            ctx.trackerScript = script
            ctx.tracker = RunModeTracker()
        }
        let tracker: RunModeTracker = ctx.tracker
        switch f[0] {
        case "cq":
            return [(path, [tracker.onCq(try X.int(f[1])).rawValue])]
        case "toggle":
            let current: RunMode = try runMode(f[1])
            return [(path, [tracker.toggle(current, try X.int(f[2])).rawValue])]
        case "tuned":
            let freq: Int = try X.int(f[1])
            let mode: Mode? = try element(Mode.allCases, f[2])
            let current: RunMode = try runMode(f[3])
            let result: RunMode? = tracker.onTuned(freq, mode: mode, current: current, autoSwitch: X.bool(f[4]),
                                                   runOnCqFreq: X.bool(f[5]))
            return [(path, [result?.rawValue ?? "~"])]
        case "cqFreq":
            let band: Band? = try element(Band.allCases, f[1])
            return [(path, [tracker.cqFrequency(band).map { String($0) } ?? "~"])]
        default:
            throw X.Malformed(text: "unknown event \(f[0])")
        }
    }

    static func runMode(_ field: String) throws -> RunMode {
        guard let mode = RunMode(rawValue: field) else { throw X.Malformed(text: field) }
        return mode
    }

    // MARK: - sked

    /// `THROW <class>` as `MiscSections.result` (the message is not written).
    static func result(_ body: () throws(JavaDateTimeException) -> String) -> String {
        do {
            return try body()
        } catch {
            return "THROW DateTimeException"
        }
    }

    static func skedParse(_ path: String, _ f: [String]) throws -> Rows {
        let text: String? = X.text(f[0])
        let now: JavaInstant = try X.instant(f[1], f[2])
        let parsed: String = result { () throws(JavaDateTimeException) -> String in
            try SkedPlanner.parseTime(text, now: now)?.toString() ?? "~"
        }
        return [(path, [F.tx(parsed)])]
    }

    static func sked(_ call: String, _ at: String) -> SkedEntry {
        SkedEntry(call: call, freqHz: 14_025_000, mode: "CW", atUtc: at, note: "")
    }

    static func skedAt(_ path: String, _ f: [String]) throws -> Rows {
        let entry: SkedEntry = sked("X", X.text(f[0]) ?? "")
        let now: JavaInstant = try X.instant(f[1], f[2])
        let at: String = SkedPlanner.at(entry)?.toString() ?? "~"
        let due: String = result { () throws(JavaDateTimeException) -> String in
            X.b(try SkedPlanner.isDue(entry, now: now))
        }
        let past: String = result { () throws(JavaDateTimeException) -> String in
            X.b(try SkedPlanner.isPast(entry, now: now))
        }
        return [(path, [F.tx(at), due, past])]
    }

    static func skedList(_ path: String, _ f: [String]) throws -> Rows {
        let now: JavaInstant = try X.instant(f[0], f[1])
        var skeds: [SkedEntry] = []
        for (index, field) in f.dropFirst(2).enumerated() {
            skeds.append(sked("S\(index)", X.text(field) ?? ""))
        }
        let sorted: String = SkedPlanner.sorted(skeds).map(\.call).joined(separator: ",")
        let next: String = result { () throws(JavaDateTimeException) -> String in
            try SkedPlanner.next(skeds, now: now)?.call ?? "~"
        }
        return [(path, [sorted, next])]
    }

    // MARK: - msg

    static func messageLog(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if path.split(separator: "/").count == 2 {
            ctx.messages = MessageLog(maxEntries: try X.int(f[0]))
            return []
        }
        let log: MessageLog = ctx.messages
        if f[0] == "clear" {
            log.clear()
        } else {
            log.add(try X.instant(f[1], f[2]), X.text(f[3]))
        }
        let entries: [MessageLog.Entry] = log.entries
        var out: [String] = [String(entries.count)]
        for entry in entries {
            out += X.fields(entry.at)
            out.append(F.tx(entry.text))
        }
        out.append(F.tx(result { () throws(JavaDateTimeException) -> String in try log.asText() }))
        return [(path, out)]
    }

    // MARK: - macro

    static func macroLoad(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let directory: String = try ctx.temporaryDirectory()
        let file: String = "\(directory)/\(f[0]).txt"
        let present: Bool = X.bool(f[1])
        if present {
            try X.write(try X.bytes(hex: f[2]), to: file)
        }
        defer {
            if present { try? FileManager.default.removeItem(atPath: file) }
        }
        guard let lines = MacroScript.load(directory, X.text(f[3])) else {
            return [(path, ["~"])]
        }
        return [(path, [String(lines.count)] + lines.map { F.tx($0) })]
    }
}
