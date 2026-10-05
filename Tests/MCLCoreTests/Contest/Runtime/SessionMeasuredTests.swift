import Foundation
import Testing
@testable import MCLCore

/// Replays the `SessionMeasured` cases (maintainer-only probe)
/// on the Swift `ContestSession` and compares every step — the result and the whole score after it — with Java.
/// Covers bonuses by `Scope` and `long` sums (measured table),
/// non-transactional `log`, counting by band and mode, TOUR, rover, bonus
/// stations, QTC, the multiplier grid and helper methods over cq-ww, wpx, iaru-hf (HQ), QSO party,
/// wae (QTC), dx and ww-digi.
@Suite struct SessionMeasuredTests {

    /// Steps where Java fails with an NPE; Swift is lenient (a deliberate divergence from Java v1.1.1).
    /// Key "scenario/step", value = (result, score) in Swift.
    static let lenient: [String: (String, String)] = [
        // `bonuses: [~, …]`: Java NPE on a `null` element; Swift skips it and awards the second bonus (ONCE)
        "bonus-nil-element/0": ("counted=true pts=0 dupe=false band=20m bonusStation=false qth=~ mults=[]",
                                "qsoCount=1 qsoPoints=0 mult=0 groups=[] bonus=10 qtc=0 total=0 qtcCount=0"),
        "bonus-nil-element/1": ("counted=true pts=0 dupe=false band=20m bonusStation=false qth=~ mults=[]",
                                "qsoCount=2 qsoPoints=0 mult=0 groups=[] bonus=10 qtc=0 total=0 qtcCount=0"),
    ]

    /// Every callsign is Czech (503, EU, CQ 15, ITU 28) — the Java anonymous `DxccLookup` of the probe.
    struct FakeCzech: DxccLookup {
        static let entity = DxccEntity(entityCode: 503, name: "Czech", countryCode: "CZ", continents: ["EU"],
                                       cq: [15], itu: [28], lat: 50.0, lon: 15.0)
        func resolve(_ callsign: String?) -> DxccEntity? { Self.entity }
        func entities() -> [DxccEntity] { [Self.entity] }
    }

    struct Row: Equatable, CustomStringConvertible {
        let result: String
        let score: String
        var description: String { result + "\t" + score }
    }

    static func expectedRows() throws -> [String: Row] {
        var out: [String: Row] = [:]
        for line in SessionMeasured.expected.split(separator: "\n", omittingEmptySubsequences: true) {
            let p = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            try #require(p.count == 4, "table row: \(line)")
            out[p[0] + "/" + p[1]] = Row(result: p[2], score: p[3])
        }
        return out
    }

    // MARK: - reading cases (like the probe)

    /// Columns separated by "¦", spaces around the separator are ignored (Java `split(" ?¦ ?", -1)`).
    static func columns(_ line: Substring) -> [String] {
        let parts = line.split(separator: "¦", omittingEmptySubsequences: false).map(String.init)
        return parts.enumerated().map { index, part in
            var p = Substring(part)
            if index > 0, p.first == " " { p = p.dropFirst() }
            if index < parts.count - 1, p.last == " " { p = p.dropLast() }
            return String(p)
        }
    }

    /// `~` = nil; `\u{XXXX}` = one UTF-16 unit.
    static func unesc(_ text: String) -> String? {
        if text == "~" { return nil }
        var units: [UInt16] = []
        var rest = Substring(text)
        while let range = rest.range(of: "\\u{") {
            units.append(contentsOf: rest[..<range.lowerBound].utf16)
            let after = rest[range.upperBound...]
            let close = after.firstIndex(of: "}")!
            units.append(UInt16(after[..<close], radix: 16)!)
            rest = after[after.index(after: close)...]
        }
        units.append(contentsOf: rest.utf16)
        return String(decoding: units, as: UTF16.self)
    }

    static func received(_ spec: String) -> JavaLinkedMap<String>? {
        if spec == "~" { return nil }
        var map = JavaLinkedMap<String>()
        if spec == "{}" { return map }
        for kv in spec.split(separator: ";", omittingEmptySubsequences: false) {
            let eq = kv.firstIndex(of: "=")!
            map.put(unesc(String(kv[..<eq])), unesc(String(kv[kv.index(after: eq)...])))
        }
        return map
    }

    static func list(_ spec: String) -> [String?]? {
        if spec == "~" { return nil }
        if spec == "-" { return [] }
        return spec.split(separator: ";", omittingEmptySubsequences: false).map { unesc(String($0)) }
    }

    // MARK: - text like the probe

    static let esc = ExchangeMeasuredTests.esc

    static func exception(_ error: ExpressionError) -> String {
        let name: String
        switch error.kind {
        case .illegalArgument: name = "IllegalArgumentException"
        case .numberFormat: name = "NumberFormatException"
        case .patternSyntax: name = "PatternSyntaxException"
        case .unsupportedPattern: name = "UnsupportedPattern"
        case .nestingTooDeep: name = "NestingTooDeep"
        }
        return "EXC " + name + ": " + esc(error.message)
    }

    static func exception(_ error: ContestSessionError) -> String {
        switch error {
        case .expression(let e): return exception(e)
        case .exchange(let e): return ExchangeMeasuredTests.exception(e)
        case .multiplier(let e): return "EXC MultiplierException: " + esc(e.message)
        }
    }

    static func result(_ r: ContestSession.LogResult) -> String {
        "counted=\(r.counted) pts=\(r.points) dupe=\(r.dupe) band=" + esc(r.context.band)
            + " bonusStation=\(r.context.bonusStation) qth=" + esc(r.context.ownQth)
            + " mults=[" + MultiplierEvaluatorTests.describe(r.multipliers) + "]"
    }

    static func score(_ s: ContestSession) -> String {
        do {
            let x = try s.score()
            let groups = x.multByGroup.entries.map { esc($0.key) + "=\($0.value ?? 0)" }
            return "qsoCount=\(x.qsoCount) qsoPoints=\(x.qsoPoints) mult=\(x.multTotal) groups=["
                + groups.joined(separator: ",") + "] bonus=\(x.bonusPoints) qtc=\(x.qtcPoints) total=\(x.total)"
                + " qtcCount=\(s.qtcCount)"
        } catch {
            return exception(error)
        }
    }

    /// Java `String.compareTo` (by UTF-16).
    static func javaLess(_ a: String, _ b: String) -> Bool {
        a.utf16.lexicographicallyPrecedes(b.utf16)
    }

    static func grid(_ s: ContestSession, _ selector: String, _ bandSpec: String) throws(ContestSessionError) -> String {
        let bands = bandSpec.split(separator: ";").map { Band.from(adif: String($0))! }
        let kind = selector.split(separator: ":", maxSplits: 1).first.map(String.init) ?? selector
        let arg = selector.contains(":") ? String(selector[selector.index(after: selector.firstIndex(of: ":")!)...]) : ""
        let g = try s.multiplierGrid(bands: bands) { binding, set in
            switch kind {
            case "dxcc": return set is DxccMultiplierSet
            case "set": return set.id.map { JavaText.equals(arg, $0) } ?? false
            case "binding": return binding.id.map { JavaText.equals(arg, $0) } ?? false
            case "all": return true
            default: return false
            }
        }
        var rows: [String] = []
        for r in g.rows {
            if r.workedBands.isEmpty && rows.count >= 3 { continue }   // unworked only the first three
            rows.append([esc(r.key), esc(r.label), esc(r.prefix), esc(r.continent),
                         r.workedBands.map { esc($0) }.joined(separator: "+")].joined(separator: ","))
        }
        return "available=\(g.available) worked=\(g.worked) possible=\(g.possible) rows=\(g.rows.count) ["
            + rows.joined(separator: ";") + "]"
    }

    static func time(_ spec: String) -> Int64? {
        spec == "~" ? nil : Int64(spec)!
    }

    /// One step (except `S`) like the probe.
    static func step(_ s: ContestSession, _ f: [String]) throws(ContestSessionError) -> String {
        switch f[0] {
        case "L":
            if f[5] == "now" {
                return result(try s.log(call: unesc(f[1]), band: unesc(f[2]), mode: unesc(f[3]),
                                        receivedRaw: received(f[4])))
            }
            return result(try s.log(call: unesc(f[1]), band: unesc(f[2]), mode: unesc(f[3]), receivedRaw: received(f[4]),
                                    atEpochSecond: time(f[5]), ownQth: unesc(f[6])))
        case "P":
            return result(try s.preview(call: unesc(f[1]), band: unesc(f[2]), mode: unesc(f[3]),
                                        receivedRaw: received(f[4]), ownQth: unesc(f[5])))
        case "R":
            return result(try s.replayLogged(call: unesc(f[1]), band: unesc(f[2]), mode: unesc(f[3]),
                                             exchangeRcvdFlat: unesc(f[4]), serialRcvd: f[5] == "~" ? nil : Int(f[5])!,
                                             atEpochSecond: time(f[6]), ownQth: unesc(f[7])))
        case "T":
            s.setTour(f[1] == "~" ? nil : Tour.parse(unesc(f[1]))!)
            return "tour=" + (s.tour.map { $0.format() } ?? "~")
        case "B":
            s.setBonusStations(list(f[1]))
            return "bonus=[" + s.bonusStations.sorted(by: javaLess).map { esc($0) }.joined(separator: ";") + "]"
        case "Q":
            s.setQtcCount(Int32(f[1])!)
            return "qtcCount=\(s.qtcCount)"
        case "G":
            return try grid(s, f[1], f[2])
        case "E":
            return "complete=\(try s.exchangeComplete(call: unesc(f[1]), receivedRaw: received(f[2])))"
        case "A":
            do {
                return "fields=[" + (try s.activeReceivedFields(call: unesc(f[1]))).map { esc($0.id) }
                    .joined(separator: ";") + "]"
            } catch {
                throw .expression(error)
            }
        case "F":
            do {
                let map = try s.receivedFromFlat(call: unesc(f[1]), exchangeRcvdFlat: unesc(f[2]),
                                                 serialRcvd: f[3] == "~" ? nil : Int(f[3])!)
                return "received=[" + map.entries.map { esc($0.key) + "=" + esc($0.value) }.joined(separator: ";") + "]"
            } catch {
                throw .expression(error)
            }
        case "O":
            return "ownQth=" + esc(s.ownQthFromSent(unesc(f[1])))
        case "M":
            let labels = s.multiplierLabels(setId: unesc(f[1]))
            let keys = labels.keys.compactMap { $0 }.sorted(by: javaLess)
            return "labels=[" + keys.map { esc($0) + "=" + esc(labels[$0]) }
                .joined(separator: ";") + "]"
        case "K":
            return "base=" + esc(ContestSession.baseCall(unesc(f[1])))
        default:
            preconditionFailure("unknown step \(f)")
        }
    }

    /// Replays all cases; returns (key "scenario/step", row).
    static func replayAll() throws -> [(String, Row)] {
        let dxcc = try SessionFixture.dxcc()
        let registry = try SessionFixture.registry(dxcc)
        let fake = FakeCzech()
        let emptyRegistry = MultiplierSetRegistry(dxcc: fake)
        var out: [(String, Row)] = []
        var name = ""
        var session: ContestSession?
        var index = 0
        for line in SessionMeasured.cases.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = columns(line)
            if f[0] == "S" {
                name = f[1]
                let isFake = f[2] == "fake"
                session = ContestSession(definition: try SessionFixture.definition(f[3]),
                                         dxcc: isFake ? fake : dxcc, registry: isFake ? emptyRegistry : registry,
                                         myCall: unesc(f[4]), myGrid: unesc(f[5]), myItuZone: unesc(f[6]))
                index = 0
                continue
            }
            let s = try #require(session)
            let result: String
            do {
                result = try step(s, f)
            } catch {
                result = exception(error)
            }
            out.append((name + "/\(index)", Row(result: result, score: score(s))))
            index += 1
        }
        return out
    }

    @Test func everyStepMatchesJava() throws {
        let expected = try Self.expectedRows()
        let actual = try Self.replayAll()
        #expect(actual.count == expected.count, "step count")
        for (key, row) in actual {
            if let pinned = Self.lenient[key] {
                #expect(row == Row(result: pinned.0, score: pinned.1), "\(key) (leniency)")
                #expect(expected[key]?.result.hasPrefix("EXC NullPointerException") == true, "\(key): Java crashes")
                continue
            }
            #expect(row == expected[key], "\(key)")
        }
    }

    /// Bonus table (probe `ProbeBonus`): `bonusPoints` after
    /// QSOs 1…6 — read here from the generated table and compared with the recorded notes, so that it is
    /// visible that the probe measures the same.
    @Test func bonusTableMatchesHandoffNotes() throws {
        let notes: [(String, String)] = [
            ("once", "10 10 10 10 10 10"),
            ("no-scope", "10 10 10 10 10 10"),
            ("per-band", "10 10 20 20 20 20"),
            ("per-mode", "10 10 10 20 20 20"),
            ("per-band-mode", "10 10 20 30 40 40"),
            ("when-cw", "10 10 20 20 20 20"),
            ("two-same-id", "10 10 10 10 10 10"),
            ("null-id", "10 10 20 20 20 20"),
            ("no-value", "0 0 0 0 0 0"),
            ("int-wrap", "2147483647 2147483647 4294967294 6442450941 8589934588 8589934588"),
        ]
        let expected = try Self.expectedRows()
        let actual = Dictionary(uniqueKeysWithValues: try Self.replayAll())
        for (name, values) in notes {
            var java: [String] = []
            var swift: [String] = []
            for index in 0..<6 {
                let key = "bonus-\(name)/\(index)"
                java.append(Self.bonus(try #require(expected[key]).score))
                swift.append(Self.bonus(try #require(actual[key]).score))
            }
            #expect(java.joined(separator: " ") == values, "\(name): Java")
            #expect(swift.joined(separator: " ") == values, "\(name): Swift")
        }
        // `bonuses: [~, …]`: Java NPE (notes), Swift skips the element (lenient)
        #expect(try #require(expected["bonus-nil-element/0"]).result.hasPrefix("EXC NullPointerException"))
    }

    private static func bonus(_ score: String) -> String {
        let field = score.split(separator: " ").first { $0.hasPrefix("bonus=") } ?? ""
        return String(field.dropFirst("bonus=".count))
    }
}
