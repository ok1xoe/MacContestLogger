import Foundation
import Testing
@testable import MCLCore

/// Parity suite of `ProfileMerge` against v1.1.1: `Fixtures/profile-merge-java.tsv.gz` is the output of the JVM probe
/// a maintainer-only probe, which runs the real `ConfigProfiles.loadInto` (Jackson
/// 2.22 `readerForUpdating`) over 1 765 profile files on three bases: the hand-written cases, `null` for every
/// property of every class in its natural position, an unknown enum constant for every enum property, 58 scalar
/// tokens in 23 positions (every property type, merged and new beans, lists, maps, the root), streaming quirks,
/// syntax errors, invalid UTF-8 (also in names: the quad arithmetic), escaped surrogates, UTF-16/UTF-32 input,
/// number-length limits, message truncation, non-finite doubles in the live configuration. Every case: the same
/// result, or the same Java class, the same message and the same partially merged configuration — except the
/// pinned `documentedDivergences`.
///
/// Comparison: the Java configuration (serialized by Jackson through its getters) is read by
/// `ProfileMerge.decode` after the documented normalization of `ProfileJson.decodable` (a `null` dropped), and
/// the random `id` of a new `SkedEntry` is masked on both sides.
///
/// A failure of the schema tests after a Java-side change: regenerate as in a maintainer-only probe.
/// A failure because Swift writes a key Java does not know: see `swiftOnlyHint`.
@Suite struct ProfileMergeJavaParityTests {

    static let regenerateHint: String = "the fixture and ProfileMergeSchemaTable.swift are generated from Java v1.1.1"
        + " by a maintainer-only generator (not in this repository)."
    static let swiftOnlyHint: String = "a Swift-only configuration field needs an entry in"
        + " ProfileMergeSchema.swiftOnlyProperties (see its documentation), not in the generated table"

    struct NotAnObject: Error {}

    /// Cases whose message differs knowingly (the class and the configuration still match), by case number.
    static let documentedDivergences: [Int: String] = [
        // UTF-16 input with non-ASCII text before the error: Jackson's char-based parser counts the column in
        // chars (22), Swift parses the UTF-8 transcoding and counts bytes (23).
        1765: "column of non-ASCII UTF-16 input",
    ]

    struct Case {
        let number: Int
        let base: String
        let input: Data
        let ok: Bool
        let javaClass: String
        let message: String
        let diff: String
    }

    struct Fixture {
        var bases: [String: String] = [:]
        var cases: [Case] = []
        var classes: [(name: String, known: [String])] = []
        var properties: [(owner: String, name: String, kind: String, nullOutcome: String)] = []
        var enums: [String: [String]] = [:]
        var validNames: [(name: String, valid: Bool)] = []
        var listed: [String] = []
    }

    static func fixture() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "profile-merge-java.tsv", withExtension: "gz"),
                               "the bundle has no profile-merge-java.tsv.gz — the .copy rule in Package.swift")
        let text = try #require(String(data: try JavaIoParityFixture.gunzip(Data(contentsOf: url)), encoding: .utf8))
        var fixture = Fixture()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            switch cols[0] {
            case "CLASS":
                fixture.classes.append((cols[1], cols[2].split(separator: ",").map(String.init)))
            case "PROP":
                fixture.properties.append((cols[1], cols[2], cols[3], cols[5]))
            case "ENUM":
                fixture.enums[cols[1]] = cols[2].split(separator: ",").map(String.init)
            case "VALID":
                fixture.validNames.append((unescape(cols[1]), cols[2] == "true"))
            case "LIST":
                fixture.listed = cols[1].split(separator: "|", omittingEmptySubsequences: false).map {
                    unescape(String($0))
                }
            case "BASE":
                fixture.bases[cols[1]] = unescape(cols[2])
            case "CASE":
                fixture.cases.append(Case(number: Int(cols[1]) ?? 0, base: cols[2], input: unescapeBytes(cols[3]),
                                          ok: cols[4] == "OK", javaClass: cols[5], message: unescape(cols[6]),
                                          diff: unescape(cols[7])))
            default:
                Issue.record("unknown row \(cols[0])")
            }
        }
        return fixture
    }

    /// `\uXXXX` (UTF-16 units) back to text.
    static func unescape(_ text: String) -> String {
        var units: [UInt16] = []
        let source = Array(text.utf16)
        var index = 0
        while index < source.count {
            if source[index] == 0x5C, index + 5 < source.count + 0, source[index + 1] == 0x75,
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

    /// `\xHH` (bytes) back to bytes.
    static func unescapeBytes(_ text: String) -> Data {
        var bytes: [UInt8] = []
        let source = Array(text.utf8)
        var index = 0
        while index < source.count {
            if source[index] == 0x5C, index + 3 < source.count + 0, source[index + 1] == 0x78,
               let byte = UInt8(String(decoding: source[(index + 2)..<(index + 4)], as: UTF8.self), radix: 16) {
                bytes.append(byte)
                index += 4
            } else {
                bytes.append(source[index])
                index += 1
            }
        }
        return Data(bytes)
    }

    // MARK: - Java configuration → Swift

    static func tree(_ json: String) throws -> ProfileJson {
        try #require(ProfileJson.parse(Data(json.utf8)))
    }

    /// The Java configuration as Swift reads it: `ProfileJson.decodable` (a `null` dropped) and
    /// `ProfileMerge.decode` (Jackson's `NaN`/`Infinity` strings read as numbers).
    static func config(_ node: ProfileJson) throws -> AppConfig {
        guard case .object(let fields) = node else { throw NotAnObject() }
        return try ProfileMerge.decode(fields)
    }

    /// `base` with the probe's diff applied (JSON pointer → value).
    static func applying(_ diff: String, to base: ProfileJson) throws -> ProfileJson {
        guard case .object(let changes) = try tree(diff) else { return base }
        var result = base
        for (pointer, value) in changes {
            let path = pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map {
                $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            }
            result = set(value, at: ArraySlice(path), in: result)
        }
        return result
    }

    static func set(_ value: ProfileJson, at path: ArraySlice<String>, in node: ProfileJson) -> ProfileJson {
        guard let key = path.first else { return value }
        guard case .object(var fields) = node else { return node }
        fields[key] = set(value, at: path.dropFirst(), in: fields[key] ?? .null)
        return .object(fields)
    }

    /// Equal configurations, up to the random `id` of a new `SkedEntry` (Java masks it as `<random-uuid>`).
    static func same(_ swift: AppConfig, _ java: AppConfig) -> Bool {
        if swift == java {
            return true
        }
        // Also a `NaN` (never equal to itself) compares as Jackson's string here.
        guard let left = try? ProfileMerge.fields(of: swift), let right = try? ProfileMerge.fields(of: java) else {
            return false
        }
        return mask(.object(left)) == mask(.object(right))
    }

    static func mask(_ node: ProfileJson) -> ProfileJson {
        switch node {
        case .array(let items):
            return .array(items.map(mask))
        case .object(let fields):
            var result: [String: ProfileJson] = [:]
            for (key, value) in fields {
                if key == "id", case .string(let text) = value, text == "<random-uuid>" || UUID(uuidString: text) != nil {
                    result[key] = .string("<random-uuid>")
                } else {
                    result[key] = mask(value)
                }
            }
            return .object(result)
        default:
            return node
        }
    }

    // MARK: - Parity

    @Test func theFixtureHasEveryCase() throws {
        #expect(try Self.fixture().cases.count == 1_765)
    }

    /// The cases in eight shards (every eighth case), so that they run in parallel.
    @Test(arguments: 0..<8)
    func everyMeasuredCaseMatchesJava(shard: Int) throws {
        let fixture = try Self.fixture()
        var bases: [String: ProfileJson] = [:]
        var currents: [String: AppConfig] = [:]
        for (id, json) in fixture.bases {
            bases[id] = try Self.tree(json)
            currents[id] = try Self.config(Self.tree(json))
        }
        var failures: [String] = []
        for item in fixture.cases where item.number % 8 == shard {
            let base = try #require(bases[item.base])
            let current = try #require(currents[item.base])
            let expected = try Self.config(Self.applying(item.diff, to: base))
            let input = String(decoding: item.input, as: UTF8.self).replacingOccurrences(of: "\u{0}", with: "\\0")
            do {
                let merged = try ProfileMerge.merge(current: current, profileData: item.input)
                if !item.ok {
                    failures.append("#\(item.number) \(input): Swift OK, Java \(item.javaClass): \(item.message)")
                } else if !Self.same(merged, expected) {
                    failures.append("#\(item.number) \(input): different configuration")
                }
            } catch {
                if item.ok {
                    failures.append("#\(item.number) \(input): Java OK, Swift \(error.javaClass): "
                                    + (error.javaMessage ?? ""))
                } else if Self.documentedDivergences[item.number] != nil {
                    if error.javaClass != item.javaClass || error.javaMessage == item.message
                        || !Self.same(error.partial, expected) {
                        failures.append("#\(item.number): the documented divergence changed")
                    }
                } else if error.javaClass != item.javaClass
                            || Self.withoutSwiftOnlyCount(error.javaMessage) != item.message {
                    failures.append("#\(item.number) \(input):\n  Java  \(item.javaClass): \(item.message)\n"
                                    + "  Swift \(error.javaClass): \(error.javaMessage ?? "")")
                } else if !Self.same(error.partial, expected) {
                    failures.append("#\(item.number) \(input): different partial configuration")
                }
            }
        }
        let report: String = "\(failures.count) cases differ:\n" + failures.prefix(40).joined(separator: "\n")
        #expect(failures.isEmpty, Comment(rawValue: report))
    }

    // MARK: - Schema

    @Test func schemaMatchesTheProbe() throws {
        let fixture = try Self.fixture()
        let generated = ProfileMergeSchema.generatedClasses
        let hint = Comment(rawValue: Self.regenerateHint)
        #expect(generated.count == fixture.classes.count, hint)
        for (name, known) in fixture.classes {
            let bean = try #require(generated[name], Comment(rawValue: "missing class \(name): " + Self.regenerateHint))
            #expect(bean.known == known, Comment(rawValue: "known properties of \(name): " + Self.regenerateHint))
        }
        for property in fixture.properties {
            let bean = try #require(generated[property.owner], hint)
            let swift = try #require(bean.property(property.name),
                                     Comment(rawValue: "\(property.owner).\(property.name): " + Self.regenerateHint))
            #expect(Self.describe(swift.kind) == property.kind, Comment(rawValue: "\(property.owner).\(property.name)"))
        }
        let propertyCount = generated.values.reduce(0) { $0 + $1.properties.count }
        #expect(propertyCount == fixture.properties.count, hint)
        #expect(ProfileMergeSchema.enums.mapValues(\.keys) == fixture.enums, hint)
    }

    /// The probe's notation of a property type.
    static func describe(_ kind: ProfileMergeSchema.Kind) -> String {
        switch kind {
        case .string: return "string"
        case .int: return "int"
        case .long: return "long"
        case .double: return "double"
        case .boolean: return "boolean"
        case .integer: return "Integer"
        case .enumeration(let name):
            let constants = ProfileMergeSchema.enums[name]?.constants ?? []
            return "enum(" + name + ":" + constants.joined(separator: ",") + ")"
        case .bean(let name): return "bean(" + name + ")"
        case .list(let element): return "list<" + describe(element) + ">"
        case .map(let element): return "map<" + describe(element) + ">"
        }
    }

    /// The table of `List`/`Map` paths of the Java `AppConfig` (replaced whole, never merged), pinned against the
    /// keys Swift's `AppConfig` writes: every such path is a JSON array / object in Swift's encoding.
    @Test func listAndMapPathsAreContainersInSwiftsAppConfig() throws {
        let root = try #require(ProfileMergeSchema.classes[ProfileMergeSchema.root])
        var paths: [String] = []
        let defaults = try ProfileMerge.fields(of: AppConfig())
        for property in root.properties {
            if case .bean(let name) = property.kind, let bean = ProfileMergeSchema.classes[name] {
                guard case .object(let nested)? = defaults[property.name] else {
                    Issue.record("Swift does not write \(property.name) as an object")
                    continue
                }
                for inner in bean.properties {
                    paths += Self.containerPath(property.name + "." + inner.name, inner.kind, nested[inner.name])
                }
            } else {
                paths += Self.containerPath(property.name, property.kind, defaults[property.name])
            }
        }
        #expect(paths.sorted() == [
            "antennas", "bandNotes", "contestSetups", "cwKeyer.runMessages", "cwKeyer.spMessages",
            "digital.runMessages", "digital.spMessages", "dxCluster.blacklistedCalls", "dxCluster.blacklistedSpotters",
            "dxCluster.callBlacklist",
            "dxCluster.commands", "dxCluster.favorites", "dxCluster.spotFilterHiddenBands",
            "dxCluster.spotFilterHiddenModes", "dxCluster.spotFilterSpotterContinents", "dxCluster.spotterBlacklist",
            "goals",
            "hamQth.callModes", "hamQth.fetchFields", "keyBindings", "openWindows", "qrz.callModes",
            "qrz.fetchFields", "transverters", "voiceKeyer.runMessages", "voiceKeyer.spMessages",
            "windowGeometry",
        ])
    }

    static func containerPath(_ path: String, _ kind: ProfileMergeSchema.Kind, _ value: ProfileJson?) -> [String] {
        switch (kind, value) {
        case (.list, .array?), (.map, .object?):
            return [path]
        case (.list, _), (.map, _):
            Issue.record("Swift does not write \(path) as a container: \(String(describing: value))")
            return [path]
        default:
            return []
        }
    }

    /// Swift writes and reads back the same keys as Jackson for the fixture configuration (so that a profile
    /// saved by either side merges key by key).
    @Test func swiftWritesJacksonsKeys() throws {
        let fixture = try Self.fixture()
        let java = try Self.tree(try #require(fixture.bases["C"]))
        let swift = ProfileJson.object(try ProfileMerge.fields(of: try Self.config(java)))
        var differences: [String] = []
        Self.compareKeys(java, swift, path: "", into: &differences)
        // The Swift-only keys (`ProfileMergeSchema.swiftOnlyProperties`) are written by Swift only, by design.
        let swiftOnly: Set<String> = Set(ProfileMergeSchema.swiftOnlyPaths
            .map { "/" + $0.joined(separator: "/") + " only in Swift" })
        differences.removeAll { swiftOnly.contains($0) }
        #expect(differences.isEmpty, Comment(rawValue: differences.joined(separator: "\n") + "\n" + Self.swiftOnlyHint))
    }

    /// Jackson's "Unrecognized field" message counts the known properties; Swift counts its Swift-only ones too
    /// (Java has no such message to match), so the count is brought back to Java's before comparing.
    static func withoutSwiftOnlyCount(_ message: String?) -> String? {
        guard let message else { return nil }
        for (owner, properties) in ProfileMergeSchema.swiftOnlyProperties
        where !properties.isEmpty && message.contains("(class " + owner + ")") {
            guard let range = message.range(of: #"\((\d+) known properties"#, options: .regularExpression),
                  let count = Int(message[range].filter(\.isNumber)) else { return message }
            return message.replacingCharacters(in: range, with: "(\(count - properties.count) known properties")
        }
        return message
    }

    static func compareKeys(_ java: ProfileJson, _ swift: ProfileJson, path: String, into out: inout [String]) {
        switch (java, swift) {
        case (.object(let left), .object(let right)):
            for key in Set(left.keys).union(right.keys).sorted() {
                switch (left[key], right[key]) {
                case (let javaValue?, let swiftValue?):
                    compareKeys(javaValue, swiftValue, path: path + "/" + key, into: &out)
                case (.some, nil):
                    out.append(path + "/" + key + " only in Java")
                default:
                    out.append(path + "/" + key + " only in Swift")
                }
            }
        case (.array(let left), .array(let right)):
            for (index, pair) in zip(left, right).enumerated() {
                compareKeys(pair.0, pair.1, path: path + "/" + String(index), into: &out)
            }
        default:
            return
        }
    }

    // MARK: - Names

    /// `ConfigProfiles.isValidName`: Java's `\p{L}`/`\p{N}` by code points (a surrogate pair is one, a
    /// combining mark is not a letter), at most 40, not blank.
    @Test func isValidNameMatchesJava() throws {
        let fixture = try Self.fixture()
        #expect(fixture.validNames.count == 32)
        for (name, valid) in fixture.validNames {
            #expect(ProfileMerge.isValidName(name) == valid, Comment(rawValue: "\(name.unicodeScalars.map(\.value))"))
            #expect(ConfigProfiles<AppConfig>.isValidName(name) == valid)
        }
    }

    /// `ConfigProfiles.list()` over the probe's directory: `.json` suffix (case-sensitive; the file `.json` is the
    /// name `""`, a directory counts too), sorted by `String.compareTo`.
    @Test func listMatchesJava() throws {
        let fixture = try Self.fixture()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = ["b.json", "a.json", ".json", "x.JSON", "y.json.bak", "\u{E9}.json", "Z.json", "\u{E4}.json",
                     "\u{1F600}.json", "\u{FF21}.json", "a b.json", "a-b.json", "a_b.json", "10.json", "9.json",
                     "notes.txt", ".hidden.json"]
        for file in files {
            try Data("{}".utf8).write(to: dir.appendingPathComponent(file))
        }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("dir.json"),
                                                withIntermediateDirectories: false)
        #expect(ConfigProfiles<AppConfig>(dir: dir).list() == fixture.listed)
        #expect(fixture.listed.first == "")
    }

    @Test func doublePropertiesArePinned() {
        var doubles: [String] = []
        for bean in ProfileMergeSchema.classes.values {
            for property in bean.properties where property.kind == .double {
                doubles.append(property.name)
            }
        }
        #expect(doubles.sorted() == ["freqKHz", "repeatSeconds"])
    }
}
