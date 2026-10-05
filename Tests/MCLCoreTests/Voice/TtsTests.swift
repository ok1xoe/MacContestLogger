import Testing
@testable import MCLCore

/// Port of `voice/TtsTest` (2 tests, same names).
@Suite struct TtsTests {

    let ctx = VoiceMessagePlanner.Context(operatorCall: "OK1XOE", myCall: "OK1XOE", hisCall: "W1AW", serial: 12,
                                          freqHz: 14_250_000)

    @Test func phoneticAndMacros() {
        #expect(VoiceMessagePlanner.phonetic("ok1xoe/p") == "Oscar Kilo 1 X-ray Oscar Echo stroke Papa")
        #expect(VoiceMessagePlanner.ttsText("CQ contest *", ctx) == "CQ contest Oscar Kilo 1 X-ray Oscar Echo")
        #expect(VoiceMessagePlanner.ttsText("! five nine #", ctx) == "Whiskey 1 Alfa Whiskey five nine 1 2")
    }

    @Test func ttsTokenUsesSpeechEngine() throws {
        var spoken: [String] = []
        let tts = try JavaPath("/tmp/tts.wav")
        let plan = try VoiceMessagePlanner.plan(
            "[CQ test *], cq.wav", ctx: ctx, wavDir: try JavaPath("/wav"), lettersDir: try JavaPath("/wav/letters"),
            exists: { _ in true }, speech: { text in
                spoken.append(text)
                return tts
            })
        #expect(plan.files == [tts, try JavaPath("/wav/cq.wav")])
        #expect(spoken == ["CQ test Oscar Kilo 1 X-ray Oscar Echo"])

        let failed = try VoiceMessagePlanner.plan("[hello]", ctx: ctx, wavDir: try JavaPath("/wav"),
                                                  lettersDir: try JavaPath("/l"), exists: { _ in true },
                                                  speech: { _ in nil })
        #expect(failed.missing.first?.hasPrefix("TTS:") == true)
    }
}
