import Foundation
import Testing
@testable import MCLCore

/// Parity suite against Java for the engine and contest exchange: the final regression net over
/// the unit tables. Three arms, each comparing the Swift result with a reference
/// produced by the **Java** application v1.1.1 (maintainer-only probe,
/// procedure in a maintainer-only probe). The references are committed — the tests need no
/// JDK and cannot silently degrade to "Swift against Swift".
///
/// - **Score** (`engine-score-java.json`): for each of the 22 definitions of `contest-data/contests/`,
///   both synthetic `definition-synthetic/` ones and `engine-gate-synthetic/overflow.yaml` (int/long overflow,
///   for the gate only) a deterministically generated stream of 150 steps
///   (write, preview, TOUR session change). After each step the counterpart class, the parsed
///   received exchange, crediting, dupe, points, the state of every multiplier binding and the running score.
/// - **Exchange** (`engine-exchange-java.json`): `ExchangeEngine.activeReceivedFields/parse/
///   parseLine/sentDefaults`, `ExchangeGrab.route` and `SpotExchangeEstimator.estimate`
///   over generated inputs for each definition.
/// - **Expressions** (`engine-expressions-java.json`): 3,000 generated expressions (the language grammar
///   and mutations into error shapes) → result bits, or the kind and verbatim text of the exception.
///
/// **The score stream mirrors `ContestSession.log`** (`ContestSession.java:271-293`), which is only
/// here: `factory.build` → without a band / in a mode the contest does not have, it is not credited →
/// `dupe.isDupe` → points (0 for a dupe unless `dupeWorthZero: false`) → `evaluator.commit` →
/// `dupe.add` → `qsoPoints += points`, `qsoCount += 1`; the score is
/// `ScoreEngine.compute(def, qsoPoints, 0, 0, qsoCount, tracker)`. It **omits** the awarding of
/// bonuses (`awardBonuses`) and QTC — that is covered by the session suite. The preview is `ContestSession.preview` with the step time.
///
/// Inputs are in the reference as `in` lines (Java generates them, Swift only executes them); the `out`
/// lines are the results. An item's checksum covers the definition bytes, the registry inputs
/// (`multipliers/`, `dxcc-engine-gate.json`) and the `in` lines — if they disagree, the gate reports
/// **"REGENERATE REFERENCE"** and does not compare results; if they match and the result does not, it is a **"MISMATCH"**.
///
/// Recorded divergence: `synthetic/full-b.yaml` has a `nil` points rule and a `nil` binding —
/// Java fails on them with a `NullPointerException`, Swift skips them (a deliberate divergence from Java v1.1.1).
/// From the first Java NPE in an item on, nothing is compared (the states diverge); which items
/// which ones is pinned by `javaNpeOnlyInFullDefinitionB`.
@Suite struct JavaEngineParityTests {

    typealias Entry = JavaYamlParityTests.ReferenceFile

    // MARK: - Line texts

    /// Java `EngineRefGen.esc`: printable ASCII except `\ , ; = ~ | " : { } [ ]` stays,
    /// everything else by UTF-16 units as `\uXXXX`; `nil` → `~`.
    static func esc(_ text: String?) -> String {
        guard let text else { return "~" }
        var out = ""
        for unit in text.utf16 {
            if unit <= 0x20 || unit > 0x7E || "\\,;=~|\":{}[]".utf16.contains(unit) {
                let hex = String(unit, radix: 16, uppercase: true)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            } else {
                out.unicodeScalars.append(Unicode.Scalar(UInt8(unit)))
            }
        }
        return out
    }

    /// The inverse of `esc`: `~` → `nil`, `\uXXXX` → a UTF-16 unit.
    static func unesc(_ text: String) -> String? {
        if text == "~" { return nil }
        var units: [UInt16] = []
        let source = Array(text.utf16)
        var index = 0
        while index < source.count {
            if source[index] == 0x5C, index + 5 < source.count, source[index + 1] == 0x75,
               let unit = UInt16(String(decoding: source[(index + 2)..<(index + 6)], as: UTF16.self), radix: 16) {
                units.append(unit)
                index += 6
            } else {
                units.append(source[index])
                index += 1
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// The fields of one reference line (`["path","in",…]`). Texts are after `esc`, so there is
    /// no quote inside and the only JSON escape is a doubled backslash.
    static func fields(_ line: String) -> [String] {
        let body = line.dropFirst(2).dropLast(2)
        return body.components(separatedBy: "\",\"").map { $0.replacingOccurrences(of: "\\\\", with: "\\") }
    }

    static func line(_ path: String, _ fields: String...) -> String {
        "[" + ([path] + fields).map(JavaYamlParityTests.jsonString).joined(separator: ",") + "]"
    }

    /// A map from the input: `~` → `nil`, otherwise `{k=v;…}` in write order.
    static func map(_ spec: String) -> JavaLinkedMap<String>? {
        guard spec != "~" else { return nil }
        var out = JavaLinkedMap<String>()
        let body = String(spec.dropFirst().dropLast())
        guard !body.isEmpty else { return out }
        for pair in body.components(separatedBy: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            out.put(unesc(String(parts[0])), unesc(String(parts[1])))
        }
        return out
    }

    static func strings(_ map: JavaLinkedMap<String>?) -> String {
        guard let map else { return "~" }
        return "{" + map.entries.map { esc($0.key) + "=" + esc($0.value) }.joined(separator: ";") + "}"
    }

    static func value(_ value: ExchangeValue?) -> String {
        guard let value else { return "~" }
        let parts = [value.valid ? "ok" : "bad", esc(value.raw), esc(value.canonical), esc(value.error)]
        return parts.joined(separator: ":")
    }

    static func values(_ map: JavaLinkedMap<ExchangeValue>?) -> String {
        guard let map else { return "~" }
        return "{" + map.entries.map { esc($0.key) + "=" + value($0.value) }.joined(separator: ";") + "}"
    }

    static func results(_ results: [MultiplierEvalResult]) -> String {
        results.map { r in
            [esc(r.bindingId), esc(r.setId), esc(r.key), esc(r.scopeKey), r.state.rawValue,
             String(r.countsAsMultiplier), String(r.isNew)].joined(separator: ",")
        }.joined(separator: ";")
    }

    static func ids(_ fields: [ContestDefinition.ExchangeField]) -> String {
        "[" + fields.map { esc($0.id) }.joined(separator: ";") + "]"
    }

    /// Java `EXC ExceptionClass: message` from a Swift error (the Java class the error replaces).
    static func exc(_ error: any Error) -> String {
        let (name, message): (String, String)
        switch error {
        case let error as QsoContextError:
            switch error {
            case .expression(let inner): return exc(inner)
            case .exchange(let inner): return exc(inner)
            }
        case let error as ContestSessionError:
            switch error {
            case .expression(let inner): return exc(inner)
            case .exchange(let inner): return exc(inner)
            case .multiplier(let inner): return exc(inner)
            }
        case let error as ExpressionError:
            (name, message) = (javaName(error.kind), error.message)
        case let error as ExchangeError:
            (name, message) = (error.kind == .numberFormat ? "NumberFormatException" : "PatternSyntaxException",
                               error.message)
        case let error as MultiplierError:
            (name, message) = ("MultiplierException", error.description)
        default:
            (name, message) = ("Swift." + String(describing: type(of: error)), "\(error)")
        }
        return "EXC " + name + ": " + esc(message)
    }

    static func javaName(_ kind: ExpressionError.Kind) -> String {
        switch kind {
        case .illegalArgument: "IllegalArgumentException"
        case .numberFormat: "NumberFormatException"
        case .patternSyntax: "PatternSyntaxException"
        case .unsupportedPattern: "Swift.unsupportedPattern"
        case .nestingTooDeep: "Swift.nestingTooDeep"
        }
    }

    static func kindName(_ kind: ExpressionError.Kind) -> String {
        switch kind {
        case .illegalArgument: "illegalArgument"
        case .numberFormat: "numberFormat"
        case .patternSyntax: "patternSyntax"
        case .unsupportedPattern: "swift.unsupportedPattern"
        case .nestingTooDeep: "swift.nestingTooDeep"
        }
    }

    // MARK: - References and checksums

    static func reference(_ name: String) throws -> [Entry] {
        try JavaYamlParityTests.parseReference(referenceText(name))
    }

    static func referenceText(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"),
                               Comment(rawValue: "no reference \(name).json in the bundle — .process rule in Package.swift"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func isInput(_ line: String) -> Bool {
        line.contains("\",\"in\"")
    }

    /// By the same rule as `EngineRefGen.entry`.
    static func checksum(definition: Data?, registry: String, lines: [String]) -> String {
        let inputs = lines.filter(isInput).map { $0 + "\n" }.joined()
        var text = ""
        if let definition {
            text += "definition\t" + JavaYamlParityTests.sha256Hex(definition) + "\n"
            text += "registry\t" + registry + "\n"
        }
        text += "inputs\t" + JavaYamlParityTests.sha256Hex(Data(inputs.utf8)) + "\n"
        return JavaYamlParityTests.sha256Hex(Data(text.utf8))
    }

    /// Parity definitions in reference order: `contests/*.yaml`, `synthetic/*.yaml`, then `gate/*.yaml`
    /// (`engine-gate-synthetic/` — int and long overflow, for this suite only).
    static func definitionFiles() throws -> [(name: String, url: URL)] {
        let contests = try ContestDataLayoutTests.contestDataRoot().appendingPathComponent("contests")
        let synthetic = try #require(Bundle.module.url(forResource: "definition-synthetic", withExtension: nil))
        var out: [(name: String, url: URL)] = []
        for name in try JavaDefinitionParityTests.sortedNames(in: contests, suffix: ".yaml") {
            out.append(("contests/" + name, contests.appendingPathComponent(name)))
        }
        for name in try JavaDefinitionParityTests.sortedNames(in: synthetic, suffix: ".yaml") {
            out.append(("synthetic/" + name, synthetic.appendingPathComponent(name)))
        }
        let gate = try #require(Bundle.module.url(forResource: "engine-gate-synthetic", withExtension: nil),
                                "directory engine-gate-synthetic is not in the bundle — .copy rule in Package.swift")
        for name in try JavaDefinitionParityTests.sortedNames(in: gate, suffix: ".yaml") {
            out.append(("gate/" + name, gate.appendingPathComponent(name)))
        }
        return out
    }

    struct Environment {
        let dxcc: DxccResolver
        let registry: MultiplierSetRegistry
        let registryDigest: String
    }

    /// DXCC fixture for this gate only (`dxcc-engine-gate.json`): the entities of `dxcc-test.json` + PL, RU ×2,
    /// G, JA, 5B, S5, 9A, KH6 with real prefixes, zones and continents — so that the stream's callsigns are not
    /// mostly "unknown" (`sp-dx`, `rdxc`). The definitions suite still reads `dxcc-test.json`.
    static let dxccFixture = "dxcc-engine-gate.json"

    static func environment() throws -> Environment {
        let url = try #require(Bundle.module.url(forResource: "dxcc-engine-gate", withExtension: "json"),
                               "dxcc-engine-gate.json is not in the bundle — .process rule in Package.swift")
        let dxccData = try Data(contentsOf: url)
        let dxcc = try DxccResolver.fromData(dxccData)
        let multipliers = try ContestDataLayoutTests.contestDataRoot().appendingPathComponent("multipliers")
        return Environment(dxcc: dxcc,
                           registry: try MultiplierSetRegistry(dxcc: dxcc).loadDir(multipliers),
                           registryDigest: try registryDigest(multipliers: multipliers, dxcc: dxccData))
    }

    /// By the same rule as `EngineRefGen.registryDigest` (= `DefRefGen`, only the DXCC file name differs).
    static func registryDigest(multipliers: URL, dxcc: Data) throws -> String {
        var text = ""
        let read = try JavaDefinitionParityTests.sortedNames(in: multipliers, suffix: "")
            .filter { $0.hasSuffix(".yaml") || $0.hasSuffix(".csv") }
        for name in read {
            let data = try Data(contentsOf: multipliers.appendingPathComponent(name))
            text += "multipliers/\(name)\t\(JavaYamlParityTests.sha256Hex(data))\n"
        }
        text += "\(dxccFixture)\t\(JavaYamlParityTests.sha256Hex(dxcc))\n"
        return JavaYamlParityTests.sha256Hex(Data(text.utf8))
    }

    /// Runs the arm over the definitions: for each reference item (only when the item set matches)
    /// it executes its `in` lines and returns the Swift items with their own checksum.
    static func runOverDefinitions(_ reference: [Entry], files: [(name: String, url: URL)]? = nil,
                                   _ run: (ContestDefinition, [String], Environment) throws -> [String]) throws -> [Entry] {
        let environment = try environment()
        let byName = Dictionary(reference.map { ($0.relative, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [Entry] = []
        for file in try files ?? definitionFiles() {
            let data = try Data(contentsOf: file.url)
            let inputs = byName[file.name]?.lines.filter(isInput) ?? []
            let lines = try run(try ContestDefinitionLoader.loadFile(file.url), inputs, environment)
            out.append(Entry(relative: file.name,
                             sha256: checksum(definition: data, registry: environment.registryDigest, lines: inputs),
                             lines: lines))
        }
        return out
    }

    // MARK: - Comparison

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// The step number of a path (`/007/points` → 7); `/setup` and other non-numeric → `nil`.
    static func stepNumber(_ path: String) -> Int? {
        Int(step(path).dropFirst())
    }

    /// The step a line belongs to (`/007/points` → `/007`).
    static func step(_ path: String) -> String {
        let parts = path.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
        return parts.count > 1 ? "/" + parts[1] : path
    }

    static let javaNpe = "EXC NullPointerException"

    /// Recorded divergence: Java fails on a `nil` definition element, Swift skips it and continues —
    /// from the step of the first Java NPE the item is no longer compared (the states diverged).
    static func truncatedAtJavaNpe(_ java: Entry, _ swift: Entry) -> (Entry, Entry) {
        guard let first = java.lines.first(where: { $0.contains(javaNpe) }) else { return (java, swift) }
        let cut = stepNumber(JavaYamlParityTests.pathOf(first)) ?? 0
        func keep(_ line: String) -> Bool {
            // Numerically, not as text: the width of the step number is only a generator convention.
            guard let current = stepNumber(JavaYamlParityTests.pathOf(line)) else { return true }
            return current < cut
        }
        return (Entry(relative: java.relative, sha256: java.sha256, lines: java.lines.filter(keep)),
                Entry(relative: swift.relative, sha256: swift.sha256, lines: swift.lines.filter(keep)))
    }

    /// Differences between the reference and the Swift result. If the item set or the
    /// checksum does not match, the reference is stale ("REGENERATE"); otherwise lines are paired **by path**
    /// and the step input is added to every difference.
    static func differences(reference: [Entry], mine: [Entry], arm: String,
                            regenerate: String = JavaEngineParityTests.regenerate) -> String? {
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
        func shown(_ text: String) -> String { text.replacingOccurrences(of: "\\\\", with: "\\") }
        var report: [String] = []
        for (fullJava, fullSwift) in zip(reference, mine) where report.count < 25 {
            let (java, swift) = truncatedAtJavaNpe(fullJava, fullSwift)
            guard java.lines != swift.lines else { continue }
            var javaByPath: [String: String] = [:]
            var swiftByPath: [String: String] = [:]
            var inputs: [String: String] = [:]
            for line in java.lines {
                let path = JavaYamlParityTests.pathOf(line)
                if javaByPath[path] == nil { javaByPath[path] = JavaYamlParityTests.valueOf(line) }
                if isInput(line) { inputs[step(path)] = JavaYamlParityTests.valueOf(line) }
            }
            for line in swift.lines {
                let path = JavaYamlParityTests.pathOf(line)
                if swiftByPath[path] == nil { swiftByPath[path] = JavaYamlParityTests.valueOf(line) }
            }
            var seen = Set<String>()
            let before = report.count
            // At most five differences per item: a defect in the score stream drags through all further steps.
            for path in (java.lines + swift.lines).map(JavaYamlParityTests.pathOf)
            where report.count < 25 && report.count - before < 5 {
                guard seen.insert(path).inserted else { continue }
                let javaText = javaByPath[path] ?? "<row missing>"
                let swiftText = swiftByPath[path] ?? "<row missing>"
                guard javaText != swiftText else { continue }
                let input = inputs[step(path)].map { " | vstup " + shown($0) } ?? ""
                report.append("\(java.relative): \(path): java=\(shown(javaText)) swift=\(shown(swiftText))\(input)")
            }
            if report.count == before {
                report.append("\(java.relative): rows match, their order differs")
            }
        }
        guard !report.isEmpty else { return nil }
        return "MISMATCH (\(arm)) — input checksums match, but the result diverged from Java:\n"
            + report.joined(separator: "\n")
    }

    // MARK: - Score arm

    /// Runs one definition's stream exactly in the order of `EngineRefGen.scoreArm` (= `ContestSession.log`
    /// without bonuses and QTC; preview = `ContestSession.preview`).
    static func scoreStream(_ definition: ContestDefinition, _ inputs: [String],
                            _ environment: Environment) throws -> [String] {
        var out: [String] = []
        var factory: QsoContextFactory?
        var evaluator = MultiplierEvaluator(registry: environment.registry)
        var dupe = ContestDupeChecker(definition: definition)
        var qsoPoints: Int64 = 0
        var qsoCount: Int32 = 0
        let dupeWorthZero = definition.dupe?.dupeWorthZero ?? true

        for input in inputs {
            out.append(input)
            let f = fields(input)
            let p = f[0]
            if p == "/setup" {
                factory = QsoContextFactory(definition: definition, dxcc: environment.dxcc, exchange: ExchangeEngine(),
                                            myCall: unesc(f[2]), myGrid: unesc(f[3]), myItuZone: unesc(f[4]))
                continue
            }
            if f[2] == "T" {
                dupe.tour = unesc(f[3]).flatMap(Tour.parse)
                continue
            }
            guard f[2] == "Q" || f[2] == "P" else {
                // An unknown step kind (e.g. future bonus steps) must not silently be executed as a write.
                Issue.record(Comment(rawValue: "unknown step kind \(input)"))
                continue
            }
            let factoryNow = try #require(factory, "proud bez /setup")
            let preview = f[2] == "P"
            let at = try #require(Int64(f[3]))
            let call = unesc(f[4]), band = unesc(f[5]), mode = unesc(f[6])
            do {
                let context = try factoryNow.build(call: call, band: band, mode: mode, receivedRaw: map(f[7]),
                                                   ownQth: unesc(f[8]))
                out.append(line(p + "/class", "out", esc(context.workedClass)))
                out.append(line(p + "/rcv", "out", values(context.received)))
                if preview {
                    let points = try PointsCalculator.points(definition, context)
                    out.append(line(p + "/points", "out", String(points)))
                    out.append(line(p + "/dupe", "out", String(dupe.isDupe(context, atEpochSecond: at))))
                    out.append(line(p + "/mult", "out", results(try evaluator.preview(definition, context))))
                } else if band.map(JavaText.isBlank) ?? true || !ModeEligibility.counts(definition.modes, mode) {
                    out.append(line(p + "/counted", "out", "false"))
                } else {
                    out.append(line(p + "/counted", "out", "true"))
                    let isDupe = dupe.isDupe(context, atEpochSecond: at)
                    out.append(line(p + "/dupe", "out", String(isDupe)))
                    let points = isDupe && dupeWorthZero ? 0 : try PointsCalculator.points(definition, context)
                    out.append(line(p + "/points", "out", String(points)))
                    out.append(line(p + "/mult", "out", results(try evaluator.commit(definition, context))))
                    dupe.add(context, atEpochSecond: at)
                    qsoPoints = JavaMath.addLong(qsoPoints, Int64(points))
                    qsoCount = JavaMath.addInt(qsoCount, 1)
                }
            } catch {
                out.append(line(p + "/exc", "out", exc(error)))
            }
            out.append(line(p + "/score", "out", score(definition, qsoPoints, qsoCount, evaluator.tracker)))
        }
        return out
    }

    static func score(_ definition: ContestDefinition, _ qsoPoints: Int64, _ qsoCount: Int32,
                      _ tracker: MultiplierTracker) -> String {
        do {
            let s = try ScoreEngine.compute(definition, qsoPoints: qsoPoints, bonusPoints: 0, qtcPoints: 0,
                                            qsoCount: qsoCount, tracker: tracker)
            let groups = s.multByGroup.entries.map { esc($0.key) + "=" + ($0.value.map { String($0) } ?? "null") }.joined(separator: ",")
            return "qso=\(s.qsoCount) pts=\(s.qsoPoints) mult=\(s.multTotal) groups=[\(groups)] "
                + "bonus=\(s.bonusPoints) qtc=\(s.qtcPoints) total=\(s.total)"
        } catch {
            return exc(error)
        }
    }

    @Test func scoreArmMatchesJava() throws {
        try JavaV111Gate.run {
            let reference = try Self.reference("engine-score-java")
            let mine = try Self.runOverDefinitions(reference, Self.scoreStream)
            if let report = Self.differences(reference: reference, mine: mine, arm: "score arm") {
                Issue.record(Comment(rawValue: report))
            }
        }
    }

    /// Java NPEs (Swift's recorded leniency) are only in the synthetic `full-b` — it deliberately has a
    /// `nil` points rule and a `nil` binding. Elsewhere an NPE would mean a part of the stream is not compared,
    /// so it is pinned here where and why: a new item with an NPE turns this test red.
    @Test func javaNpeOnlyInFullDefinitionB() throws {
        let reference = try Self.reference("engine-score-java")
        let withNpe = reference.filter { $0.lines.contains { $0.contains(Self.javaNpe) } }.map(\.relative)
        #expect(withNpe == ["synthetic/full-b.yaml"])
        // Cut and range: NPE from the first step and in all 137 exceptions of full-b (a shift after regeneration is visible).
        let fullB = try #require(reference.first { $0.relative == "synthetic/full-b.yaml" })
        let npe = fullB.lines.filter { $0.contains(Self.javaNpe) && JavaYamlParityTests.pathOf($0).hasSuffix("/exc") }
        #expect(npe.first.map(JavaYamlParityTests.pathOf) == "/000/exc")
        #expect(npe.count == 137)
        let messages = Set(reference.flatMap(\.lines).filter { $0.contains(Self.javaNpe) }.map(JavaYamlParityTests.valueOf))
        #expect(messages.allSatisfy { $0.contains("PointRule.when()") || $0.contains("MultiplierBinding.bandWeights()") },
                Comment(rawValue: messages.sorted().joined(separator: "\n")))
        for name in ["engine-exchange-java", "engine-expressions-java"] {
            #expect(!(try Self.referenceText(name)).contains("NullPointerException"), "\(name) has an NPE")
        }
    }

    // MARK: - Exchange arm

    static func exchangeOps(_ definition: ContestDefinition, _ inputs: [String],
                            _ environment: Environment) throws -> [String] {
        let engine = ExchangeEngine()
        let received = definition.exchange?.received
        let sent = definition.exchange?.sent
        var out: [String] = []
        for input in inputs {
            out.append(input)
            let f = fields(input)
            let result: String
            do {
                switch f[2] {
                case "A":
                    result = ids(engine.activeReceivedFields(definition, unesc(f[3])))
                case "P":
                    let list = try #require(f[3] == "r" ? received : sent)
                    let index = try #require(Int(f[4]))
                    let field = try #require(list[index])
                    result = value(try engine.parse(field, unesc(f[5])))
                case "L":
                    let cls = unesc(f[3])
                    let list: [ContestDefinition.ExchangeField?] = cls == "*all"
                        ? (received ?? []) : engine.activeReceivedFields(definition, cls)
                    result = values(try engine.parseLine(list, unesc(f[4])))
                case "S":
                    var mode: Mode?
                    if f[3] != "~" {
                        let known: Mode = try #require(Mode(rawValue: f[3]), "unknown mode \(f[3])")
                        mode = known
                    }
                    let context = ExchangeContext(mode: mode,
                                                  nextSerial: try #require(Int32(f[4])),
                                                  station: map(f[5]) ?? JavaLinkedMap(), roverQth: unesc(f[6]))
                    result = strings(engine.sentDefaults(definition, context))
                case "G":
                    let grab = try ExchangeGrab.route(received, map(f[3]) ?? JavaLinkedMap(), unesc(f[4]))
                    result = grab.map { esc($0.fieldId) + "=" + esc($0.value) } ?? "~"
                case "E":
                    result = strings(SpotExchangeEstimator.estimate(received, unesc(f[3]), environment.dxcc))
                default:
                    Issue.record(Comment(rawValue: "unknown operation \(input)"))
                    result = "?"
                }
            } catch {
                result = exc(error)
            }
            out.append(line(f[0] + "/out", "out", result))
        }
        return out
    }

    @Test func exchangeArmMatchesJava() throws {
        try JavaV111Gate.run {
            let reference = try Self.reference("engine-exchange-java")
            let mine = try Self.runOverDefinitions(reference, Self.exchangeOps)
            if let report = Self.differences(reference: reference, mine: mine, arm: "exchange arm") {
                Issue.record(Comment(rawValue: report))
                return
            }
            #expect(JavaYamlParityTests.canonicalDocument(mine) == (try Self.referenceText("engine-exchange-java")))
        }
    }

    // MARK: - Expressions arm

    static func expressionRun(_ inputs: [String]) throws -> [String] {
        var variables = JavaLinkedMap<ExpressionValue>()
        var out: [String] = []
        for input in inputs {
            out.append(input)
            let f = fields(input)
            if f[0].hasPrefix("/var/") {
                switch f[2] {
                case "num":
                    let bits = try #require(UInt64(f[4], radix: 16))
                    variables.put(unesc(f[3]), .number(Double(bitPattern: bits)))
                case "str":
                    // A Java variable map has no null values; `~` would be a generator defect here.
                    let text = try #require(unesc(f[4]), "variable \(f[3]) without a value")
                    variables.put(unesc(f[3]), .text(text))
                default:
                    Issue.record(Comment(rawValue: "unknown variable type \(input)"))
                }
                continue
            }
            let result: String
            do {
                let value = try Expression.eval(unesc(f[2]), variables)
                result = "OK " + String(value.bitPattern, radix: 16)
            } catch {
                result = "ERR " + kindName(error.kind) + " " + esc(error.message)
            }
            out.append(line(f[0] + "/out", "out", result))
        }
        return out
    }

    @Test func expressionsArmMatchesJava() throws {
        try JavaV111Gate.run {
            let reference = try Self.reference("engine-expressions-java")
            var mine: [Entry] = []
            for entry in reference {
                let inputs = entry.lines.filter(Self.isInput)
                mine.append(Entry(relative: entry.relative,
                                  sha256: Self.checksum(definition: nil, registry: "", lines: inputs),
                                  lines: try Self.expressionRun(inputs)))
            }
            if let report = Self.differences(reference: reference, mine: mine, arm: "expressions arm") {
                Issue.record(Comment(rawValue: report))
                return
            }
            #expect(JavaYamlParityTests.canonicalDocument(mine) == (try Self.referenceText("engine-expressions-java")))
        }
    }

    // MARK: - The gate does not pass by accident

    /// The references carry what the gate stands on: every multiplier state, dupe and uncredited QSO,
    /// exceptions of numbers above 2³¹−1, expression errors of all three kinds and enough lines.
    @Test func referencesCarryCheckpoints() throws {
        let score = try Self.referenceText("engine-score-java")
        for state in ["KNOWN_NEW_MULTIPLIER", "KNOWN_ALREADY_WORKED", "UNKNOWN_ACCEPTED", "SUSPICIOUS", "INVALID_FORMAT"] {
            #expect(score.contains("," + state + ","), "state \(state) is missing from the stream")
        }
        #expect(score.components(separatedBy: "/dupe\",\"out\",\"true\"").count > 100)
        #expect(score.components(separatedBy: "/counted\",\"out\",\"false\"").count > 100)
        #expect(score.contains("EXC NumberFormatException"))
        #expect(score.contains("\"T\",\"1200/30\""))
        let scoreEntries = try Self.reference("engine-score-java")
        #expect(scoreEntries.count == 25)
        #expect(scoreEntries.allSatisfy { $0.lines.filter(Self.isInput).count == 151 })
        // The gate's DXCC fixture brought to life contests that would have no counterparts over `dxcc-test.json`:
        // sp-dx has non-zero points and multiplier results, rdxc the class `ru`; overflow wraps points past 2³¹.
        let byName = Dictionary(scoreEntries.map { ($0.relative, $0.lines) }, uniquingKeysWith: { first, _ in first })
        let spDx = try #require(byName["contests/sp-dx.yaml"])
        #expect(spDx.contains { $0.contains("/points\",\"out\",\"") && !$0.hasSuffix(",\"0\"]") })
        #expect(spDx.contains { $0.contains("/mult\",\"out\",\"") && !$0.hasSuffix(",\"\"]") })
        #expect(try #require(byName["contests/rdxc.yaml"]).contains { $0.hasSuffix("/class\",\"out\",\"ru\"]") })
        #expect(try #require(byName["gate/overflow.yaml"]).contains { $0.hasSuffix("/points\",\"out\",\"-294967296\"]") })
        let exchange = try Self.referenceText("engine-exchange-java")
        #expect(exchange.contains("EXC NumberFormatException"))
        #expect(exchange.components(separatedBy: "\"in\",\"G\"").count > 1000)
        let expressions = try Self.referenceText("engine-expressions-java")
        for kind in ["illegalArgument", "numberFormat", "patternSyntax"] {
            #expect(expressions.components(separatedBy: "\"ERR \(kind) ").count > 30, "too few errors \(kind)")
        }
        #expect(expressions.components(separatedBy: "\"OK ").count > 1500)
    }
}
