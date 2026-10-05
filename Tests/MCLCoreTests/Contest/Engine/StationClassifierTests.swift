import Testing
@testable import MCLCore

/// `StationClassifier` — there is no Java test for it; the table `ConditionMeasured.classify`
/// is measured by the maintainer-only probe (JDK 21.0.2).
@Suite struct StationClassifierTests {
    typealias Condition = ContestDefinition.Condition
    typealias FieldEquals = ContestDefinition.FieldEquals
    typealias StationClass = ContestDefinition.StationClass

    private static func entity(_ code: Int, _ country: String, _ continent: String) -> DxccEntity {
        DxccEntity(entityCode: code, name: "N\(code)", countryCode: country, continents: [continent],
                   cq: [], itu: [], lat: .nan, lon: .nan)
    }

    /// The probe's worked/own pair.
    static let pairs: [String: (worked: DxccEntity?, own: DxccEntity?)] = {
        let ok = entity(1, "OK", "EU")
        let k = entity(2, "K", "NA")
        return ["OK/OK": (ok, ok), "K/OK": (k, ok), "null/OK": (nil, ok), "OK/null": (ok, nil)]
    }()

    /// The `stationClasses` of the probe definitions under the same descriptions.
    static let classes: [String: [StationClass?]?] = {
        var d: [String: [StationClass?]?] = [:]
        d["classes null"] = .some(nil)
        d["classes []"] = []
        d["W/VE dxccIn, DX fallback"] = [StationClass(id: "W", when: Condition(dxccIn: ["K", "VE"])),
                                         StationClass(id: "DX", when: nil)]
        d["first match has null id"] = [StationClass(id: nil, when: Condition()), StationClass(id: "X", when: nil)]
        d["null id not matching"] = [StationClass(id: nil, when: Condition(dxccIn: ["ZZ"])),
                                     StationClass(id: "X", when: nil)]
        d["mode never matches, bandIn[~] does"] = [StationClass(id: "A", when: Condition(mode: "CW")),
                                                   StationClass(id: "B", when: Condition(bandIn: [nil]))]
        d["bandIn[20m] never"] = [StationClass(id: "A", when: Condition(bandIn: ["20m"]))]
        d["fieldEquals field ~"] = [
            StationClass(id: "A", when: Condition(fieldEquals: FieldEquals(field: nil, value: "x"))),
            StationClass(id: "B", when: nil),
        ]
        d["fieldEquals exch"] = [
            StationClass(id: "A", when: Condition(fieldEquals: FieldEquals(field: "exch", value: "x"))),
            StationClass(id: "B", when: nil),
        ]
        d["null class element"] = [nil, StationClass(id: "X", when: nil)]
        d["sameContinent/otherContinent"] = [StationClass(id: "S", when: Condition(sameContinent: true)),
                                             StationClass(id: "O", when: Condition(otherContinent: true))]
        d["ownDxcc"] = [StationClass(id: "OWN", when: Condition(ownDxcc: true)),
                        StationClass(id: "DX", when: Condition())]
        d["expr call == ''"] = [StationClass(id: "E", when: Condition(expr: "call == '' && band == ''"))]
        d["expr foo"] = [StationClass(id: "E", when: Condition(expr: "foo(1)"))]
        d["workedClass ''"] = [StationClass(id: "A", when: Condition(workedClass: "")),
                               StationClass(id: "B", when: nil)]
        d["fieldPresent x"] = [StationClass(id: "A", when: Condition(fieldPresent: "x")),
                               StationClass(id: "B", when: nil)]
        d["bonusStation false"] = [StationClass(id: "A", when: Condition(bonusStation: false))]
        return d
    }()

    /// Where Java fails with an NPE, Swift is lenient (a deliberate divergence from Java v1.1.1):
    /// - `fieldEquals.field: ~` over the probe (`Map.of().get(null)`) → no match → next class;
    /// - `stationClasses: [~, …]` (`sc.when()`) → the element is skipped.
    static let lenient: [String: String?] = [
        "fieldEquals field ~": "B",
        "null class element": "X",
    ]

    @Test(arguments: ConditionMeasured.classify)
    func matchesJava(_ row: ConditionMeasured.Row) throws {
        let list = try #require(Self.classes[row.name], "missing definition \(row.name)")
        let pair = try #require(Self.pairs[row.context])
        let definition = ContestDefinition(schemaVersion: 1, id: "t", stationClasses: list)
        let result = Result { () throws(ExpressionError) in
            try StationClassifier.classify(definition, worked: pair.worked, own: pair.own)
        }
        switch row.java {
        case .id(let expected):
            #expect(try result.get() == expected)
        case .error(let kind, let message):
            #expect(throws: ExpressionError(kind: kind, message: message)) { try result.get() }
        case .npe:
            let expected = try #require(Self.lenient[row.name], "NPE without a lenient value")
            #expect(try result.get() == expected)
        case .bool:
            Issue.record("classification does not return a bool")
        }
    }

    @Test func everyDefinitionIsMeasured() {
        let measured = Set(ConditionMeasured.classify.map(\.name))
        #expect(measured == Set(Self.classes.keys))
        #expect(ConditionMeasured.classify.count == Self.classes.count * Self.pairs.count)
    }

    /// Java returns the id of the first matching class, even if it is `null`, and does not search further.
    @Test func firstMatchWithNilIdStopsSearch() throws {
        let definition = ContestDefinition(id: "t", stationClasses: [
            StationClass(id: nil, when: nil), StationClass(id: "X", when: nil),
        ])
        #expect(try StationClassifier.classify(definition, worked: nil, own: nil) == nil)
    }

    /// `stationClasses: [~]` — Java NPE, Swift skips the element (recorded leniency).
    @Test func nilClassElementIsSkipped() throws {
        let only = ContestDefinition(id: "t", stationClasses: [nil])
        #expect(try StationClassifier.classify(only, worked: nil, own: nil) == nil)
        let then = ContestDefinition(id: "t", stationClasses: [nil, StationClass(id: "X", when: nil)])
        #expect(try StationClassifier.classify(then, worked: nil, own: nil) == "X")
    }
}
