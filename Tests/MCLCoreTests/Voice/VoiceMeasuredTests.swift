import Testing
@testable import MCLCore

/// `VoiceMessagePlanner` and `MacSpeech.cacheFile` against tables measured on Java (`VoiceAudioMeasured`,
/// rows `VMP.`/`MS.` of the maintainer-only probe).
@Suite struct VoiceMeasuredTests {

    static func rows(_ id: String) -> [[String]] {
        ProbeRows.rows(VoiceAudioMeasured.research, id)
    }

    static func nullable(_ text: String) -> String? {
        text == "<null>" ? nil : text
    }

    static func path(_ text: String) -> JavaPath {
        try! JavaPath(text)
    }

    @Test func phoneticMatchesJava() {
        let rows = Self.rows("VMP.phonetic")
        #expect(rows.count == 9)
        for row in rows {
            #expect(VoiceMessagePlanner.phonetic(Self.nullable(row[0])) == row[1], "\(row)")
        }
    }

    @Test func ttsTextMatchesJava() {
        let ctx = VoiceMessagePlanner.Context(operatorCall: "OK1XOE", myCall: "OK1XOE", hisCall: "W1AW", serial: 12,
                                              freqHz: 14_250_000)
        let rows = Self.rows("VMP.ttsText")
        #expect(rows.count == 6)
        for row in rows {
            #expect(VoiceMessagePlanner.ttsText(row[0], ctx) == row[1], "\(row)")
        }
    }

    @Test func frequencyMatchesJava() {
        let rows = Self.rows("VMP.frequency")
        #expect(rows.count == 14)
        for row in rows {
            #expect(VoiceMessagePlanner.frequency(Int64(row[0])!) == row[1], "\(row)")
        }
    }

    @Test func expandPathMatchesJava() {
        let rows = Self.rows("VMP.expandPath")
        #expect(rows.count == 5)
        for row in rows {
            #expect(VoiceMessagePlanner.expandPath(row[0], Self.nullable(row[1])) == row[2], "\(row)")
        }
    }

    /// 9 callsigns × 26 messages: files and missing items verbatim (Java `List.toString` over `Path`).
    @Test func planMatchesJava() throws {
        let existing: Set<String> = [
            "/wav/L/A.wav", "/wav/L/B.wav", "/wav/L/1.wav", "/wav/L/DL1.wav", "/wav/L/DL.wav", "/wav/L/AB1.wav",
            "/wav/L/stroke.wav", "/wav/L/point.wav", "/wav/L/4.wav", "/wav/L/\u{17D}.wav", "/wav/OK1XOE/CQ.wav",
            "/wav/cq.wav", "/x/abs.wav", "/wav/sub/../cq2.wav", "/cq3.wav",
        ]
        let speech: VoiceMessagePlanner.Speech = { text in
            text.contains("fail") ? nil : Self.path("/tts/\(text.utf16.count).wav")
        }
        let rows = Self.rows("VMP.plan")
        #expect(rows.count == 234)
        for row in rows {
            let ctx = VoiceMessagePlanner.Context(operatorCall: "ok1xoe", myCall: "AB1", hisCall: row[0], serial: 104,
                                                  freqHz: 14_250_050)
            let plan = try VoiceMessagePlanner.plan(row[1], ctx: ctx, wavDir: Self.path("/wav"),
                                                    lettersDir: Self.path("/wav/L"),
                                                    exists: { existing.contains($0.description) }, speech: speech)
            #expect(ProbeRows.javaList(plan.files.map(\.description)) == row[2], "\(row)")
            #expect(ProbeRows.javaList(plan.missing) == row[3], "\(row)")
        }
    }

    @Test func recordTargetMatchesJava() throws {
        let rows = Self.rows("VMP.recordTarget")
        #expect(rows.count == 10)
        for row in rows {
            let target = try VoiceMessagePlanner.recordTarget(row[0], operatorCall: row[1], wavDir: Self.path("/wav"))
            #expect((target.map { "Optional[\($0)]" } ?? "Optional.empty") == row[2], "\(row)")
        }
    }

    @Test func resolveDirMatchesJava() throws {
        let rows = Self.rows("VMP.resolveDir")
        #expect(rows.count == 5)
        for row in rows {
            let dir = try VoiceMessagePlanner.resolveDir(row[0], operatorCall: row[1], wavDir: Self.path("/wav"))
            #expect(dir.description == row[2], "\(row)")
        }
    }

    /// The name in the TTS cache: SHA-256 (voice.trim() + "|" + text), 12 bytes hex — the same cache as Java.
    @Test func cacheFileMatchesJava() {
        let rows = Self.rows("MS.cacheFile")
        #expect(rows.count == 4)
        for row in rows {
            let speech = MacSpeech(cacheDir: Self.path("/c"), voice: Self.nullable(row[0]))
            #expect(speech.cacheFile(row[1]).description == row[2], "\(row)")
        }
    }

    /// An item with NUL: Java throws from `Path.of` (`InvalidPathException`), Swift `JavaInvalidPathError`.
    @Test func nulInFileTokenThrows() {
        let ctx = VoiceMessagePlanner.Context(operatorCall: "A", myCall: "B", hisCall: "C", serial: 1, freqHz: 0)
        #expect(throws: JavaInvalidPathError.self) {
            try VoiceMessagePlanner.plan("a\u{0}b.wav", ctx: ctx, wavDir: Self.path("/wav"),
                                         lettersDir: Self.path("/wav/L"), exists: { _ in true })
        }
    }
}
