import Foundation
@testable import MCLCore

/// Test signals ported from the Java tests of `audio/` (`WaterfallTest.tone`, `CwDecoderTest.cw`)
/// and the probe `ProbeVoiceAudio` (`cw` with the full alphabet). The noise is `new Random(1).nextGaussian()` via the
/// test `JavaRandom` (bitwise like Java); `sin` is from Darwin libm, not HotSpot.
enum AudioSignals {

    static let sampleRate = Double(AudioCapture.sampleRate)

    /// `WaterfallTest.tone`.
    static func tone(_ hz: Double, _ n: Int, _ amp: Double) -> [Double] {
        (0..<n).map { i in amp * sin(2 * Double.pi * hz * Double(i) / sampleRate) }
    }

    /// The generator's Morse code (`CwDecoderTest.CODE` is a subset of it with the same codes).
    static let code: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....",
        "I": "..", "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.",
        "Q": "--.-", "R": ".-.", "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
        "Y": "-.--", "Z": "--..", "1": ".----", "2": "..---", "3": "...--", "4": "....-", "5": ".....",
        "6": "-....", "7": "--...", "8": "---..", "9": "----.", "0": "-----", "/": "-..-.", "?": "..--..",
        "=": "-...-",
    ]

    /// `CwDecoderTest.cw`: a CW signal with noise (a dot of `(int)(fs × 1.2 / wpm)` samples, gaps of 1/3/7 dots,
    /// 10 dots of silence at the start and 20 at the end).
    static func cw(_ text: String, wpm: Int, tone: Double, noise noiseAmp: Double) -> [Double] {
        let dot = Int(sampleRate * 1.2 / Double(wpm))
        var s: [Double] = []
        var random = JavaRandom(seed: 1)
        func emit(_ length: Int, _ on: Bool) {
            for _ in 0..<length {
                let v: Double = on ? 0.5 * sin(2 * Double.pi * tone * Double(s.count) / sampleRate) : 0
                s.append(v + noiseAmp * random.nextGaussian())
            }
        }
        emit(dot * 10, false)
        for word in JavaText.split(text, unit: 0x20) {
            for character in word {
                for mark in code[character]! {
                    emit(mark == "." ? dot : 3 * dot, true)
                    emit(dot, false)
                }
                emit(2 * dot, false)
            }
            emit(4 * dot, false)
        }
        emit(dot * 20, false)
        return s
    }

    /// Decodes a signal in blocks of `chunk` samples (`CwDecoderTest.decode` without `trim`).
    static func decode(_ signal: [Double], tone: Double, chunk: Int = 1024) -> (text: String, wpm: Int32) {
        var text = ""
        let decoder = CwDecoder(sampleRate: sampleRate, toneHz: tone) { text.append($0) }
        var i = 0
        while i < signal.count {
            decoder.add(Array(signal[i..<min(signal.count, i + chunk)]))
            i += chunk
        }
        return (text, decoder.wpm())
    }
}
