import Testing
@testable import MCLCore

/// Expression variables from the QSO context. The first two tests are a port of the Java
/// `QsoVariablesTest`; the rest is measured on Java
/// (maintainer-only probe, JDK 21.0.2).
@Suite struct QsoVariablesTests {

    // MARK: - port of the Java QsoVariablesTest (2)

    @Test func exposesContextAndReceivedFields() {
        let ctx = QsoContext(
            call: "DL1ABC", band: "20m", mode: "CW",
            received: JavaLinkedMap([("exch", .valid("28", "28")), ("rst", .valid("599", "599"))]),
            workedEntity: nil, ownEntity: nil, workedClass: "", ownGrid: nil, ownItuZone: "28")
        let v = QsoVariables.of(ctx)

        #expect(v["call"] == .text("DL1ABC"))
        #expect(v["band"] == .text("20m"))
        #expect(v["mode"] == .text("CW"))
        #expect(v["ownItuZone"] == .text("28"))
        // received fields by id
        #expect(v["exch"] == .text("28"))
        #expect(v["rst"] == .text("599"))
        // without DXCC entities → continents empty, ownDxcc/sameContinent = 0
        #expect(v["workedContinent"] == .text(""))
        #expect(v["ownContinent"] == .text(""))
        #expect(v["ownDxcc"] == .number(0.0))
        #expect(v["sameContinent"] == .number(0.0))
    }

    @Test func usableInExpression() throws {
        let ctx = QsoContext(
            call: "DA0HQ", band: "20m", mode: "CW",
            received: JavaLinkedMap([("exch", .valid("DARC", "DARC"))]),
            workedEntity: nil, ownEntity: nil, workedClass: "", ownGrid: nil, ownItuZone: "28")
        let v = QsoVariables.of(ctx)
        // HQ abbreviation → matches letter
        #expect(try Expression.eval("matches(exch, '[A-Za-z]')", v) == 1.0)
        // it is not my zone (DARC != 28)
        #expect(try Expression.eval("exch == ownItuZone", v) == 0.0)
    }

    // MARK: - measured on Java

    private static func entity(_ code: Int, _ continents: [String?]?) -> DxccEntity {
        DxccEntity(entityCode: code, name: "N\(code)", countryCode: "C\(code)", continents: continents,
                   cq: [], itu: [], lat: .nan, lon: .nan)
    }

    /// Probe context: a received field overwrites the context variable at its position (`band`,
    /// `ownDxcc`), a `null` value and an invalid field → `""`, a `null` id stays the key `null`,
    /// canonically equal ids (`K` / KELVIN SIGN, `Å` U+00C5 / ANGSTROM SIGN) are **two**
    /// variables as in a Java `LinkedHashMap`.
    private static func probeContext() -> QsoContext {
        let received = JavaLinkedMap<ExchangeValue>([
            ("exch", .valid("x", "X")),
            ("band", .valid("b", "40M")),
            ("nul", nil),
            ("inv", .invalid("q", "err")),
            (nil, .valid("n", "N")),
            ("K", .valid("1", "1")),
            ("\u{212A}", .valid("2", "2")),
            ("\u{00C5}", .valid("3", "3")),
            ("\u{212B}", .valid("4", "4")),
            ("ownDxcc", .valid("5", "PREPSANO")),
        ])
        return QsoContext(call: nil, band: "20m", mode: nil, received: received,
                          workedEntity: entity(1, [nil, "EU"]), ownEntity: entity(1, ["EU"]),
                          workedClass: "W", ownGrid: "JN79", ownItuZone: "28", ownQth: "PRG",
                          bonusStation: true)
    }

    @Test func entriesInJavaOrder() {
        // Java: call=S: band=S:40M mode=S: workedContinent=S: ownContinent=S:EU ownItuZone=S:28
        // ownDxcc=S:PREPSANO sameContinent=D:0.0 otherContinent=D:0.0 exch=S:X nul=S: inv=S:
        // null=S:N K=S:1 \u212A=S:2 \u00C5=S:3 \u212B=S:4
        let expected: [(String?, ExpressionValue)] = [
            ("call", .text("")), ("band", .text("40M")), ("mode", .text("")),
            ("workedContinent", .text("")), ("ownContinent", .text("EU")), ("ownItuZone", .text("28")),
            ("ownDxcc", .text("PREPSANO")), ("sameContinent", .number(0)), ("otherContinent", .number(0)),
            ("exch", .text("X")), ("nul", .text("")), ("inv", .text("")), (nil, .text("N")),
            ("K", .text("1")), ("\u{212A}", .text("2")), ("\u{00C5}", .text("3")), ("\u{212B}", .text("4")),
        ]
        let entries = QsoVariables.of(Self.probeContext()).entries
        #expect(entries.count == expected.count)
        for (actual, wanted) in zip(entries, expected) {
            #expect(actual.key.map { Array($0.utf16) } == wanted.0.map { Array($0.utf16) })
            #expect(actual.value == wanted.1)
        }
    }

    struct EvalRow: Sendable, CustomStringConvertible {
        let expression: String
        let java: Double
        var description: String { expression.unicodeScalars.map { $0.isASCII ? String($0) : "\\u{\(String($0.value, radix: 16))}" }.joined() }
    }

    static let evalRows: [EvalRow] = [
        EvalRow(expression: "call == ''", java: 1), EvalRow(expression: "band", java: 0),
        EvalRow(expression: "band == ''", java: 0), EvalRow(expression: "mode == ''", java: 1),
        EvalRow(expression: "exch == ''", java: 0), EvalRow(expression: "nul == ''", java: 1),
        EvalRow(expression: "inv == ''", java: 1),
        EvalRow(expression: "K", java: 1), EvalRow(expression: "\u{212A}", java: 2),
        EvalRow(expression: "\u{00C5}", java: 3), EvalRow(expression: "\u{212B}", java: 4),
        EvalRow(expression: "ownDxcc", java: 0), EvalRow(expression: "ownDxcc == ''", java: 0),
        EvalRow(expression: "sameContinent", java: 0), EvalRow(expression: "otherContinent", java: 0),
        EvalRow(expression: "workedContinent == ''", java: 1), EvalRow(expression: "ownContinent == ''", java: 0),
        EvalRow(expression: "ownItuZone", java: 28),
        // workedClass, ownGrid, ownQth, bonusStation are not among the variables → 0, not ""
        EvalRow(expression: "workedClass", java: 0), EvalRow(expression: "workedClass == ''", java: 0),
        EvalRow(expression: "ownGrid == ''", java: 0), EvalRow(expression: "ownQth == ''", java: 0),
        EvalRow(expression: "bonusStation", java: 0), EvalRow(expression: "bonusStation == ''", java: 0),
    ]

    @Test(arguments: evalRows)
    func evaluatesLikeJava(_ row: EvalRow) throws {
        #expect(try Expression.eval(row.expression, QsoVariables.of(Self.probeContext())) == row.java)
    }

    @Test func withoutReceivedOnlyContextVariables() {
        let ctx = QsoContext(call: "OK1XOE", band: nil, mode: "CW", received: nil,
                             workedEntity: nil, ownEntity: nil, workedClass: nil)
        #expect(QsoVariables.of(ctx).count == 9)
    }

    /// Variables are built once per QSO: `QsoContext.expressionVariables` is the same map
    /// as a fresh `QsoVariables.of` — keys by UTF-16 and order — on the first and every later read
    /// and in a copy of the context. Java builds it anew for every expression, but only from an immutable context
    /// and `Expression` only reads it, so a shared map is equivalent.
    @Test func cachedVariablesEqualFreshMapInOrder() {
        let ctx = Self.probeContext()
        let fresh = QsoVariables.of(ctx).entries
        let copy = ctx
        for cached in [ctx.expressionVariables.entries, ctx.expressionVariables.entries,
                       copy.expressionVariables.entries] {
            #expect(cached.count == fresh.count)
            for (actual, wanted) in zip(cached, fresh) {
                #expect(actual.key.map { Array($0.utf16) } == wanted.key.map { Array($0.utf16) })
                #expect(actual.value == wanted.value)
            }
        }
    }

    @Test func cachedVariablesAreSafeAcrossThreads() async {
        let ctx = Self.probeContext()
        let fresh = QsoVariables.of(ctx)
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<16 {
                group.addTask { ctx.expressionVariables == fresh }
            }
            var all: [Bool] = []
            for await ok in group { all.append(ok) }
            return all
        }
        #expect(results.allSatisfy { $0 })
    }
}
