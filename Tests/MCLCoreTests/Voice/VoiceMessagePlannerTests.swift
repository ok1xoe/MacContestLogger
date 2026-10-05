import Testing
@testable import MCLCore

/// Port of `voice/VoiceMessagePlannerTest` (13 tests, same names).
@Suite struct VoiceMessagePlannerTests {

    static func path(_ text: String) -> JavaPath {
        try! JavaPath(text)
    }

    static let wav = path("/wav")
    static let letters = wav.resolve(path("LettersFiles/OK1XOE"))
    static let ctx = VoiceMessagePlanner.Context(
        operatorCall: "OK1XOE", myCall: "OK1XOE", hisCall: "DL1ABC", serial: 7, freqHz: 14_250_500)

    /// The file name if `p` is directly in the letters directory (Java `p.getParent().equals(LETTERS)`).
    static func letterName(_ p: JavaPath) -> String? {
        let prefix = letters.description + "/"
        guard p.description.hasPrefix(prefix) else { return nil }
        let name = String(p.description.dropFirst(prefix.count))
        return name.contains("/") ? nil : name
    }

    /// Files that "exist" — letters and digits + a few finished recordings.
    static func existing(_ extra: String...) -> (JavaPath) -> Bool {
        let known: Set<String> = ["A", "B", "C", "D", "E", "K", "L", "O", "X", "0", "1", "2", "4", "5", "7",
                                  "stroke", "strokep", "query", "point", "P"]
        return { p in
            if let file = letterName(p) {
                let name = file.hasSuffix(".wav") ? String(file.dropLast(4)) : file
                return known.contains(name) || extra.contains(name)
            }
            return extra.contains((try? wav.relativize(p).description) ?? "")
        }
    }

    static func names(_ plan: VoiceMessagePlanner.Plan) -> [String] {
        plan.files.map { p in
            letterName(p) ?? ((try? wav.relativize(p).description) ?? "?")
        }
    }

    static func plan(_ text: String, _ exists: (JavaPath) -> Bool) throws -> VoiceMessagePlanner.Plan {
        try VoiceMessagePlanner.plan(text, ctx: ctx, wavDir: wav, lettersDir: letters, exists: exists)
    }

    @Test func operatorMacroSelectsOperatorsFolder() throws {
        let p = try Self.plan("{OPERATOR}/CQ.wav", Self.existing("OK1XOE/CQ.wav"))

        #expect(Self.names(p) == ["OK1XOE/CQ.wav"])
        #expect(p.missing.isEmpty)
    }

    @Test func backslashAndWavdirFromN1mmFilesWork() throws {
        let p = try Self.plan("{WAVDIR}\\CQ.wav", Self.existing("OK1XOE/CQ.wav"))

        #expect(Self.names(p) == ["OK1XOE/CQ.wav"])
    }

    @Test func severalFilesSeparatedByComma() throws {
        let p = try Self.plan("{OPERATOR}/CQ.wav, {OPERATOR}/CQ.wav", Self.existing("OK1XOE/CQ.wav"))

        #expect(Self.names(p) == ["OK1XOE/CQ.wav", "OK1XOE/CQ.wav"])
    }

    @Test func emptyTokensAndEmptyWavAreSkipped() throws {
        let p = try Self.plan(" , empty.wav", Self.existing())

        #expect(p.files.isEmpty)
        #expect(p.missing.isEmpty)
    }

    @Test func missingFileIsReportedNotPlayed() throws {
        let p = try Self.plan("{OPERATOR}/CQ.wav,{OPERATOR}/Nope.wav", Self.existing("OK1XOE/CQ.wav"))

        #expect(Self.names(p) == ["OK1XOE/CQ.wav"])
        #expect(p.missing == ["OK1XOE/Nope.wav"])
    }

    @Test func bangVoicesHisCallLetterByLetter() throws {
        #expect(Self.names(try Self.plan("!", Self.existing())) == ["D.wav", "L.wav", "1.wav", "A.wav", "B.wav", "C.wav"])
    }

    @Test func recordedFragmentWinsOverLetters() throws {
        // N1MM: a recorded snippet ("DL1") is used instead of individual letters.
        #expect(Self.names(try Self.plan("!", Self.existing("DL1"))) == ["DL1.wav", "A.wav", "B.wav", "C.wav"])
    }

    @Test func hashVoicesSerialAndStarMyCall() throws {
        #expect(Self.names(try Self.plan("{OPERATOR}/59.wav,#", Self.existing("OK1XOE/59.wav"))) == ["OK1XOE/59.wav", "7.wav"])
        let star = Self.names(try Self.plan("*", Self.existing()))
        #expect(star == ["O.wav", "K.wav", "1.wav", "X.wav", "O.wav", "E.wav"])
        #expect(Self.names(try Self.plan("{MYCALL}", Self.existing())) == star)
    }

    @Test func atVoicesFrequencyWithPoint() throws {
        let expected: [String] = ["1.wav", "4.wav", "2.wav", "5.wav", "0.wav", "point.wav", "5.wav"]
        #expect(Self.names(try Self.plan("@", Self.existing())) == expected)
    }

    @Test func specialCharactersInCall() throws {
        let ctx = VoiceMessagePlanner.Context(operatorCall: "OK1XOE", myCall: "OK1XOE", hisCall: "OK1A/P", serial: 1, freqHz: 0)

        let plan = try VoiceMessagePlanner.plan("!", ctx: ctx, wavDir: Self.wav, lettersDir: Self.letters,
                                                exists: Self.existing())
        let n: [String] = plan.files.map { String($0.description.split(separator: "/").last!) }

        #expect(n == ["O.wav", "K.wav", "1.wav", "A.wav", "strokep.wav"])
    }

    @Test func missingLetterIsReported() throws {
        let ctx = VoiceMessagePlanner.Context(operatorCall: "OK1XOE", myCall: "OK1XOE", hisCall: "W1Z", serial: 1, freqHz: 0)

        let p = try VoiceMessagePlanner.plan("!", ctx: ctx, wavDir: Self.wav, lettersDir: Self.letters,
                                             exists: Self.existing())

        #expect(p.missing.contains { $0.hasSuffix("W.wav") })
        #expect(p.missing.contains { $0.hasSuffix("Z.wav") })
    }

    @Test func recordTargetOnlyForSingleFileMessage() throws {
        let wav = Self.wav
        #expect(try VoiceMessagePlanner.recordTarget("{OPERATOR}/CQ.wav", operatorCall: "OK1XOE", wavDir: wav)
            == wav.resolve(Self.path("OK1XOE/CQ.wav")))
        #expect(try VoiceMessagePlanner.recordTarget("a.wav,b.wav", operatorCall: "OK1XOE", wavDir: wav) == nil)
        #expect(try VoiceMessagePlanner.recordTarget("{OPERATOR}/59.wav,#", operatorCall: "OK1XOE", wavDir: wav) == nil)
        #expect(try VoiceMessagePlanner.recordTarget("", operatorCall: "OK1XOE", wavDir: wav) == nil)
    }

    @Test func lettersDirResolvesOperator() throws {
        #expect(try VoiceMessagePlanner.resolveDir("LettersFiles/{OPERATOR}", operatorCall: "OK1XOE", wavDir: Self.wav)
            == Self.wav.resolve(Self.path("LettersFiles/OK1XOE")))
        #expect(try VoiceMessagePlanner.resolveDir("/abs/letters", operatorCall: "OK1XOE", wavDir: Self.wav)
            == Self.path("/abs/letters"))
    }
}
