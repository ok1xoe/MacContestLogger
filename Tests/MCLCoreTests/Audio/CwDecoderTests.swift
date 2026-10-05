import Testing
@testable import MCLCore

/// Port of `audio/CwDecoderTest` (3 tests, same names). The signal generator is `AudioSignals.cw`
/// (noise `JavaRandom(1).nextGaussian` bitwise like Java).
@Suite struct CwDecoderTests {

    static func decode(_ signal: [Double], _ tone: Double) -> String {
        JavaText.trim(AudioSignals.decode(signal, tone: tone).text)
    }

    @Test func decodesCleanCw() {
        let got = Self.decode(AudioSignals.cw("CQ TEST OK1XOE", wpm: 25, tone: 600, noise: 0.01), 600)
        #expect(got.contains("CQ TEST OK1XOE"), "\(got)")
    }

    @Test func decodesFasterCwInNoise() {
        let got = Self.decode(AudioSignals.cw("CQ TEST OK1XOE", wpm: 32, tone: 700, noise: 0.08), 700)
        #expect(got.contains("TEST") && got.contains("OK1XOE"), "\(got)")
    }

    @Test func extractsCallsignsNewestFirstWithoutMyCall() {
        #expect(CwDecoder.callsigns("CQ TEST OK2XYZ  OK1XOE 5NN 15 TU DL1ABC 599 *E", myCall: "OK1XOE")
            == ["DL1ABC", "OK2XYZ"])
        #expect(CwDecoder.callsigns("de sp9/ok1xoe/p k", myCall: "OK1ABC") == ["SP9/OK1XOE/P"])
    }
}
