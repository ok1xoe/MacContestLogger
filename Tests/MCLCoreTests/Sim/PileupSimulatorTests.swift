import Testing
@testable import MCLCore

/// `java.util.Random` behind the simulator protocol (`JavaRandom` only in tests and the parity suite).
final class JavaPileupRandom: PileupRandom {

    private var random: JavaRandom

    init(seed: Int64) {
        random = JavaRandom(seed: seed)
    }

    func nextInt(bound: Int32) -> Int32 {
        random.nextInt(bound: bound)
    }

    func nextDouble() -> Double {
        random.nextDouble()
    }
}

/// Ported Java `sim/PileupSimulatorTest` (5 tests, Java v1.1.1). `new Random(seed)` = `JavaPileupRandom`.
@Suite struct PileupSimulatorTests {

    private static func sim(_ seed: Int64) -> PileupSimulator {
        let pool: [String] = ["DL1ABC", "OK2XYZ", "SP9AAA", "G4BBB", "K1ZZ"]
        return PileupSimulator(settings: PileupSimulator.Settings(activity: 3, minWpm: 22, maxWpm: 30, pitchSpreadHz: 300),
                               callSource: PileupSimulator.callSource(pool: pool, random: JavaPileupRandom(seed: seed)),
                               random: JavaPileupRandom(seed: seed))
    }

    private static func firstCaller(_ s: PileupSimulator) throws -> PileupSimulator.Transmission {
        for _ in 0..<20 {
            let replies: [PileupSimulator.Transmission] = try s.onSent("CQ TEST OK1XOE")
            if let first = replies.first {
                return first
            }
        }
        Issue.record("nobody is calling")
        throw JavaIllegalArgumentError(message: "nobody is calling")
    }

    @Test func cqBringsCallersAndCallGetsExchange() throws {
        let s = Self.sim(1)
        let t = try Self.firstCaller(s)
        let call: String = t.from.call
        #expect(t.text == call)

        let ex: [PileupSimulator.Transmission] = try s.onSent(call + " 5NN 1")
        #expect(ex.count == 1)
        #expect(ex.first?.text == "5NN " + String(t.from.serial))
        #expect(s.current?.call == call)

        // AGN → repeats the exchange
        #expect(try s.onSent("AGN").first?.text == "5NN " + String(t.from.serial))

        let ok = s.onLogged(call: call, exchange: "599 " + String(t.from.serial))
        #expect(ok.ok)
        #expect(s.qsos == 1)
        #expect(s.errors == 0)
    }

    @Test func wrongLoggedDataIsReported() throws {
        let s = Self.sim(2)
        let t = try Self.firstCaller(s)
        _ = try s.onSent(t.from.call + " 5NN 1")
        let bad = s.onLogged(call: t.from.call + "X", exchange: "9999")
        #expect(!bad.callOk)
        #expect(!bad.exchangeOk)
        #expect(bad.expectedCall == t.from.call)
        #expect(s.errors == 1)
    }

    @Test func partialAndMistypedCallsGetRepeats() throws {
        let s = Self.sim(3)
        let t = try Self.firstCaller(s)
        let call: String = t.from.call
        let partial: [PileupSimulator.Transmission] = try s.onSent(String(call.prefix(3)) + "?")
        #expect(partial.contains { $0.from.call == call })

        let typo: String = String(call.dropLast()) + (call.hasSuffix("Q") ? "R" : "Q")
        let fix: [PileupSimulator.Transmission] = try s.onSent(typo + " 5NN 1")
        #expect(fix.contains { $0.text == "DE " + call + " " + call }, "\(fix)")
    }

    @Test func synthesizedCallerIsDecodable() {
        let rate = Float(AudioCapture.sampleRate)
        let audio: [Float] = CwSynth.render("DL1ABC", wpm: 28, pitchHz: 650, amplitude: 0.5, sampleRate: rate)
        var padded = [Double](repeating: 0, count: audio.count + 12_000)
        for i in 0..<audio.count {
            padded[3000 + i] = Double(audio[i])
        }
        var text = ""
        let decoder = CwDecoder(sampleRate: Double(AudioCapture.sampleRate), toneHz: 650) { text.append($0) }
        decoder.add(padded)
        #expect(text.contains("DL1ABC"), "\(text)")
    }

    @Test func editDistance() {
        #expect(PileupSimulator.editDistance("OK1XOF", "OK1XOE") == 1)
        #expect(PileupSimulator.editDistance("OK1XO", "OK1XOE") == 1)
        #expect(PileupSimulator.editDistance("K1ZZ", "K1ZZ") == 0)
    }
}
