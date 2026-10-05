import Foundation
import Testing
@testable import MCLCore

/// Parity suite against Java for contest definitions and multiplier sets: one
/// regression net with three arms, each comparing the Swift result with a reference
/// produced by the **Java** application v1.1.1 (maintainer-only probe,
/// procedure in a maintainer-only probe). The references are committed — the tests
/// need no JDK and cannot silently degrade to "Swift against Swift".
///
/// - **Read arm** (`contest-data-definitions.json`): each of the 22 definitions
///   `contest-data/contests/` and two synthetic "full" definitions
///   `definition-synthetic/` (every field filled, all enum values) as a whole record (all fields, `null` explicitly)
///   and the whole set registry over `contest-data/multipliers/` with `dxcc-test.json`
///   (order of `ids`, set class, `id`, `enumerable`, all values with attributes).
/// - **Error arm** (`definition-errors-java.json` over the corpus
///   `Fixtures/definition-errors/`): whether and where (line, column) `readTree` rejects
///   the file and whether and where the loader rejects it. The message text is not compared.
/// - **Write arm** (`definition-write-java.json` for the inputs
///   `definition-write-cases.json`): `DefinitionEditing.template/withId`,
///   `CountyListImport.qsoPartyTemplate` and the file bytes of `CountyListImport.write`.
///
/// The reference format is the same as in `JavaYamlParityTests` (and is composed by the same
/// functions): an item = the `sha256` of the input + node lines. The checksum tells a
/// **stale reference** ("REGENERATE REFERENCE") from a **defect** ("MISMATCH").
///
/// It absorbs the earlier separate comparisons `bundledDefinitionsMatchJava`
/// (Java `toString` of 22 definitions, a probe outside the repo) and `bundledRegistryMatchesJava`
/// (the first 8 values of a set) — both were a subset of the read arm and their
/// reference had no committed generator.
@Suite struct JavaDefinitionParityTests {

    // MARK: - Canonical tree

    /// A node of the canonical dump — an image of the Java value that `DefRefGen`
    /// prints by reflection (record, list, map, scalars).
    indirect enum Node {
        case null
        case str(String)
        case int(Int)
        case bool(Bool)
        case double(Double)
        case enumCase(String)
        case record([(String, Node)])
        case list([Node])
        case map([(String, Node)])
    }

    static func line(_ path: String, _ fields: String...) -> String {
        "[" + ([path] + fields).map(JavaYamlParityTests.jsonString).joined(separator: ",") + "]"
    }

    static func pointer(_ key: String) -> String {
        key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }

    static func emit(_ node: Node, path: String, into lines: inout [String]) {
        switch node {
        case .null: lines.append(line(path, "null"))
        case .str(let text): lines.append(line(path, "str", text))
        case .int(let value): lines.append(line(path, "int", String(value)))
        case .bool(let value): lines.append(line(path, "bool", value ? "true" : "false"))
        case .double(let value): lines.append(line(path, "double", JavaDouble.toString(value)))
        case .enumCase(let name): lines.append(line(path, "enum", name))
        case .list(let items):
            lines.append(line(path, "list"))
            for (index, item) in items.enumerated() {
                emit(item, path: path + "/[\(index)]", into: &lines)
            }
        case .record(let fields), .map(let fields):
            if case .record = node { lines.append(line(path, "record")) } else { lines.append(line(path, "map")) }
            for (key, value) in fields {
                emit(value, path: path + "/" + pointer(key), into: &lines)
            }
        }
    }

    static func lines(of node: Node) -> [String] {
        var out: [String] = []
        emit(node, path: "", into: &out)
        return out
    }

    // MARK: - ContestDefinition → nodes
    //
    // Fields in the Java order of record components. The list of fields is determined by Java
    // (reflection in `DefRefGen`): a field that is missing here shows up in the gate as
    // `swift=<node missing>`.

    static func opt<T>(_ value: T?, _ convert: (T) -> Node) -> Node {
        guard let value else { return .null }
        return convert(value)
    }

    static func str(_ value: String?) -> Node { opt(value) { .str($0) } }
    static func int(_ value: Int?) -> Node { opt(value) { .int($0) } }
    static func bool(_ value: Bool?) -> Node { opt(value) { .bool($0) } }
    static func enumName<E: RawRepresentable>(_ value: E?) -> Node where E.RawValue == String {
        opt(value) { .enumCase($0.rawValue) }
    }
    static func list<T>(_ value: [T?]?, _ convert: (T) -> Node) -> Node {
        opt(value) { items in .list(items.map { opt($0, convert) }) }
    }
    static func strings(_ value: [String?]?) -> Node { list(value) { .str($0) } }
    static func orderedMap<T>(_ value: YamlOrderedMap<T>?, _ convert: (T) -> Node) -> Node {
        opt(value) { map in .map(map.pairs.map { ($0.key, opt($0.value, convert)) }) }
    }

    typealias Def = ContestDefinition

    static func node(_ d: Def) -> Node {
        .record([
            ("schemaVersion", .int(d.schemaVersion)),
            ("id", str(d.id)),
            ("metadata", opt(d.metadata, node)),
            ("period", opt(d.period, node)),
            ("bands", strings(d.bands)),
            ("modes", strings(d.modes)),
            ("categories", list(d.categories, node)),
            ("stationClasses", list(d.stationClasses, node)),
            ("exchange", opt(d.exchange, node)),
            ("scoring", opt(d.scoring, node)),
            ("multipliers", list(d.multipliers, node)),
            ("dupe", opt(d.dupe, node)),
            ("cabrillo", opt(d.cabrillo, node)),
            ("ui", opt(d.ui, node)),
            ("operating", opt(d.operating, node)),
        ])
    }

    static func node(_ o: Def.Operating) -> Node {
        .record([("offTime", opt(o.offTime, node)), ("bandChange", opt(o.bandChange, node)),
                 ("rules", list(o.rules, node))])
    }
    static func node(_ r: Def.OperatingRule) -> Node {
        .record([("when", orderedMap(r.when) { .str($0) }), ("offTime", opt(r.offTime, node)),
                 ("bandChange", opt(r.bandChange, node))])
    }
    static func node(_ o: Def.OffTime) -> Node {
        .record([("minimumMinutes", int(o.minimumMinutes)), ("requiredMinutes", int(o.requiredMinutes))])
    }
    static func node(_ b: Def.BandChange) -> Node {
        .record([("minimumMinutes", int(b.minimumMinutes)), ("perHour", int(b.perHour))])
    }
    static func node(_ m: Def.Metadata) -> Node {
        .record([("name", str(m.name)), ("organizer", str(m.organizer)),
                 ("description", str(m.description)), ("officialUrl", str(m.officialUrl))])
    }
    static func node(_ p: Def.Period) -> Node {
        .record([("durationHours", int(p.durationHours)), ("sessions", opt(p.sessions, node))])
    }
    static func node(_ s: Def.Sessions) -> Node {
        .record([("start", str(s.start)), ("minutes", int(s.minutes))])
    }
    static func node(_ c: Def.Category) -> Node {
        .record([("id", str(c.id)), ("label", str(c.label))])
    }
    static func node(_ s: Def.StationClass) -> Node {
        .record([("id", str(s.id)), ("when", opt(s.when, node))])
    }
    static func node(_ e: Def.Exchange) -> Node {
        .record([("sent", list(e.sent, node)), ("received", list(e.received, node))])
    }
    static func node(_ f: Def.ExchangeField) -> Node {
        .record([("id", str(f.id)), ("type", enumName(f.type)), ("required", .bool(f.required)),
                 ("source", enumName(f.source)), ("appliesWhen", opt(f.appliesWhen, node)),
                 ("validation", opt(f.validation, node)), ("estimate", str(f.estimate))])
    }
    static func node(_ a: Def.AppliesWhen) -> Node {
        .record([("workedClass", str(a.workedClass))])
    }
    static func node(_ v: Def.FieldValidation) -> Node {
        .record([("regex", str(v.regex)), ("min", int(v.min)), ("max", int(v.max)), ("length", int(v.length))])
    }
    static func node(_ c: Def.Condition) -> Node {
        .record([
            ("allOf", list(c.allOf, node)),
            ("anyOf", list(c.anyOf, node)),
            ("not", opt(c.not, node)),
            ("ownDxcc", bool(c.ownDxcc)),
            ("sameDxcc", bool(c.sameDxcc)),
            ("sameContinent", bool(c.sameContinent)),
            ("otherContinent", bool(c.otherContinent)),
            ("continentIs", str(c.continentIs)),
            ("ownContinentIs", str(c.ownContinentIs)),
            ("workedClass", str(c.workedClass)),
            ("dxccIn", strings(c.dxccIn)),
            ("bandIn", strings(c.bandIn)),
            ("mode", str(c.mode)),
            ("fieldEquals", opt(c.fieldEquals, node)),
            ("fieldPresent", str(c.fieldPresent)),
            ("expr", str(c.expr)),
            ("bonusStation", bool(c.bonusStation)),
        ])
    }
    static func node(_ f: Def.FieldEquals) -> Node {
        .record([("field", str(f.field)), ("value", str(f.value))])
    }
    static func node(_ s: Def.Scoring) -> Node {
        .record([("qsoPoints", opt(s.qsoPoints, node)), ("bonuses", list(s.bonuses, node)),
                 ("total", str(s.total)), ("qtc", opt(s.qtc, node))])
    }
    static func node(_ q: Def.Qtc) -> Node {
        .record([("points", int(q.points)), ("maxPerStation", int(q.maxPerStation)),
                 ("groupSize", int(q.groupSize))])
    }
    static func node(_ q: Def.QsoPoints) -> Node {
        // The Java component is named `defaultValue` (YAML key `default`).
        .record([("mode", enumName(q.mode)), ("defaultValue", .int(q.defaultValue)),
                 ("rules", list(q.rules, node))])
    }
    static func node(_ r: Def.PointRule) -> Node {
        .record([("when", opt(r.when, node)), ("value", opt(r.value, node))])
    }
    static func node(_ v: Def.PointValue) -> Node {
        .record([("fixed", int(v.fixed)), ("expr", str(v.expr)), ("perKm", opt(v.perKm, node))])
    }
    static func node(_ p: Def.PerKm) -> Node {
        .record([("field", str(p.field)), ("factor", .double(p.factor)), ("round", str(p.round)),
                 ("min", int(p.min)), ("max", int(p.max))])
    }
    static func node(_ b: Def.Bonus) -> Node {
        .record([("id", str(b.id)), ("when", opt(b.when, node)), ("value", opt(b.value, node)),
                 ("scope", enumName(b.scope))])
    }
    static func node(_ m: Def.MultiplierBinding) -> Node {
        .record([("id", str(m.id)), ("set", str(m.set)), ("from", str(m.from)), ("scope", enumName(m.scope)),
                 ("label", str(m.label)), ("appliesWhen", opt(m.appliesWhen, node)),
                 ("bandWeights", orderedMap(m.bandWeights) { .int($0) })])
    }
    static func node(_ d: Def.Dupe) -> Node {
        .record([("scope", enumName(d.scope)), ("dupeWorthZero", bool(d.dupeWorthZero))])
    }
    static func node(_ c: Def.Cabrillo) -> Node {
        .record([("contestName", str(c.contestName)), ("sentOrder", strings(c.sentOrder)),
                 ("receivedOrder", strings(c.receivedOrder))])
    }
    static func node(_ u: Def.Ui) -> Node {
        .record([("entryOrder", strings(u.entryOrder)), ("logColumns", strings(u.logColumns))])
    }

    // MARK: - Registry → nodes

    /// Java `String.compareTo` = UTF-16 unit order (not Swift `<`).
    static func utf16Less(_ a: String, _ b: String) -> Bool {
        a.utf16.lexicographicallyPrecedes(b.utf16)
    }

    static func node(_ registry: MultiplierSetRegistry) throws -> Node {
        var sets: [(String, Node)] = []
        for id in registry.ids {
            let set = try registry.get(id)
            let values: [Node] = set.values.map { value in
                .record([
                    ("key", str(value.key)),
                    ("label", str(value.label)),
                    // Java `TreeMap` — sorted by UTF-16 units.
                    ("attributes", .map(value.attributes.sorted { utf16Less($0.key, $1.key) }
                        .map { ($0.key, .str($0.value)) })),
                ])
            }
            sets.append((id ?? "null", .record([
                ("class", .str(String(describing: type(of: set)))),
                ("id", str(set.id)),
                ("enumerable", .bool(set.enumerable)),
                ("values", .list(values)),
            ])))
        }
        return .map(sets)
    }

    // MARK: - References and comparison

    typealias Entry = JavaYamlParityTests.ReferenceFile

    static func reference(_ name: String) throws -> [Entry] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"),
                               Comment(rawValue: "no reference \(name).json in the bundle"))
        return try JavaYamlParityTests.parseReference(String(contentsOf: url, encoding: .utf8))
    }

    static func referenceText(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Differences between the reference and the Swift result. First it decides **whose
    /// defect it is**: if the item set or the input checksum disagrees,
    /// the reference is stale and node differences are not printed (they would point to
    /// code that is fine). Otherwise nodes are paired **by path**
    /// (`file: path: java=… swift=…`), not by line index.
    static func differences(reference: [Entry], mine: [Entry], arm: String) -> String? {
        let referenceNames = reference.map(\.relative)
        let mineNames = mine.map(\.relative)
        if referenceNames != mineNames {
            let extraMine = mineNames.filter { !referenceNames.contains($0) }
            let extraReference = referenceNames.filter { !mineNames.contains($0) }
            return "REGENERATE REFERENCE (\(arm)) — the item set diverged; extra in inputs: "
                + extraMine.joined(separator: ", ") + " | extra in reference: "
                + extraReference.joined(separator: ", ") + regenerate
        }
        let stale = zip(reference, mine).filter { $0.sha256 != $1.sha256 }.map(\.0.relative)
        if !stale.isEmpty {
            return "REGENERATE REFERENCE (\(arm)) — the code did not diverge, the input bytes did. "
                + "Checksum mismatch at: " + stale.joined(separator: ", ") + regenerate
        }
        var report: [String] = []
        for (java, swift) in zip(reference, mine) where report.count < 25 {
            guard java.lines != swift.lines else { continue }
            let javaByPath = Dictionary(java.lines.map { (JavaYamlParityTests.pathOf($0), JavaYamlParityTests.valueOf($0)) },
                                        uniquingKeysWith: { first, _ in first })
            let swiftByPath = Dictionary(swift.lines.map { (JavaYamlParityTests.pathOf($0), JavaYamlParityTests.valueOf($0)) },
                                         uniquingKeysWith: { first, _ in first })
            var seen = Set<String>()
            let before = report.count
            for path in (swift.lines + java.lines).map(JavaYamlParityTests.pathOf) where report.count < 25 {
                guard seen.insert(path).inserted else { continue }
                let javaText = javaByPath[path] ?? "<node missing>"
                let swiftText = swiftByPath[path] ?? "<node missing>"
                guard javaText != swiftText else { continue }
                report.append("\(java.relative): \(JavaYamlParityTests.display(path)): java=\(javaText) swift=\(swiftText)")
            }
            if report.count == before {
                report.append("\(java.relative): nodes match, their order differs")
            }
        }
        guard !report.isEmpty else { return nil }
        return "MISMATCH (\(arm)) — input checksums match, but the result diverged from Java:\n"
            + report.joined(separator: "\n")
    }

    // MARK: - Read arm

    static func readArm() throws -> [Entry] {
        let root = try ContestDataLayoutTests.contestDataRoot()
        let contests = root.appendingPathComponent("contests")
        var out: [Entry] = []
        for name in try sortedNames(in: contests, suffix: ".yaml") {
            let url = contests.appendingPathComponent(name)
            let data = try Data(contentsOf: url)
            let definition = try ContestDefinitionLoader.loadFile(url)
            out.append(Entry(relative: "contests/" + name, sha256: JavaYamlParityTests.sha256Hex(data),
                             lines: lines(of: node(definition))))
        }
        let synthetic = try #require(Bundle.module.url(forResource: "definition-synthetic", withExtension: nil),
                                     "directory definition-synthetic is not in the bundle — .copy rule in Package.swift")
        for name in try sortedNames(in: synthetic, suffix: ".yaml") {
            let url = synthetic.appendingPathComponent(name)
            let data = try Data(contentsOf: url)
            let definition = try ContestDefinitionLoader.loadFile(url)
            out.append(Entry(relative: "synthetic/" + name, sha256: JavaYamlParityTests.sha256Hex(data),
                             lines: lines(of: node(definition))))
        }
        let multipliers = root.appendingPathComponent("multipliers")
        let dxccData = try DxccTestFixture.data()
        let registry = try MultiplierSetRegistry(dxcc: DxccResolver.fromData(dxccData)).loadDir(multipliers)
        out.append(Entry(relative: "registry",
                         sha256: try registryDigest(multipliers: multipliers, dxcc: dxccData),
                         lines: lines(of: try node(registry))))
        return out
    }

    /// Checksum of the registry inputs by the same rule as `DefRefGen.registryDigest`.
    static func registryDigest(multipliers: URL, dxcc: Data) throws -> String {
        var text = ""
        // Only what the registry reads (`.yaml` and `.csv`) — `.DS_Store` would give a false "REGENERATE".
        let read = try sortedNames(in: multipliers, suffix: "").filter { $0.hasSuffix(".yaml") || $0.hasSuffix(".csv") }
        for name in read {
            let data = try Data(contentsOf: multipliers.appendingPathComponent(name))
            text += "multipliers/\(name)\t\(JavaYamlParityTests.sha256Hex(data))\n"
        }
        text += "dxcc-test.json\t\(JavaYamlParityTests.sha256Hex(dxcc))\n"
        return JavaYamlParityTests.sha256Hex(Data(text.utf8))
    }

    /// Names of regular files with an extension, sorted by UTF-16 units like
    /// Java `Comparator.comparing(getFileName().toString())`.
    static func sortedNames(in directory: URL, suffix: String) throws -> [String] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        return try urls.filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(suffix) }
            .sorted(by: utf16Less)
    }

    @Test func readArmMatchesJava() throws {
        try JavaV111Gate.run {
            let reference = try Self.reference("contest-data-definitions")
            let mine = try Self.readArm()
            if let report = Self.differences(reference: reference, mine: mine, arm: "read arm") {
                Issue.record(Comment(rawValue: report))
                return
            }
            // The nodes match — now the document composition byte by byte (separators, order).
            #expect(JavaYamlParityTests.canonicalDocument(mine) == (try Self.referenceText("contest-data-definitions")))
        }
    }

    // MARK: - Error arm

    /// The Swift side's result for one corpus file, in reference lines:
    /// `tree` (YAML reader) and `load` (definition / set loader).
    static func errorLines(data: Data, isContest: Bool) -> [String] {
        func located(_ error: YamlError) -> String {
            line("load", "ERR", String(error.line), String(error.column))
        }
        var out: [String] = []
        // Text like the loaders: Foundation drops a leading BOM, the corpus has no bad UTF-8.
        let text = String(data: data, encoding: .utf8) ?? ""
        do {
            _ = try YamlParser.parse(text)
            out.append(line("tree", "OK"))
        } catch let error as YamlError {
            out.append(line("tree", "ERR", String(error.line), String(error.column)))
        } catch {
            out.append(line("tree", "EXC", "\(error)"))
        }
        if isContest {
            do {
                _ = try ContestDefinitionLoader.load(data)
                out.append(line("load", "OK"))
            } catch {
                switch error {
                case .invalidDefinition(let cause): out.append(located(cause))
                case .emptyDefinition: out.append(line("load", "EMPTY"))
                case .newerSchema: out.append(line("load", "NEWER"))
                case .failure(let message): out.append(line("load", "FAIL", message))
                }
            }
        } else {
            do {
                _ = try MultiplierSetLoader.load(data)
                out.append(line("load", "OK"))
            } catch {
                switch error {
                case .invalidDefinition(let cause): out.append(located(cause))
                case .emptyDefinition: out.append(line("load", "EMPTY"))
                default: out.append(line("load", "FAIL", error.message))
                }
            }
        }
        return out
    }

    static let knownMarker = line("known", "typová před syntaktickou")

    static func errorArm() throws -> [Entry] {
        let root = try #require(Bundle.module.url(forResource: "definition-errors", withExtension: nil),
                                "directory definition-errors is not in the bundle — .copy rule in Package.swift")
        var out: [Entry] = []
        for kind in ["contests", "multipliers"] {
            let directory = root.appendingPathComponent(kind)
            for name in try sortedNames(in: directory, suffix: ".yaml") {
                let data = try Data(contentsOf: directory.appendingPathComponent(name))
                out.append(Entry(relative: kind + "/" + name, sha256: JavaYamlParityTests.sha256Hex(data),
                                 lines: errorLines(data: data, isContest: kind == "contests")))
            }
        }
        return out
    }

    /// The reference adjusted to what Swift should give: for the recorded divergence "Type
    /// error before syntax error" (Java maps in a streaming fashion and shows the earlier type
    /// error, Swift builds the tree first) the loader is expected to give the position of Java's
    /// `readTree` and the `known` marker is dropped. Other items unchanged.
    static func expectedErrors(_ reference: [Entry]) -> [Entry] {
        reference.map { entry in
            guard entry.lines.contains(knownMarker), let tree = entry.lines.first,
                  tree.hasPrefix(line("tree", "ERR").dropLast()) else { return entry }
            let expectedLoad = "[\"load\"" + tree.dropFirst("[\"tree\"".count)
            let lines = entry.lines.filter { $0 != knownMarker }
                .map { $0.hasPrefix("[\"load\",") ? expectedLoad : $0 }
            return Entry(relative: entry.relative, sha256: entry.sha256, lines: lines)
        }
    }

    @Test func errorArmMatchesJava() throws {
        try JavaV111Gate.run {
            let reference = Self.expectedErrors(try Self.reference("definition-errors-java"))
            if let report = Self.differences(reference: reference, mine: try Self.errorArm(), arm: "error arm") {
                Issue.record(Comment(rawValue: report))
            }
        }
    }

    /// Files with the recorded divergence "Type error before syntax error" are tracked
    /// separately, not as failures: here it pins **which** they are and what Java
    /// shows, so the class does not grow unnoticed (a new file in the corpus
    /// with this marker turns this test red until it is entered here).
    @Test func typeErrorBeforeSyntaxErrorIsTrackedSeparately() throws {
        let marked = try Self.reference("definition-errors-java").filter { $0.lines.contains(Self.knownMarker) }
        #expect(marked.map(\.relative) == ["contests/type-before-syntax.yaml"])
        #expect(marked.first?.lines == [
            Self.line("tree", "ERR", "3", "18"),
            Self.line("load", "ERR", "1", "16"),   // Java: type error `schemaVersion: x`
            Self.knownMarker,
        ])
    }

    /// The corpus covers what it should: failure and acceptance, both paths (tree and loader)
    /// and both kinds of definitions — otherwise the gate could pass only because it
    /// measures nothing.
    @Test func errorCorpusIsNontrivial() throws {
        let reference = try Self.reference("definition-errors-java")
        let loads = reference.compactMap { $0.lines.first { $0.hasPrefix("[\"load\",") } }
        let trees = reference.compactMap(\.lines.first)
        #expect(reference.count >= 30)
        #expect(trees.filter { $0.hasPrefix("[\"tree\",\"ERR\"") }.count >= 6)
        #expect(loads.filter { $0.hasPrefix("[\"load\",\"ERR\"") }.count >= 20)
        #expect(loads.filter { $0 == Self.line("load", "OK") }.count >= 3)
        #expect(loads.contains(Self.line("load", "EMPTY")))
        #expect(loads.contains(Self.line("load", "NEWER")))
        #expect(reference.contains { $0.relative.hasPrefix("multipliers/") && $0.lines.last?.contains("ERR") == true })
    }

    // MARK: - Write arm

    static func writeCases() throws -> [(op: String, args: [String])] {
        let url = try #require(Bundle.module.url(forResource: "definition-write-cases", withExtension: "json"))
        let raw = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        return try raw.map { item in
            (try #require(item["op"] as? String), try #require(item["args"] as? [String]))
        }
    }

    static func writeArm() throws -> [Entry] {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("JavaDefinitionParityTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: work) }
        var out: [Entry] = []
        for (index, testCase) in try writeCases().enumerated() {
            let args = testCase.args
            var lines: [String] = []
            switch testCase.op {
            case "template":
                lines.append(line("out", "str", DefinitionEditing.template(args[0], args[1])))
            case "withId":
                lines.append(line("out", "str", DefinitionEditing.withId(args[0], args[1])))
            case "qsoPartyTemplate":
                lines.append(line("out", "str", CountyListImport.qsoPartyTemplate(args[0], args[1], args[2])))
            case "write":
                let directory = work.appendingPathComponent("case\(index)").appendingPathComponent("multipliers")
                let values = stride(from: 2, to: args.count - 1, by: 2).map { (code: args[$0], label: args[$0 + 1]) }
                do {
                    let count = try CountyListImport.write(directory, setId: args[0], name: args[1], values: values)
                    lines.append(line("count", "int", String(count)))
                    for name in try sortedNames(in: directory, suffix: "") {
                        let data = try Data(contentsOf: directory.appendingPathComponent(name))
                        let text = try #require(String(data: data, encoding: .utf8),
                                                Comment(rawValue: "\(name): not UTF-8"))
                        lines.append(line("file/" + pointer(name), "str", text))
                    }
                } catch let error as CountyListImportError {
                    lines.append(line("error", "str", error.message))
                }
            default:
                Issue.record(Comment(rawValue: "unknown operation \(testCase.op)"))
            }
            let input = ([testCase.op] + args).map(JavaYamlParityTests.jsonString).joined(separator: ",")
            let label = String(repeating: "0", count: max(0, 3 - String(index).count)) + String(index)
            out.append(Entry(relative: label + " " + testCase.op,
                             sha256: JavaYamlParityTests.sha256Hex(Data(input.utf8)), lines: lines))
        }
        return out
    }

    @Test func writeArmMatchesJava() throws {
        try JavaV111Gate.run {
            let reference = try Self.reference("definition-write-java")
            let mine = try Self.writeArm()
            if let report = Self.differences(reference: reference, mine: mine, arm: "write arm") {
                Issue.record(Comment(rawValue: report))
                return
            }
            #expect(JavaYamlParityTests.canonicalDocument(mine) == (try Self.referenceText("definition-write-java")))
        }
    }

    // MARK: - The gate does not pass by accident

    /// The read arm compares non-trivial content and contains exactly the values
    /// on which the injected regressions of step 3 stand (band weights, `default`).
    @Test func readReferenceCarriesChecksums() throws {
        let reference = try Self.reference("contest-data-definitions")
        let all = reference.flatMap(\.lines)
        #expect(reference.count == 25, Comment(rawValue: "items \(reference.count)"))
        #expect(all.count > 5000, Comment(rawValue: "only \(all.count) nodes"))
        #expect(all.contains(Self.line("/multipliers/[0]/bandWeights/80m", "int", "4")))
        #expect(all.contains(Self.line("/scoring/qsoPoints/defaultValue", "int", "1")))
        #expect(all.filter { $0.hasSuffix(",\"null\"]") }.count > 1000)
    }

    /// The synthetic definitions fill **every** field of every record at least once
    /// and use **all** enum values — otherwise a decoder that does not read a field
    /// would leave the read arm green (measured: the `contest-data` corpus leaves 11 fields
    /// always `null`). Fields are taken from the Java
    /// reference (reflection), not from a hand-written list.
    @Test func syntheticDefinitionsFillEveryFieldAndEveryEnum() throws {
        let reference = try Self.reference("contest-data-definitions")
        let synthetic = reference.filter { $0.relative.hasPrefix("synthetic/") }
        #expect(synthetic.count == 2)
        // Field = the last component of the node path; list items (`/[i]`) and map
        // keys (`bandWeights`, `OperatingRule.when`) are not fields.
        var all = Set<String>(), filled = Set<String>()
        for entry in synthetic {
            let maps = Set(entry.lines.filter { $0.hasSuffix(",\"map\"]") }.map(JavaYamlParityTests.pathOf))
            for line in entry.lines {
                let path = JavaYamlParityTests.pathOf(line)
                guard let slash = path.lastIndex(of: "/") else { continue }
                let name = String(path[path.index(after: slash)...])
                guard !name.hasPrefix("["), !maps.contains(String(path[..<slash])) else { continue }
                all.insert(name)
                if !line.hasSuffix(",\"null\"]") { filled.insert(name) }
            }
        }
        #expect(all.subtracting(filled).isEmpty, Comment(rawValue: "always null: \(all.subtracting(filled).sorted())"))
        let enums = Set(synthetic.flatMap(\.lines).filter { $0.contains(",\"enum\",") }.map(JavaYamlParityTests.valueOf))
        let expected = ContestDefinition.FieldType.allCases.map(\.rawValue)
            + ContestDefinition.FieldSource.allCases.map(\.rawValue)
            + ContestDefinition.Scope.allCases.map(\.rawValue)
            + ContestDefinition.PointsMode.allCases.map(\.rawValue)
        for name in expected {
            #expect(enums.contains("\"enum\",\"\(name)\""), Comment(rawValue: "enum \(name) is missing from the synthetic data"))
        }
    }
}
