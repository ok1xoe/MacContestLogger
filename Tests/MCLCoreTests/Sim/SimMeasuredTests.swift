import Testing
@testable import MCLCore

/// `sim/` against Java v1.1.1 (maintainer-only probe, table `SimMeasured`):
/// `PileupSimulator` under a scripted operator over `new Random(seed)` (a shared source as in Kotlin and two
/// separate ones as in the Java test, `Settings` with the overflow of `2 * spread + 1`), `callSource`, `editDistance`,
/// `CwSynth.keying` (dot length in `float`) and `render` (envelope exactly, samples ±1 `float` ulp —).
/// Nothing here plays to a device.
@Suite struct SimMeasuredTests {

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rawRows(SimMeasured.rows, id)
    }

    private static let testPool: [String] = ["DL1ABC", "OK2XYZ", "SP9AAA", "G4BBB", "K1ZZ"]
    private static let oddPool: [String] = ["ok1abc", "OK1ABC", " ", "DL1X", "dl1x", ""]

    /// The probe's operator script (`SimProbe.SCRIPT`).
    private static let script: [String] = [
        "S:CQ TEST OK1XOE", "S:QRZ?", "S:<P>", "S:<T> 5NN 1", "S:?", "S:<C> 5NN 1", "S:AGN", "S:<CUR>",
        "L:OK", "S:TU OK1XOE TEST", "S:<c>", "S:NR?", "L:BAD", "L:NULL", "S:CQ", "S:", "N",
        "S:  cq\ttest  ", "S:<C>", "S:CALL?", "L:OK", "S:TEST", "S:OK1? DL? K? SP9AA? 9?", "S:<C2>", "L:OK",
        "S:QRZ", "S:\u{e9} cq \u{df}", "S:<C>\t5NN", "S:<CUR> TU", "L:OK", "L:OK", "S:<T2>", "S:<C3>?",
        "S:CQ", "S:CQ", "S:CQ", "S:<C>", "L:OK",
    ]

    // MARK: - Probe format

    private static func caller(_ c: PileupSimulator.Caller?) -> String {
        guard let c else { return "null" }
        let cols: [String] = [c.call, String(c.serial), String(c.wpm), String(c.pitchOffsetHz), String(c.patience)]
        return cols.joined(separator: "/")
    }

    private static func sent(_ out: [PileupSimulator.Transmission]) -> String {
        out.map { (t: PileupSimulator.Transmission) -> String in
            let head: String = caller(t.from) + ">" + String(t.delayMs)
            return head + ">" + t.text
        }.joined(separator: ";")
    }

    private static func pick(_ s: PileupSimulator, _ i: Int) -> String {
        let cs: [PileupSimulator.Caller] = s.callers
        if cs.isEmpty { return "NOBODY" }
        let index: Int = i < 0 ? cs.count - 1 : Swift.min(i, cs.count - 1)
        return cs[index].call
    }

    private static func resolve(_ text: String, _ s: PileupSimulator) -> String {
        let c: String = pick(s, 0)
        let cur: String = s.current?.call ?? "NOCUR"
        let typo: String = String(c.dropLast()) + (c.hasSuffix("Q") ? "R" : "Q")
        let typo2: String = (c.hasPrefix("X") ? "Y" : "X") + String(c.dropFirst())
        let partial: String = String(c.prefix(3)) + "?"
        var r: String = JavaText.replace(text, "<CUR>", cur)
        r = JavaText.replace(r, "<C2>", pick(s, 1))
        r = JavaText.replace(r, "<C3>", pick(s, -1))
        r = JavaText.replace(r, "<P>", partial)
        r = JavaText.replace(r, "<T2>", typo2)
        r = JavaText.replace(r, "<T>", typo)
        r = JavaText.replace(r, "<c>", JavaText.toLowerCase(c))
        return JavaText.replace(r, "<C>", c)
    }

    /// One script run → rows in the probe's shape (without `SIM.step`).
    private static func run(_ name: String, _ seed: Int64, _ settings: PileupSimulator.Settings,
                            _ source: @escaping () -> String?, _ random: any PileupRandom) -> [[String]] {
        let s = PileupSimulator(settings: settings, callSource: source, random: random)
        var out: [[String]] = []
        for (step, op) in script.enumerated() {
            var input: String? = op
            let result: String
            if op == "N" {
                input = nil
                result = outcome { try s.onSent(nil) }
            } else if op.hasPrefix("S:") {
                let text: String = resolve(String(op.dropFirst(2)), s)
                input = text
                result = outcome { try s.onSent(text) }
            } else {
                let cur: PileupSimulator.Caller? = s.current
                var call: String?
                var exch: String?
                switch op {
                case "L:OK":
                    call = cur?.call ?? "NONE"
                    exch = cur.map { "599 " + String($0.serial) } ?? "599"
                case "L:BAD":
                    call = (cur?.call ?? "NOCUR") + "X"
                    exch = "599 0001x"
                default:
                    call = nil
                    exch = nil
                }
                input = "log " + (call ?? "null") + " | " + (exch ?? "null")
                let k: PileupSimulator.Check = s.onLogged(call: call, exchange: exch)
                let cols: [String] = [k.loggedCall, k.expectedCall, String(k.callOk), String(k.exchangeOk),
                                      k.expectedExchange]
                result = cols.joined(separator: "|")
            }
            let callers: String = s.callers.map { caller($0) }.joined(separator: ",")
            out.append([name, String(seed), String(step), input ?? "null", result, callers, caller(s.current),
                        String(s.qsos), String(s.errors)])
        }
        return out
    }

    private static func outcome(_ body: () throws -> [PileupSimulator.Transmission]) -> String {
        do {
            return sent(try body())
        } catch let error as JavaIllegalArgumentError {
            return "throws IllegalArgumentException: " + error.message
        } catch {
            return "throws \(error)"
        }
    }

    private static func settings(_ a: Int32, _ b: Int32, _ c: Int32, _ d: Int32) -> PileupSimulator.Settings {
        PileupSimulator.Settings(activity: a, minWpm: b, maxWpm: c, pitchSpreadHz: d)
    }

    // MARK: - PileupSimulator

    @Test func settingsAreNormalizedLikeJava() throws {
        let rows: [[String]] = Self.rows("SIM.settings")
        #expect(rows.count == 7)
        for row in rows {
            let v: [Int32] = row[0].split(separator: ",").compactMap { Int32($0) }
            try #require(v.count == 4)
            let s = Self.settings(v[0], v[1], v[2], v[3])
            let got: String = [s.activity, s.minWpm, s.maxWpm, s.pitchSpreadHz].map { String($0) }
                .joined(separator: ",")
            #expect(got == row[1], "\(row)")
        }
    }

    @Test func callSourceMatchesJava() throws {
        let rows: [[String]] = Self.rows("SIM.src")
        #expect(rows.count == 21)
        for row in rows {
            let seed: Int64 = try #require(Int64(row[1]))
            let pool: [String] = row[0] == "made" ? [] : row[0] == "pool" ? Self.testPool : Self.oddPool
            let source = PileupSimulator.callSource(pool: pool, random: JavaPileupRandom(seed: seed))
            var got: [String] = []
            for _ in 0..<30 {
                got.append(source() ?? "null")
            }
            let expected: [String] = row[2].split(separator: ",", omittingEmptySubsequences: false)
                .map { ProbeRows.unescape(String($0)) }
            #expect(got == expected, "\(row[0]) \(seed)")
        }
    }

    @Test func editDistanceMatchesJava() {
        let rows: [[String]] = Self.rows("SIM.ed")
        #expect(rows.count == 14)
        for row in rows {
            let got: Int32 = PileupSimulator.editDistance(ProbeRows.unescape(row[0]), ProbeRows.unescape(row[1]))
            #expect(String(got) == row[2], "\(row)")
        }
    }

    @Test func scriptedOperatorMatchesJava() {
        var got: [[String]] = []
        let a = Self.settings(3, 22, 30, 300)
        for seed: Int64 in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 123_456_789_012_345] {
            let source = PileupSimulator.callSource(pool: Self.testPool, random: JavaPileupRandom(seed: seed))
            got += Self.run("A", seed, a, source, JavaPileupRandom(seed: seed))
        }
        let b = Self.settings(6, 18, 40, 500)
        for seed: Int64 in 1...6 {
            let shared = JavaPileupRandom(seed: seed)
            got += Self.run("B", seed, b, PileupSimulator.callSource(pool: [], random: shared), shared)
        }
        let c = Self.settings(1, 5, 3, 0)
        for seed: Int64 in 1...4 {
            let shared = JavaPileupRandom(seed: seed)
            got += Self.run("C", seed, c, PileupSimulator.callSource(pool: Self.oddPool, random: shared), shared)
        }
        let d = Self.settings(9, 40, 20, -5)
        for seed: Int64 in 1...3 {
            let source = PileupSimulator.callSource(pool: nil, random: JavaPileupRandom(seed: seed + 100))
            got += Self.run("D", seed, d, source, JavaPileupRandom(seed: seed))
        }
        let e = Self.settings(2, 25, 25, 1_073_741_824)
        for seed: Int64 in 1...2 {
            let shared = JavaPileupRandom(seed: seed)
            got += Self.run("E", seed, e, PileupSimulator.callSource(pool: Self.testPool, random: shared), shared)
        }
        got += Self.run("F", 1, Self.settings(4, 20, 30, 100), { nil }, JavaPileupRandom(seed: 1))

        let expected: [[String]] = Self.rows("SIM.step").map { $0.map(ProbeRows.unescape) }
        #expect(got.count == expected.count)
        #expect(expected.count == 1_026)
        var mismatches = 0
        for (g, x) in zip(got, expected) where g != x {
            mismatches += 1
            if mismatches <= 10 {
                Issue.record("SIM.step Java \(x)\nSwift \(g)")
            }
        }
        #expect(mismatches == 0, "SIM.step: \(mismatches) neshod")
    }

    /// Review focus: `2 * spread + 1` overflows in `int` → `nextInt` with a negative bound throws
    /// `IllegalArgumentException` in the middle of `refillCallers` (the callsign randomness and `wpm` already consumed).
    @Test func pitchSpreadOverflowThrowsLikeJava() {
        let shared = JavaPileupRandom(seed: 1)
        let s = PileupSimulator(settings: Self.settings(2, 25, 25, 1_073_741_824),
                                callSource: PileupSimulator.callSource(pool: Self.testPool, random: shared),
                                random: shared)
        #expect(throws: JavaIllegalArgumentError(message: "bound must be positive")) {
            try s.onSent("CQ")
        }
        #expect(s.callers.isEmpty)
    }

    // MARK: - CwSynth

    private static func floatBits(_ hex: String) -> Float {
        Float(bitPattern: UInt32(hex, radix: 16) ?? 0)
    }

    private static func doubleBits(_ hex: String) -> Double {
        Double(bitPattern: UInt64(hex, radix: 16) ?? 0)
    }

    private static func runs(_ v: [Bool]) -> String {
        var parts: [String] = []
        var i = 0
        while i < v.count {
            var j = i
            while j < v.count && v[j] == v[i] { j += 1 }
            parts.append((v[i] ? "+" : "-") + String(j - i))
            i = j
        }
        return parts.joined(separator: ",")
    }

    /// A match to 1 `float` ulp (HotSpot `Math.sin/cos` vs. Darwin libm).
    private static func withinUlp(_ a: Float, _ b: Float) -> Bool {
        if a.bitPattern == b.bitPattern { return true }
        let ulp: Float = Swift.max(a.ulp, b.ulp)
        return abs(a - b) <= ulp
    }

    @Test func ditLengthIsComputedInFloat() throws {
        let wpms: [Int32] = try #require(Self.rows("CW.wpms").first)[0].split(separator: ",").compactMap { Int32($0) }
        #expect(wpms.count == 76)
        let rows: [[String]] = Self.rows("CW.dit")
        #expect(rows.count == 17)
        for row in rows {
            let rate: Float = Self.floatBits(row[0])
            let got: [String] = wpms.map { String(CwSynth.keying("E", wpm: $0, sampleRate: rate).count / 4) }
            #expect(got.joined(separator: ",") == row[2], "rate \(row[1])")
        }
    }

    @Test func keyingMatchesJava() throws {
        let rows: [[String]] = Self.rows("CW.key")
        #expect(rows.count == 10)
        for row in rows {
            let wpm: Int32 = try #require(Int32(row[1]))
            let key: [Bool] = CwSynth.keying(ProbeRows.unescape(row[0]), wpm: wpm, sampleRate: Self.floatBits(row[2]))
            #expect(String(key.count) == row[3], "\(row[0])")
            #expect(Self.runs(key) == row[4], "\(row[0])")
        }
    }

    @Test func renderMatchesJavaWithinOneFloatUlp() throws {
        let rows: [[String]] = Self.rows("CW.render")
        #expect(rows.count == 14)
        for row in rows {
            let wpm: Int32 = try #require(Int32(row[1]))
            let out: [Float] = CwSynth.render(ProbeRows.unescape(row[0]), wpm: wpm, pitchHz: Self.doubleBits(row[2]),
                                              amplitude: Self.doubleBits(row[3]), sampleRate: Self.floatBits(row[4]))
            #expect(String(out.count) == row[5], "\(row)")
            // Envelope exactly: non-zero samples exactly where they are in Java.
            #expect(Self.runs(out.map { $0 != 0 }) == row[6], "\(row[0])")
            let excerpt: [Substring] = row.count > 7 ? row[7].split(separator: ",") : []
            for item in excerpt {
                let pair: [Substring] = item.split(separator: ":")
                let index: Int = try #require(Int(pair[0]))
                try #require(index < out.count)
                let java: Float = Self.floatBits(String(pair[1]))
                #expect(Self.withinUlp(out[index], java), "\(row[0]) [\(index)] Swift \(out[index]) Java \(java)")
            }
        }
    }
}
