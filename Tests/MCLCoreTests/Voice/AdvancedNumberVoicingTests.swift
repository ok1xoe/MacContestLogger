import Foundation
@testable import MCLCore
import Testing

/// N1MM advanced voicing of serial numbers and the playback level.
@Suite struct AdvancedNumberVoicingTests {

    @Test func numberWords() {
        #expect(VoiceMessagePlanner.numberWords(0) == ["0"])
        #expect(VoiceMessagePlanner.numberWords(7) == ["7"])
        #expect(VoiceMessagePlanner.numberWords(17) == ["17"])
        #expect(VoiceMessagePlanner.numberWords(40) == ["40"])
        #expect(VoiceMessagePlanner.numberWords(123) == ["1", "HUNDRED", "20", "3"])
        #expect(VoiceMessagePlanner.numberWords(1005) == ["1", "THOUSAND", "5"])
        #expect(VoiceMessagePlanner.numberWords(2017) == ["2", "THOUSAND", "17"])
        #expect(VoiceMessagePlanner.numberWords(12_450) == ["12", "THOUSAND", "4", "HUNDRED", "50"])
    }

    private static let wav: JavaPath = VoiceMessagePlannerTests.wav
    private static let letters: JavaPath = VoiceMessagePlannerTests.letters

    private static func plan(serial: Int32, all: Bool) throws -> VoiceMessagePlanner.Plan {
        var ctx = VoiceMessagePlannerTests.ctx
        ctx.serial = serial
        var names: Set<String> = ["1.wav", "2.wav", "3.wav"]
        for name in VoiceMessagePlanner.advancedNumberFiles where all || name != "THOUSAND" {
            names.insert(name + ".wav")
        }
        return try VoiceMessagePlanner.plan("#", ctx: ctx, wavDir: wav, lettersDir: letters, exists: { path in
            names.contains(path.description.split(separator: "/").last.map(String.init) ?? "")
        }, speech: nil)
    }

    private static func names(_ files: [JavaPath]) -> [String] {
        var out: [String] = []
        for file in files {
            let parts: [Substring] = file.description.split(separator: "/")
            out.append(parts.last.map(String.init) ?? "")
        }
        return out
    }

    @Test func serialsAreVoicedAsWordsWhenAllFilesExist() throws {
        let words = try Self.plan(serial: 123, all: true)
        #expect(Self.names(words.files) == ["1.wav", "HUNDRED.wav", "20.wav", "3.wav"])
        // A missing file: digit by digit (the longest recorded snippet), as before.
        let digits = try Self.plan(serial: 123, all: false)
        #expect(Self.names(digits.files) == ["12.wav", "3.wav"])
    }

    @Test func playbackLevelScalesSigned16Bit() {
        let samples: [Int16] = [1000, -1000, 32_767, -32_768]
        var bytes: [UInt8] = []
        for sample in samples {
            bytes.append(UInt8(truncatingIfNeeded: sample))
            bytes.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
        let half: [UInt8] = SoundCard.scaled(bytes, bits: 16, gain: 0.5)
        var back: [Int16] = []
        for i in stride(from: 0, to: half.count, by: 2) {
            let low: UInt16 = UInt16(half[i])
            let high: UInt16 = UInt16(half[i + 1]) << 8
            back.append(Int16(bitPattern: low | high))
        }
        #expect(back == [500, -500, 16_384, -16_384])
        #expect(SoundCard.scaled(bytes, bits: 16, gain: 1) == bytes)
        #expect(SoundCard.scaled(bytes, bits: 8, gain: 0.5) == bytes)
    }
}
