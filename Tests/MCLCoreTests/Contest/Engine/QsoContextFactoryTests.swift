import Foundation
import os
import Testing
@testable import MCLCore

/// `QsoContextFactory` — there is no Java test for it; the scenarios `ExchangeMeasured.factory` are measured
/// by the maintainer-only probe (JDK 21.0.2) under the same descriptions.
@Suite struct QsoContextFactoryTests {

    /// A fake `DxccLookup` as in the probe: a fixed table, it records `resolve` calls.
    /// `DxccLookup` is `Sendable`, hence the call log is behind a lock.
    final class FakeDxcc: DxccLookup {
        private let recorded = OSAllocatedUnfairLock<[String?]>(initialState: [])
        var calls: [String?] { recorded.withLock { $0 } }
        let table: [String: DxccEntity]

        init() {
            func entity(_ code: Int, _ country: String, _ itu: [Int?]?) -> DxccEntity {
                DxccEntity(entityCode: code, name: "N\(code)", countryCode: country,
                           continents: [country == "K" ? "NA" : "EU"], cq: [], itu: itu, lat: .nan, lon: .nan)
            }
            table = ["OK1AA": entity(503, "OK", [28]), "OK2AA": entity(503, "OK", [28]), "W1AW": entity(291, "K", [8]),
                     "NI1A": entity(1, "NI", [nil, 3]), "EI1A": entity(2, "EI", []), "NU1A": entity(3, "NU", nil)]
        }

        func resolve(_ callsign: String?) -> DxccEntity? {
            recorded.withLock { $0.append(callsign) }
            guard let callsign else { return nil }
            return table[callsign]
        }

        func entities() -> [DxccEntity] { Array(table.values) }
    }

    static let def = "{stationClasses: [{id: wve, when: {dxccIn: [K]}}, {id: dx}], exchange: {received: ["
        + "{id: rst, type: RST}, {id: state, type: STATE, appliesWhen: {workedClass: wve}}, "
        + "{id: zone, type: CQ_ZONE, appliesWhen: {workedClass: dx}, validation: {min: 1, max: 40}}, "
        + "{id: nr, type: SERIAL}]}}"
    static let dup = "{exchange: {received: [{id: x, type: TEXT}, {id: y, type: TEXT}, {id: x, type: SERIAL}]}}"
    static let nullId = "{exchange: {received: [{type: TEXT}, {id: a, type: TEXT}]}}"
    static let utf16 = "{exchange: {received: [{id: \"\u{C5}\", type: TEXT}, {id: \"\u{212A}\", type: TEXT}]}}"
    static let nullElement = "{exchange: {received: [~, {id: a, type: TEXT}]}}"
    static let exprError = "{stationClasses: [{id: a, when: {expr: 'foo(1)'}}], exchange: {received: [{id: a, type: TEXT}]}}"
    static let classNull = "{stationClasses: [{when: {}}, {id: dx}], exchange: {received: ["
        + "{id: a, type: TEXT}, {id: b, type: TEXT, appliesWhen: {workedClass: dx}}, "
        + "{id: c, type: TEXT, appliesWhen: {}}]}}"

    private static func raw(_ pairs: (String?, String?)...) -> JavaLinkedMap<String> {
        JavaLinkedMap(pairs)
    }

    private static let dx = raw(("rst", "599"), ("zone", "07"), ("nr", "001"))

    private static func esc(_ text: String?) -> String { ExchangeMeasuredTests.esc(text) }

    private static func calls(_ dxcc: FakeDxcc) -> String {
        dxcc.calls.map { esc($0) }.joined(separator: ";")
    }

    private static func describe(_ c: QsoContext, _ dxcc: FakeDxcc) -> String {
        var text = "class=" + esc(c.workedClass) + "|ownItu=" + esc(c.ownItuZone) + "|ownQth=" + esc(c.ownQth)
        text += "|grid=" + esc(c.ownGrid) + "|bonus=\(c.bonusStation)"
        text += "|worked=" + (c.workedEntity.map { "\($0.entityCode)" } ?? "~")
        text += "|own=" + (c.ownEntity.map { "\($0.entityCode)" } ?? "~")
        text += "|received=" + (c.received.map { ExchangeMeasuredTests.map($0, ExchangeMeasuredTests.value) } ?? "~")
        return text + "|resolves=" + calls(dxcc)
    }

    private static func text(_ error: QsoContextError) -> String {
        switch error {
        case .exchange(let error): return ExchangeMeasuredTests.exception(error)
        case .expression(let error): return "EXC IllegalArgumentException: " + esc(error.message)
        }
    }

    private static func build(_ yaml: String, _ myCall: String?, _ myGrid: String?, _ myItu: String?,
                              _ call: String?, _ received: JavaLinkedMap<String>?, _ ownQth: String?) throws -> String {
        let dxcc = FakeDxcc()
        let factory = QsoContextFactory(definition: try ExchangeMeasuredTests.definition(yaml), dxcc: dxcc,
                                        exchange: ExchangeEngine(), myCall: myCall, myGrid: myGrid, myItuZone: myItu)
        do {
            return describe(try factory.build(call: call, band: "20m", mode: "CW", receivedRaw: received,
                                              ownQth: ownQth), dxcc)
        } catch {
            return text(error)
        }
    }

    /// Probe scenarios under the same descriptions.
    static let scenarios: [String: @Sendable () throws -> String] = {
        var s: [String: @Sendable () throws -> String] = [:]
        s["itu-config-trimmed"] = { try build(def, "OK1AA", nil, " 5 ", "OK2AA", dx, nil) }
        s["itu-config-nbsp"] = { try build(def, "OK1AA", nil, "\u{A0}5", "OK2AA", dx, nil) }
        s["itu-config-text"] = { try build(def, "OK1AA", nil, "abc", "OK2AA", dx, nil) }
        s["itu-fallback-entity"] = { try build(def, "OK1AA", nil, nil, "OK2AA", dx, nil) }
        s["itu-blank-fallback"] = { try build(def, "OK1AA", nil, "   ", "OK2AA", dx, nil) }
        s["itu-em-space-no-fallback"] = { try build(def, "OK1AA", nil, "\u{2003}", "OK2AA", dx, nil) }
        s["itu-null-first"] = { try build(def, "NI1A", nil, nil, "OK2AA", dx, nil) }
        s["itu-empty-list"] = { try build(def, "EI1A", nil, nil, "OK2AA", dx, nil) }
        s["itu-null-list"] = { try build(def, "NU1A", nil, nil, "OK2AA", dx, nil) }
        s["itu-no-call"] = { try build(def, nil, nil, nil, "OK2AA", dx, nil) }
        s["itu-unknown-call"] = { try build(def, "XX1XX", nil, nil, "OK2AA", dx, nil) }
        s["grid-not-normalized"] = { try build(def, "OK1AA", " jn89 ", nil, "OK2AA", dx, nil) }
        s["build-dx"] = { try build(def, "OK1AA", "JN89", nil, "OK2AA", dx, nil) }
        s["build-wve"] = { try build(def, "OK1AA", nil, nil, "W1AW", raw(("rst", "59"), ("state", " ca ")), nil) }
        s["build-unknown-call"] = { try build(def, "OK1AA", nil, nil, "ZZ9ZZ", dx, nil) }
        s["build-raw-null"] = { try build(def, "OK1AA", nil, nil, "OK2AA", nil, nil) }
        s["build-raw-empty"] = { try build(def, "OK1AA", nil, nil, "OK2AA", raw(), nil) }
        s["build-raw-present-null"] = { try build(def, "OK1AA", nil, nil, "OK2AA", raw(("rst", nil)), nil) }
        s["build-raw-extra-keys"] = {
            try build(def, "OK1AA", nil, nil, "OK2AA", raw(("state", "CA"), ("rst", "579"), ("x", "y")), nil)
        }
        s["build-call-null"] = { try build(def, "OK1AA", nil, nil, nil, dx, nil) }
        s["build-serial-overflow"] = {
            try build(def, "OK1AA", nil, nil, "OK2AA", raw(("rst", "599"), ("zone", "14"), ("nr", "2147483648")), nil)
        }
        s["build-zone-overflow"] = {
            try build(def, "OK1AA", nil, nil, "OK2AA", raw(("rst", "599"), ("zone", "99999999999"), ("nr", "1")), nil)
        }
        s["build-serial-max"] = {
            try build(def, "OK1AA", nil, nil, "OK2AA", raw(("rst", "599"), ("zone", "14"), ("nr", "002147483647")), nil)
        }
        s["ownqth-null"] = { try build(def, "OK1AA", nil, nil, "OK2AA", dx, nil) }
        s["ownqth-empty"] = { try build(def, "OK1AA", nil, nil, "OK2AA", dx, "") }
        s["ownqth-blank"] = { try build(def, "OK1AA", nil, nil, "OK2AA", dx, " \t ") }
        s["ownqth-em-space"] = { try build(def, "OK1AA", nil, nil, "OK2AA", dx, "\u{2003}") }
        s["ownqth-trim-upper"] = { try build(def, "OK1AA", nil, nil, "OK2AA", dx, " ok-1 ") }
        s["ownqth-nbsp"] = { try build(def, "OK1AA", nil, nil, "OK2AA", dx, "\u{A0}x") }
        s["ownqth-sharp-s"] = { try build(def, "OK1AA", nil, nil, "OK2AA", dx, "straße") }
        s["ownqth-control"] = { try build(def, "OK1AA", nil, nil, "OK2AA", dx, "\u{1}ab\u{1}") }
        s["duplicate-id"] = { try build(dup, "OK1AA", nil, nil, "OK2AA", raw(("x", "05"), ("y", "b")), nil) }
        s["null-id-field"] = { try build(nullId, "OK1AA", nil, nil, "OK2AA", raw((nil, "x"), ("a", "y")), nil) }
        s["null-id-field-map-of"] = { try build(nullId, "OK1AA", nil, nil, "", raw(), nil) }
        s["utf16-keys"] = { try build(utf16, "OK1AA", nil, nil, "OK2AA", raw(("A\u{30A}", "a"), ("K", "k")), nil) }
        s["utf16-keys-exact"] = {
            try build(utf16, "OK1AA", nil, nil, "OK2AA", raw(("\u{C5}", "a"), ("\u{212A}", "k")), nil)
        }
        s["received-null-element"] = { try build(nullElement, "OK1AA", nil, nil, "OK2AA", raw(("a", "q")), nil) }
        s["no-exchange"] = { try build("{}", "OK1AA", nil, nil, "OK2AA", dx, nil) }
        s["class-expr-error"] = { try build(exprError, "OK1AA", nil, nil, "OK2AA", dx, nil) }
        s["class-null-id"] = {
            try build(classNull, "OK1AA", nil, nil, "OK2AA", raw(("a", "1"), ("b", "2"), ("c", "3")), nil)
        }
        s["bonus"] = {
            let factory = QsoContextFactory(definition: try ExchangeMeasuredTests.definition(def), dxcc: FakeDxcc(),
                                            exchange: ExchangeEngine(), myCall: "OK1AA")
            func bonus(_ call: String?) throws(QsoContextError) -> Bool {
                let context = try factory.build(call: call, band: "20m", mode: "CW", receivedRaw: nil)
                return context.bonusStation
            }
            var text = "default=\(try bonus("W1AW"))"
            factory.setBonusPredicate { $0 == "W1AW" }
            text += ";set=\(try bonus("W1AW"));other=\(try bonus("OK2AA"))"
            factory.setBonusPredicate { _ in true }
            text += ";nullCall=\(try bonus(nil))"
            factory.setBonusPredicate(nil)
            return text + ";reset=\(try bonus("W1AW"))"
        }
        s["worked-class"] = {
            let dxcc = FakeDxcc()
            let factory = QsoContextFactory(definition: try ExchangeMeasuredTests.definition(def), dxcc: dxcc,
                                            exchange: ExchangeEngine(), myCall: "OK1AA")
            return "W1AW=" + esc(try factory.workedClass("W1AW")) + ";OK2AA=" + esc(try factory.workedClass("OK2AA"))
                + ";null=" + esc(try factory.workedClass(nil)) + "|resolves=" + calls(dxcc)
        }
        s["worked-class-expr-error"] = {
            let factory = QsoContextFactory(definition: try ExchangeMeasuredTests.definition(exprError),
                                            dxcc: FakeDxcc(), exchange: ExchangeEngine(), myCall: "OK1AA")
            do throws(ExpressionError) {
                return esc(try factory.workedClass("W1AW"))
            } catch {
                return "EXC IllegalArgumentException: " + esc(error.message)
            }
        }
        return s
    }()

    /// Where Java fails with an NPE (a deliberate divergence from Java v1.1.1): a `nil` element of `exchange.received` is skipped;
    /// a field without `id` over an empty map (the shape of `ContestSession.multiplierGrid`, `Map.of()`) gives `""`.
    static let lenient: [String: String] = [
        "received-null-element": "class=~|ownItu=28|ownQth=~|grid=~|bonus=false|worked=503|own=503"
            + "|received=a=true,q,Q,~|resolves=OK1AA;OK2AA",
        "null-id-field-map-of": "class=~|ownItu=28|ownQth=~|grid=~|bonus=false|worked=~|own=503"
            + "|received=~=false,,~,pr\\u00E1zdn\\u00E9;a=false,,~,pr\\u00E1zdn\\u00E9|resolves=OK1AA;",
    ]

    @Test(arguments: ExchangeMeasured.factory.map(\.0))
    func matchesJava(_ label: String) throws {
        let java = try #require(ExchangeMeasured.factory.first { $0.0 == label }?.1)
        let scenario = try #require(Self.scenarios[label], "scenario \(label) is missing from the test")
        let expected: String
        switch java {
        case .text(let text): expected = text
        case .npe: expected = try #require(Self.lenient[label], "NPE scenario without a pinned value")
        }
        #expect(try scenario() == expected)
    }

    @Test func everyScenarioIsMeasured() {
        #expect(Set(Self.scenarios.keys) == Set(ExchangeMeasured.factory.map(\.0)))
        #expect(Set(Self.lenient.keys) == Set(ExchangeMeasured.factory.filter { $0.1 == .npe }.map(\.0)))
    }

    // MARK: - type properties (Java without measurement)

    /// The Java factory is one shared instance that `ContestSession` changes via a setter; all
    /// holders of the reference then see the new predicate. Swift: a `final class`, not a copied struct.
    @Test func bonusPredicateIsSharedByAllHolders() throws {
        let factory = QsoContextFactory(definition: try ExchangeMeasuredTests.definition(Self.def), dxcc: FakeDxcc(),
                                        exchange: ExchangeEngine(), myCall: "OK1AA")
        let heldElsewhere = factory
        factory.setBonusPredicate { _ in true }
        #expect(try heldElsewhere.build(call: "W1AW", band: nil, mode: nil, receivedRaw: nil).bonusStation)
    }

    /// A bonus predicate behind a lock must not be "wrapped" on read: a function stored directly as the state
    /// of a generic `OSAllocatedUnfairLock` was re-abstracted through `inout` on every `withLock`
    /// and written back two thunks deeper — after ~10,000 QSOs the replay crashed on a stack overflow
    /// (measured by a replay benchmark). Hence so many `build` calls in a row.
    @Test func bonusPredicateDoesNotGrowWithEveryBuild() throws {
        let factory = QsoContextFactory(definition: try ExchangeMeasuredTests.definition("{}"), dxcc: FakeDxcc(),
                                        exchange: ExchangeEngine(), myCall: nil)
        factory.setBonusPredicate { $0 == "W1AW" }
        for _ in 0..<30_000 {
            _ = try factory.build(call: "OK2AA", band: nil, mode: nil, receivedRaw: nil)
        }
        #expect(try factory.build(call: "W1AW", band: nil, mode: nil, receivedRaw: nil).bonusStation)
    }

    /// A `nil` callsign goes into `dxcc.resolve(nil)` as in Java (both resolvers return "nothing") and the bonus
    /// predicate is not called for it.
    @Test func nilCallGoesThroughResolveAndSkipsBonus() throws {
        let dxcc = FakeDxcc()
        let factory = QsoContextFactory(definition: try ExchangeMeasuredTests.definition(Self.def), dxcc: dxcc,
                                        exchange: ExchangeEngine(), myCall: nil)
        let asked = NSLockedBox<[String]>([])
        factory.setBonusPredicate { c in asked.mutate { $0.append(c) }; return true }
        let context = try factory.build(call: nil, band: nil, mode: nil, receivedRaw: nil)
        #expect(context.workedEntity == nil)
        #expect(!context.bonusStation)
        #expect(asked.value.isEmpty)
        #expect(dxcc.calls == [nil])   // myCall nil is not resolved at all
    }

    /// `ownItuZone` is never `nil` — without configuration and entity it is `""`.
    @Test func ownItuZoneIsNeverNil() throws {
        let factory = QsoContextFactory(definition: try ExchangeMeasuredTests.definition("{}"), dxcc: FakeDxcc(),
                                        exchange: ExchangeEngine(), myCall: nil)
        #expect(try factory.build(call: nil, band: nil, mode: nil, receivedRaw: nil).ownItuZone == "")
    }
}

/// A lock-protected box for capturing in `@Sendable` predicates.
private final class NSLockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ body: (inout T) -> Void) { lock.lock(); defer { lock.unlock() }; body(&stored) }
}
