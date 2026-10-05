import Testing
@testable import MCLCore

/// Swift side of the sections `cmd.*`, `esm.*`, `key.*` of the Java parity suite (maintainer-only probe).
enum EntryCoreParitySections {

    typealias Ctx = JavaCoreParityFixture.Ctx
    typealias Rows = JavaCoreParityFixture.Rows
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture

    static let names: [String] = ["cmd.FUZZ", "esm.TABLE", "esm.PROG", "key.PARSE", "key.FMT", "key.ACT", "key.BIND"]

    static func handles(_ name: String) -> Bool {
        name.hasPrefix("cmd.") || name.hasPrefix("esm.") || name.hasPrefix("key.")
    }

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        switch name {
        case "cmd.FUZZ": return try command(path, f)
        case "esm.TABLE": return try esmTable(path, f)
        case "esm.PROG": return try esmProgress(path, f, ctx)
        case "key.PARSE": return [(path, [F.tx(describe(KeyCombo.parse(X.text(f[0]))))])]
        case "key.FMT": return try keyFormat(path, f)
        case "key.ACT": return try keyAction(path, f)
        case "key.BIND": return try keyBindings(path, f)
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    // MARK: - cmd

    /// `String.valueOf(CallFieldCommands.parse(…))` (or `THROW …`) and `String.valueOf(OperatorCommand.parse(…))`.
    static func command(_ path: String, _ f: [String]) throws -> Rows {
        let input: String? = X.text(f[0])
        let freq: Int64 = try X.int64(f[1])
        let other: Int64 = try X.int64(f[2])
        let ctrl: Bool = X.bool(f[3])
        let parsed: String = CommandMeasuredTests.javaString { () throws(JavaArithmeticError) -> CallFieldCommand? in
            try CallFieldCommands.parse(input, currentFreqHz: freq, otherVfoHz: other, ctrlEnter: ctrl)
        }
        let login: OperatorCommand? = OperatorCommand.parse(input)
        let op: String = login.map { "Optional[OperatorCommand[operator=\($0.operator)]]" } ?? "Optional.empty"
        return [(path, [F.tx(parsed), F.tx(op)])]
    }

    // MARK: - esm

    /// Java `State.toString()` (record, order of components).
    static func record(_ s: EsmEngine.State) -> String {
        let head = "State[run=\(s.run), callEmpty=\(s.callEmpty), dupe=\(s.dupe)"
        let middle = "exchangeValid=\(s.exchangeValid), exchangeSent=\(s.exchangeSent)"
        let tail = "myCallSent=\(s.myCallSent), callCorrected=\(s.callCorrected)]"
        return "\(head), \(middle), \(tail)"
    }

    static func record(_ o: EsmEngine.Options) -> String {
        "Options[spCallOnce=\(o.spCallOnce), workDupes=\(o.workDupes)]"
    }

    static func step(_ step: EsmEngine.Step) -> [String] {
        let keys: String = step.keys.map(String.init).joined(separator: ",")
        return [keys, X.b(step.log), step.focus.rawValue, X.b(step.isNothing)]
    }

    /// Full table via `State(index:)`/`Options(index:)`: Java `toString` of the state also verifies the bit mapping.
    static func esmTable(_ path: String, _ f: [String]) throws -> Rows {
        let state = EsmEngine.State(index: try X.int(f[0]))
        let options = EsmEngine.Options(index: try X.int(f[1]))
        let decided: [String] = step(EsmEngine.decide(state, options))
        return [(path, [record(state), record(options)] + decided)]
    }

    static func esmProgress(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let script: String = path.split(separator: "/").prefix(2).joined(separator: "/")
        if script != ctx.esmScript {
            ctx.esmScript = script
            ctx.esm = .empty
        }
        var extra: [String] = []
        switch f[0] {
        case "after":
            let keys: [Int] = try f[1].split(separator: ",").map { try X.int(String($0)) }
            ctx.esm = ctx.esm.afterSent(keys, X.text(f[2]))
        case "xsent":
            ctx.esm = ctx.esm.withExchangeSent()
        case "corrected":
            extra.append(X.b(ctx.esm.callCorrected(X.text(f[1]))))
        case "query":
            let state: EsmEngine.State = ctx.esm.state(run: X.bool(f[1]), call: X.text(f[2]), dupe: X.bool(f[3]),
                                                      exchangeValid: X.bool(f[4]))
            let options = EsmEngine.Options(index: try X.int(f[5]))
            extra.append(record(state))
            extra += step(EsmEngine.decide(state, options))
        default:
            throw X.Malformed(text: "unknown ESM step \(f[0])")
        }
        let progress: [String] = [X.b(ctx.esm.exchangeSent), X.b(ctx.esm.myCallSent), F.tx(ctx.esm.sentCall)]
        return [(path, progress + extra)]
    }

    // MARK: - key

    /// Java section output: `format code allowed`, or `empty`.
    static func describe(_ combo: KeyCombo?) -> String {
        guard let combo else { return "empty" }
        return "\(combo.format()) \(combo.keyCode) \(X.b(combo.isAllowedShortcut))"
    }

    static func keyFormat(_ path: String, _ f: [String]) throws -> Rows {
        let mask: Int = try X.int(f[0])
        let code: Int32 = try X.int32(f[1])
        let combo = KeyCombo(ctrl: mask & 1 != 0, alt: mask & 2 != 0, shift: mask & 4 != 0, meta: mask & 8 != 0,
                             keyCode: code)
        return [(path, [F.tx(combo.format()), X.b(KeyCombo.isModifierKey(code)), X.b(combo.isAllowedShortcut)])]
    }

    static func keyAction(_ path: String, _ f: [String]) throws -> Rows {
        if path.hasPrefix("id/") {
            return [(path, [ShortcutAction.byId(X.text(f[0]))?.name ?? "~"])]
        }
        let all: [ShortcutAction] = ShortcutAction.allCases
        let index: Int = try X.int(f[0])
        guard index >= 0, index < all.count else { throw X.Malformed(text: f[0]) }
        let a: ShortcutAction = all[index]
        let combo: String = a.defaultCombo().format()
        return [(path, [a.name, F.tx(a.id), F.tx(a.label), F.tx(a.defaultKeys), F.tx(combo)])]
    }

    static func keyBindings(_ path: String, _ f: [String]) throws -> Rows {
        let all: [ShortcutAction] = ShortcutAction.allCases
        if f[0] == "~" {
            let none = KeyBindings(nil)
            return [(path + "/combo", all.map { none.comboFor($0)?.format() ?? "~" })]
        }
        let count: Int = try X.int(f[0])
        guard f.count == 1 + 2 * count else { throw X.Malformed(text: path) }
        var overrides: [String: String] = [:]
        var values: [String] = []
        for i in 0..<count {
            let id: String = X.text(f[1 + 2 * i]) ?? ""
            let value: String = X.text(f[2 + 2 * i]) ?? ""
            overrides[id] = value
            values.append(value)
        }
        let bindings = KeyBindings(overrides)
        var combos: [String] = []
        var conflicts: [String] = []
        for action in all {
            combos.append(bindings.comboFor(action)?.format() ?? "~")
            let others: [ShortcutAction] = bindings.conflicts(action)
            if !others.isEmpty {
                conflicts.append("\(action.name):\(others.map(\.name).joined(separator: "/"))")
            }
        }
        var probes: [KeyCombo] = all.map { $0.defaultCombo() }
        probes += values.compactMap { KeyCombo.parse($0) }
        let resolved: [String] = probes.map { combo in
            "\(F.tx(combo.format()))=\(bindings.resolve(combo)?.name ?? "~")"
        }
        return [(path + "/combo", combos), (path + "/conf", conflicts), (path + "/res", resolved)]
    }
}
