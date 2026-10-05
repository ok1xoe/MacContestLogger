import Foundation

/// CW decoder from receiver audio (Java `audio/CwDecoder`, DXLog CW Reader): a Goertzel filter at the tone
/// pitch in 5 ms blocks, an envelope with an adaptive threshold, measuring mark and gap lengths with a running
/// speed estimate and conversion to Morse characters (`*` = unknown character, `' '` = gap between words).
///
/// Same order of operations as Java; `cos`/`sqrt` from Darwin libm (the decoded text
/// and `wpm` are compared exactly, intermediate values not). The class is not thread-safe — the caller
/// synchronises it (in Java `CwReaderWindow.kt`).
public final class CwDecoder {

    private static let morse: [String: Character] = [
        ".-": "A", "-...": "B", "-.-.": "C", "-..": "D", ".": "E", "..-.": "F", "--.": "G", "....": "H",
        "..": "I", ".---": "J", "-.-": "K", ".-..": "L", "--": "M", "-.": "N", "---": "O", ".--.": "P",
        "--.-": "Q", ".-.": "R", "...": "S", "-": "T", "..-": "U", "...-": "V", ".--": "W", "-..-": "X",
        "-.--": "Y", "--..": "Z", ".----": "1", "..---": "2", "...--": "3", "....-": "4", ".....": "5",
        "-....": "6", "--...": "7", "---..": "8", "----.": "9", "-----": "0", "-..-.": "/", "..--..": "?",
        ".-.-.-": ".", "--..--": ",", "-...-": "=", ".-.-.": "+",
    ]

    /// Minimum peak/noise ratio, below it nothing is decoded (noise only).
    private static let minSnr = 5.0

    private let sampleRate: Double
    private let block: Int32
    private var coeff = 0.0
    private let out: (Character) -> Void

    private var n: Int32 = 0
    private var q1 = 0.0
    private var q2 = 0.0
    // envelope and threshold
    private var peak = 1e-6
    private var noise = 1e-6
    private var primed = false
    private var keyDown = false
    private var runBlocks: Int32 = 0
    // timing (in blocks)
    private var dotBlocks = 6.0
    private var symbol = ""
    private var wordSpacePending = false

    /// - Parameters:
    ///   - sampleRate: sampling rate
    ///   - toneHz: CW tone pitch
    ///   - out: decoded characters (`' '` = gap between words)
    public init(sampleRate: Double, toneHz: Double, out: @escaping (Character) -> Void) {
        self.sampleRate = sampleRate
        block = JavaMath.l2i(JavaMath.round(sampleRate * 0.005)) // 5 ms blocks
        self.out = out
        setTone(toneHz)
    }

    public func setTone(_ toneHz: Double) {
        coeff = 2 * cos(2 * Double.pi * toneHz / sampleRate)
    }

    /// Speed estimate (WPM) from the dot length.
    public func wpm() -> Int32 {
        let dotMs = dotBlocks * 5
        return JavaMath.l2i(JavaMath.round(1200.0 / JavaMath.max(1, dotMs)))
    }

    public func add(_ samples: [Double]) {
        for s in samples {
            let q0: Double = coeff * q1 - q2 + s
            q2 = q1
            q1 = q0
            n &+= 1
            if n == block {
                let energy: Double = q1 * q1 + q2 * q2 - coeff * q1 * q2
                let mag = JavaMath.max(0, energy).squareRoot() / Double(block)
                q1 = 0
                q2 = 0
                n = 0
                onBlock(mag)
            }
        }
    }

    private func onBlock(_ mag: Double) {
        // Noise = average of blocks below the threshold, peak = slowly decaying maximum.
        if !primed {
            noise = mag
            peak = mag
            primed = true
        }
        peak = mag > peak ? mag : peak * 0.9995 + mag * 0.0005
        let threshold: Double = noise + (peak - noise) * 0.5
        if mag < threshold {
            noise = noise * 0.98 + mag * 0.02
        }
        let on = peak > noise * Self.minSnr && mag > (keyDown ? threshold * 0.8 : threshold)
        if on == keyDown {
            runBlocks &+= 1
            if !keyDown {
                checkGap()
            }
            return
        }
        if keyDown {
            onMark(runBlocks)
        } else {
            checkGap()
        }
        keyDown = on
        runBlocks = 1
    }

    private func onMark(_ len: Int32) {
        if len < 1 {
            return
        }
        let length = Double(len)
        if length < dotBlocks * 2 {
            symbol.append(".")
            dotBlocks = dotBlocks * 0.8 + length * 0.2
        } else {
            symbol.append("-")
            dotBlocks = dotBlocks * 0.8 + (length / 3.0) * 0.2
        }
        dotBlocks = JavaMath.max(1.5, JavaMath.min(40, dotBlocks))
        wordSpacePending = true
    }

    /// Gap: between characters (≥ 2 dots) emits a character, between words (≥ 5 dots) also a space.
    private func checkGap() {
        let run = Double(runBlocks)
        if !symbol.isEmpty && run >= dotBlocks * 2 {
            out(Self.morse[symbol] ?? "*")
            symbol = ""
        }
        if wordSpacePending && symbol.isEmpty && run >= dotBlocks * 5 {
            out(" ")
            wordSpacePending = false
        }
    }

    /// Callsigns in the decoded text (newest first), without the own callsign and without obvious non-callsigns
    /// (5NN, reports, all digits).
    public static func callsigns(_ text: String?, myCall: String?) -> [String] {
        CallsignScanner.recent(text, myCall: myCall)
    }
}
