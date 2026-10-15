import Foundation
import Testing
@testable import MCLCore

/// QSB and QRM of the pileup simulator: pure functions, no randomness of the simulator's own.
@Suite struct SimConditionsTests {

    @Test func aCallerFadesTheSameWayEveryTime() {
        let first = SimConditions.qsbParameters(call: "DL1ABC")
        let again = SimConditions.qsbParameters(call: "dl1abc")
        #expect(first.periodSeconds == again.periodSeconds && first.phase == again.phase)
        for call in ["DL1ABC", "OK1XOE", "K1TTT", "JA1ZZZ", "VK2XX"] {
            let parameters = SimConditions.qsbParameters(call: call)
            #expect(SimConditions.qsbPeriodRange.contains(parameters.periodSeconds))
            #expect(parameters.phase >= 0 && parameters.phase < 2 * Double.pi)
        }
        #expect(SimConditions.qsbParameters(call: "DL1ABC").periodSeconds
            != SimConditions.qsbParameters(call: "OK1XOE").periodSeconds)
    }

    @Test func theGainStaysBetweenTheDepthAndOne() {
        var lowest = 1.0
        var highest = 0.0
        for step in 0..<1_000 {
            let gain = SimConditions.qsbGain(seconds: Double(step) / 100, periodSeconds: 4, phase: 0.3)
            lowest = min(lowest, gain)
            highest = max(highest, gain)
        }
        #expect(lowest >= 1 - SimConditions.qsbDepth - 1e-9 && lowest < 0.2)
        #expect(highest <= 1 && highest > 0.99)
    }

    @Test func fadingScalesTheSignalAndKeepsItsLength() {
        let samples: [Float] = CwSynth.render("TEST", wpm: 25, pitchHz: 600, amplitude: 0.4, sampleRate: 12_000)
        let faded: [Float] = SimConditions.applyQsb(samples, call: "DL1ABC", sampleRate: 12_000, startSeconds: 1)
        #expect(faded.count == samples.count)
        for (a, b) in zip(samples, faded) {
            #expect(abs(b) <= abs(a) + 1e-6)
        }
        #expect(faded != samples)
        #expect(SimConditions.applyQsb(samples, call: "DL1ABC", sampleRate: 12_000, depth: 0) == samples)
    }

    @Test func theQrmStationsComeInRotation() {
        let first = SimConditions.qrm(0)
        #expect(first.text == "CQ TEST DL5QRM DL5QRM")
        #expect(first.pitchOffsetHz == 150)
        #expect(first.delayMs == 0)
        #expect(SimConditions.qrm(1).pitchOffsetHz < 0)
        for index in 0..<50 {
            let qrm = SimConditions.qrm(index)
            #expect((150...450).contains(abs(qrm.pitchOffsetHz)))
            #expect((0..<600).contains(qrm.delayMs))
            #expect(!qrm.text.isEmpty)
        }
        #expect(SimConditions.qrm(-3) == SimConditions.qrm(0))
        #expect(SimConditions.qrmAmplitude < 0.1, "weaker than the weakest caller")
    }
}
