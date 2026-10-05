import Testing
@testable import MCLCore

/// Swift side of the sections `scp.*` and `ch.*` of the Java parity suite (maintainer-only probe). Files
/// (`ScpDatabase.load`, `CallHistory.load`) are written to the item's temporary directory.
enum DataCoreParitySections {

    typealias Ctx = JavaCoreParityFixture.Ctx
    typealias Rows = JavaCoreParityFixture.Rows
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture
    typealias Field = ContestDefinition.ExchangeField

    static let names: [String] = [
        "scp.LOAD", "scp.FIND", "scp.MERGE", "scp.VAL", "ch.PARSE", "ch.LOAD", "ch.PRE", "ch.UPD",
    ]

    static func handles(_ name: String) -> Bool {
        name.hasPrefix("scp.") || name.hasPrefix("ch.")
    }

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        switch name {
        case "scp.LOAD": return try scpLoad(path, f, ctx)
        case "scp.FIND": return try scpFind(path, f, ctx)
        case "scp.MERGE": return try scpMerge(path, f)
        case "scp.VAL": return try scpValidate(path, f)
        case "ch.PARSE": return try chParse(path, f)
        case "ch.LOAD": return try chLoad(path, f, ctx)
        case "ch.PRE": return try chPrefill(path, f, ctx)
        case "ch.UPD": return try chUpdates(path, f)
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    // MARK: - scp

    static func items(_ db: ScpDatabase) -> [String] {
        var out: [String] = [String(db.size)]
        for i in 0..<db.size {
            out.append(F.tx(db.get(i)))
        }
        return out
    }

    static func scpLoad(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let file: String = try ctx.temporaryDirectory() + "/load.scp"
        try X.write(try X.bytes(hex: f[0]), to: file)
        return [(path, items(ScpDatabase.load(file)))]
    }

    static func scpFind(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if path.split(separator: "/").count == 2 {
            ctx.scp = ScpDatabase.of(f.map { X.text($0) ?? "" })
            return []
        }
        let query: String? = X.text(f[0])
        let limit: Int = try X.int(f[1])
        let found: [String] = ctx.scp.find(query, limit: limit)
        var out: [String] = [String(found.count)] + found.map { F.tx($0) }
        out.append(X.b(ctx.scp.contains(query)))
        out += ctx.scp.nPlusOne(query, limit: limit).map { F.tx($0) }
        return [(path, out)]
    }

    static func scpMerge(_ path: String, _ f: [String]) throws -> Rows {
        if path.hasPrefix("o/") {
            let a: String = X.text(f[0]) ?? ""
            let b: String = X.text(f[1]) ?? ""
            return [(path, [X.b(PartialCheck.isOneOff(a, b))])]
        }
        let typed: String? = X.text(f[0])
        let limit: Int = try X.int(f[1])
        if path.hasPrefix("m/") {
            let log = try X.list(f, from: 2)
            let spots = try X.list(f, from: log.next)
            let scp = try X.list(f, from: spots.next)
            let merged: [PartialCheck.Suggestion] = PartialCheck.merge(typed, logCalls: log.items,
                                                                       spotCalls: spots.items,
                                                                       scpMatches: scp.items, limit: limit)
            return [(path, merged.flatMap { [F.tx($0.call), $0.source.description] })]
        }
        let candidates = try X.list(f, from: 2)
        return [(path, PartialCheck.nPlusOne(typed, candidates: candidates.items, limit: limit).map { F.tx($0) })]
    }

    /// Content like `DataSections.scpBody`: `OK0..`, `BAD-0..` (rows `\n`) and extra bytes.
    static func scpValidate(_ path: String, _ f: [String]) throws -> Rows {
        let good: Int = try X.int(f[0])
        let bad: Int = try X.int(f[1])
        var content: [UInt8] = []
        for i in 0..<good {
            content += Array("OK\(i)\n".utf8)
        }
        for i in 0..<bad {
            content += Array("BAD-\(i)\n".utf8)
        }
        content += try X.bytes(hex: f[2])
        let result: String
        do {
            result = String(try ScpDownloader.validate(content))
        } catch {
            result = X.thrown("IOException", error.message)
        }
        return [(path, [F.tx(result)])]
    }

    // MARK: - ch

    /// `size`, column count, columns and records `callsign:{k=v, …}` in insertion order.
    static func dump(_ history: CallHistory) -> [String] {
        var out: [String] = [String(history.size), String(history.columns.count)]
        out += history.columns.map { F.tx($0) }
        for (key, record) in history.byCall.entries {
            let map: String = CallHistoryMeasuredTests.javaMap(record ?? JavaLinkedMap())
            out.append(F.tx("\(key ?? "null"):\(map)"))
        }
        return out
    }

    static func history(_ path: String, _ history: CallHistory, _ queries: [String?]) -> Rows {
        let found: [String] = queries.map { query in
            let record: String? = history.lookup(query).map(CallHistoryMeasuredTests.javaMap)
            return "\(F.tx(query))=\(F.tx(record))"
        }
        return [(path, dump(history)), (path + "/lk", found), (path + "/lines", history.toLines().map { F.tx($0) })]
    }

    static func chParse(_ path: String, _ f: [String]) throws -> Rows {
        let lines = try X.list(f, from: 0)
        let queries: [String?] = f[lines.next...].map { X.text($0) }
        return history(path, CallHistory.parse(lines.items), queries)
    }

    static func chLoad(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let file: String = try ctx.temporaryDirectory() + "/history.txt"
        try X.write(try X.bytes(hex: f[0]), to: file)
        let queries: [String?] = f.dropFirst().map { X.text($0) }
        return history(path, CallHistory.load(file), queries)
    }

    static func chPrefill(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if path.split(separator: "/").count == 2 {
            ctx.history = CallHistory.parse(f.map { X.text($0) ?? "" })
            return []
        }
        let call: String? = X.text(f[0])
        let limit: Int = try X.int(f[1])
        let count: Int = try X.int(f[2])
        var fields: [Field] = []
        for i in 0..<count {
            let typeText: String = f[4 + 2 * i]
            let type: ContestDefinition.FieldType? = typeText == "~" ? nil : ContestDefinition.FieldType(rawValue: typeText)
            fields.append(CallHistoryTestSupport.field(X.text(f[3 + 2 * i]), type))
        }
        let at: Int = 3 + 2 * count
        var exchange = JavaLinkedMap<String>()
        for i in 0..<(try X.int(f[at])) {
            exchange.put(X.text(f[at + 1 + 2 * i]), X.text(f[at + 2 + 2 * i]))
        }
        let hist: CallHistory = ctx.history
        let prefill: String = CallHistoryMeasuredTests.javaMap(hist.prefill(call, fields))
        let reverse: String = CallHistoryMeasuredTests.javaList(hist.reverse(exchange, fields, limit: limit))
        let columns: [String] = fields.map { F.tx(hist.columnFor($0)) }
        return [(path, [F.tx(prefill), F.tx(reverse)] + columns)]
    }

    static func chUpdates(_ path: String, _ f: [String]) throws -> Rows {
        let lines = try X.list(f, from: 0)
        var at: Int = lines.next
        let calls: Int = try X.int(f[at])
        at += 1
        var updates = JavaLinkedMap<JavaLinkedMap<String>>()
        for _ in 0..<calls {
            let call: String? = X.text(f[at])
            let count: Int = try X.int(f[at + 1])
            var values = JavaLinkedMap<String>()
            for i in 0..<count {
                values.put(X.text(f[at + 2 + 2 * i]), X.text(f[at + 3 + 2 * i]))
            }
            updates.put(call, values)
            at += 2 + 2 * count
        }
        let updated: CallHistory = CallHistory.parse(lines.items).withUpdates(updates)
        return [(path, dump(updated)), (path + "/lines", updated.toLines().map { F.tx($0) })]
    }
}
