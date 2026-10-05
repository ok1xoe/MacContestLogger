import Foundation
import Testing
@testable import MCLCore

/// Port of `audio/WaterfallTest` (3 tests, same names).
@Suite struct WaterfallTests {

    @Test func fftFindsTone() throws {
        let db = try Fft.magnitudesDb(AudioSignals.tone(750, 2048, 0.5))
        var peak = 0
        for i in 1..<db.count where db[i] > db[peak] {
            peak = i
        }
        #expect(abs(Fft.binHz(peak, fftSize: 2048, sampleRate: AudioSignals.sampleRate) - 750) <= 6)
        #expect(throws: Fft.InvalidLength.self) {
            try Fft.magnitudesDb([Double](repeating: 0, count: 1000))
        }
    }

    @Test func waterfallRowsAndPeak() {
        let w = Waterfall(sampleRate: AudioSignals.sampleRate, maxHz: 3000, rows: 50)
        var sig = AudioSignals.tone(1200, 12_000, 0.3)
        for i in sig.indices {
            sig[i] += 0.001 * sin(Double(i) * 7.3) // a bit of "noise"
        }
        #expect(w.add(sig))
        let rows = w.normalizedRows()
        #expect(rows.count > 5)
        #expect(rows[0].count == Int(w.bins))
        #expect(abs(w.peakHz(lo: 200, hi: 2800) - 1200) <= 6)
        #expect(w.maxHz >= 3000)
    }

    @Test func pcmConversion() {
        let s = AudioCapture.toSamples([0, 0x40, 0, 0xC0])
        #expect(abs(s[0] - 0.5) <= 1e-9)
        #expect(abs(s[1] + 0.5) <= 1e-9)
    }
}
