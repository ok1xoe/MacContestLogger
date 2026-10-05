import Foundation
@testable import MCLAppModel
@testable import MCLCore

/// Synthetic receiver audio for the CW reader and waterfall tests: samples (−1…1) and their 16-bit PCM, fed into a
/// deviceless capture with `AudioCapture.accept` (nothing is recorded from a device).
enum RadioSignals {

    static let sampleRate = Double(AudioCapture.sampleRate)

    /// A sine of `hz` with amplitude `amp`, `n` samples.
    static func tone(_ hz: Double, _ n: Int, _ amp: Double) -> [Double] {
        (0..<n).map { i in amp * sin(2 * Double.pi * hz * Double(i) / sampleRate) }
    }

    private static let code: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....",
        "I": "..", "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.",
        "Q": "--.-", "R": ".-.", "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
        "Y": "-.--", "Z": "--..", "1": ".----", "2": "..---", "3": "...--", "4": "....-", "5": ".....",
        "6": "-....", "7": "--...", "8": "---..", "9": "----.", "0": "-----",
    ]

    /// Clean keyed CW (a dot of `fs × 1.2 / wpm` samples, gaps of 1/3/7 dots, silence before and after), with a
    /// faint second tone far from the pitch as the noise floor.
    static func cw(_ text: String, wpm: Int, tone: Double) -> [Double] {
        let dot = Int(sampleRate * 1.2 / Double(wpm))
        var samples: [Double] = []
        func emit(_ length: Int, _ on: Bool) {
            for _ in 0..<length {
                let t: Double = Double(samples.count) / sampleRate
                let keyed: Double = on ? 0.5 * sin(2 * Double.pi * tone * t) : 0
                samples.append(keyed + 0.005 * sin(2 * Double.pi * 2_345 * t))
            }
        }
        emit(dot * 10, false)
        for word in text.split(separator: " ") {
            for character in word {
                for mark in code[character] ?? "" {
                    emit(mark == "." ? dot : 3 * dot, true)
                    emit(dot, false)
                }
                emit(2 * dot, false)
            }
            emit(4 * dot, false)
        }
        emit(dot * 20, false)
        return samples
    }

    /// 16-bit little-endian PCM of `samples` (`AudioCapture.toSamples` reverses it).
    static func pcm(_ samples: [Double]) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(samples.count * 2)
        for sample in samples {
            let value = Int16(max(-1, min(1, sample)) * 32_767)
            let bits = UInt16(bitPattern: value)
            bytes.append(UInt8(bits & 0xFF))
            bytes.append(UInt8(bits >> 8))
        }
        return bytes
    }

    /// Feeds `samples` into the app's running (deviceless) capture.
    @MainActor
    static func feed(_ app: KeyingApp, _ samples: [Double]) throws {
        guard let generation = app.keying.lastAudioGeneration else { throw POSIXError(.ENODEV) }
        app.model.audio.capture.accept(pcm(samples), generation: generation)
    }
}
