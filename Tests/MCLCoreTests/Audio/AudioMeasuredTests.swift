import Foundation
import Testing
@testable import MCLCore

/// `audio/` against tables measured on Java (`VoiceAudioMeasured`; probes `research/ProbeP6.java`
/// and `voice-audio/ProbeVoiceAudio.java`).
///
/// Integer results (`AudioToRf`, peak positions, bin and row counts, decoded
/// text, `wpm`, PCM, WAV header) exactly; dB values and brightness with a tolerance (Darwin libm vs HotSpot).
@Suite struct AudioMeasuredTests {

    static func research(_ id: String) -> [[String]] {
        ProbeRows.rows(VoiceAudioMeasured.research, id)
    }

    static func extra(_ id: String) -> [[String]] {
        ProbeRows.rows(VoiceAudioMeasured.extra, id)
    }

    static func double(_ text: String) -> Double {
        JavaDouble.parseDouble(text)!
    }

    /// Relative tolerance for libm results (units of ulp, with margin for summation in the FFT).
    static func close(_ a: Double, _ b: Double, relative: Double = 1e-9) -> Bool {
        if a == b { return true }
        return abs(a - b) <= relative * max(abs(a), abs(b))
    }

    // MARK: - AudioToRf

    @Test func audioToRfMatchesJava() {
        let rows = Self.research("A2RF")
        #expect(rows.count == 72)
        for row in rows {
            let mode: String? = row[0] == "<null>" ? nil : row[0]
            let rf = AudioToRf.rfHz(dialHz: 14_025_000, rawMode: mode, audioHz: Self.double(row[1]), cwPitch: 600)
            #expect(String(rf) == row[2], "\(row)")
        }
        let more = Self.extra("A2RF.more")[0]
        let got: [Int64] = [
            AudioToRf.rfHz(dialHz: .max, rawMode: "USB", audioHz: 1, cwPitch: 600),
            AudioToRf.rfHz(dialHz: 0, rawMode: "CW", audioHz: 0, cwPitch: .min),
            AudioToRf.rfHz(dialHz: 14_000_000, rawMode: "l\u{17F}b", audioHz: 100, cwPitch: 600),
            AudioToRf.rfHz(dialHz: 14_000_000, rawMode: "USB", audioHz: .nan, cwPitch: 600),
            AudioToRf.rfHz(dialHz: 14_000_000, rawMode: "USB", audioHz: 1e30, cwPitch: 600),
            AudioToRf.rfHz(dialHz: 14_000_000, rawMode: "cwr", audioHz: -0.5, cwPitch: 600),
        ]
        #expect(got.map { String($0) } == more)
    }

    // MARK: - AudioCapture.toSamples

    @Test func toSamplesMatchesJava() {
        let samples = AudioCapture.toSamples([0, 0x40, 0, 0xC0, 0xFF, 0x7F, 0, 0x80, 1])
        #expect(ProbeRows.javaList(samples.map(JavaDouble.toString)) == Self.research("AC.toSamples")[0][0])
    }

    // MARK: - Fft

    @Test func fftMatchesJavaWithinTolerance() throws {
        var sig: [Double] = []
        for i in 0..<16 {
            let wave: Double = sin(Double(i) * 0.7) * 0.5
            let offset: Double = Double(i % 3) * 0.01
            sig.append(wave + offset)
        }
        let db = try Fft.magnitudesDb(sig)
        let java: [Double] = Self.research("FFT.bits16")[0][0].split(separator: " ")
            .map { Double(bitPattern: UInt64(bitPattern: Int64($0)!)) }
        #expect(db.count == java.count)
        for (got, expected) in zip(db, java) {
            #expect(Self.close(got, expected), "\(got) vs \(expected)")
        }
    }

    @Test func fftRejectsLengthsLikeJava() throws {
        let bad = Self.research("FFT.bad")[0]
        for (index, length) in [0, 3].enumerated() {
            #expect(throws: Fft.InvalidLength(length: length)) {
                try Fft.magnitudesDb([Double](repeating: 0, count: length))
            }
            #expect("EXC IllegalArgumentException: " + Fft.InvalidLength(length: length).description == bad[index])
        }
        #expect(ProbeRows.javaList(try Fft.magnitudesDb([0]).map(JavaDouble.toString)) == bad[2])
        #expect(ProbeRows.javaList(try Fft.magnitudesDb([Double](repeating: 0, count: 8)).map(JavaDouble.toString))
            == Self.extra("FFT.zeros")[0][0])
        #expect(ProbeRows.javaList(try Fft.magnitudesDb([1, -1]).map(JavaDouble.toString))
            == Self.extra("FFT.two")[0][0])
    }

    @Test func fftToneMatchesJava() throws {
        let row = Self.extra("FFT.tone750")[0]
        let db = try Fft.magnitudesDb(AudioSignals.tone(750, 2048, 0.5))
        var peak = 0
        for i in 1..<db.count where db[i] > db[peak] {
            peak = i
        }
        #expect(String(peak) == row[0])
        #expect(JavaDouble.toString(Fft.binHz(peak, fftSize: 2048, sampleRate: 12_000)) == row[1])
        // Side lobes around −160 dB are differences of the order of 1e-8 of amplitude: a tolerance in dB, not relative.
        let picked: [Double] = [db[0], db[10], db[peak - 1], db[peak], db[peak + 1], db[500], db[1023]]
        for (got, expected) in zip(picked, row[2...].map(Self.double)) {
            #expect(abs(got - expected) <= 1e-6, "\(got) vs \(expected)")
        }
        let bins = Self.extra("FFT.binHz")[0]
        #expect(JavaDouble.toString(Fft.binHz(0, fftSize: 2048, sampleRate: 12_000)) == bins[0])
        #expect(JavaDouble.toString(Fft.binHz(1, fftSize: 2048, sampleRate: 12_000)) == bins[1])
        #expect(JavaDouble.toString(Fft.binHz(512, fftSize: 2048, sampleRate: 12_000)) == bins[2])
        #expect(JavaDouble.toString(Fft.binHz(3, fftSize: 7, sampleRate: 44_100.5)) == bins[3])
    }

    // MARK: - Waterfall

    @Test func waterfallBinsMatchJava() {
        let row = Self.research("WF.bins")[0]
        let wf = Waterfall(sampleRate: 12_000, maxHz: 3000, rows: 5)
        #expect(String(wf.bins) == row[0])
        #expect(JavaDouble.toString(wf.maxHz) == row[1])
        #expect(String(Waterfall(sampleRate: 12_000, maxHz: 7000, rows: 5).bins) == row[2])
        #expect(String(Waterfall(sampleRate: 12_000, maxHz: 2999.9, rows: 5).bins) == row[3])
        let more = Self.extra("WF.bins")[0]
        let got: [String] = [
            String(Waterfall(sampleRate: 12_000, maxHz: 0, rows: 1).bins),
            String(Waterfall(sampleRate: 12_000, maxHz: -5, rows: 1).bins),
            String(Waterfall(sampleRate: 12_000, maxHz: 5.86, rows: 1).bins),
            String(Waterfall(sampleRate: 48_000, maxHz: 3000, rows: 1).bins),
            String(Waterfall(sampleRate: 12_000, maxHz: 1e300, rows: 1).bins),
            JavaDouble.toString(Waterfall(sampleRate: 12_000, maxHz: 3000, rows: 1).maxHz),
        ]
        #expect(got == more)
    }

    @Test func waterfallToneMatchesJava() {
        let row = Self.extra("WF.tone1200")[0]
        let w = Waterfall(sampleRate: AudioSignals.sampleRate, maxHz: 3000, rows: 50)
        var sig = AudioSignals.tone(1200, 12_000, 0.3)
        for i in sig.indices {
            sig[i] += 0.001 * sin(Double(i) * 7.3)
        }
        let added = w.add(sig)
        let rows = w.normalizedRows()
        let r0 = rows[0]
        var brightest = 0
        for i in 1..<r0.count where r0[i] > r0[brightest] {
            brightest = i
        }
        let bright = r0.filter { $0 > 0 }.count
        let sum = r0.reduce(0.0) { $0 + Double($1) }
        #expect(String(added) == row[0])
        #expect(String(rows.count) == row[1])
        #expect(String(r0.count) == row[2])
        #expect(JavaDouble.toString(w.peakHz(lo: 200, hi: 2800)) == row[3])
        #expect(JavaDouble.toString(w.maxHz) == row[4])
        #expect(String(bright) == row[5])
        #expect(abs(sum - Self.double(row[6])) <= 1e-4, "\(sum)")
        #expect(abs(Double(r0[brightest]) - Self.double(row[7])) <= 1e-6)
        #expect(String(brightest) == row[8])
        #expect(JavaDouble.toString(w.peakHz(lo: 1300, hi: 2800)) == row[9])
        #expect(JavaDouble.toString(w.peakHz(lo: 3000, hi: 4000)) == row[10])
        #expect(JavaDouble.toString(w.peakHz(lo: 1200, hi: 1200)) == row[11])
    }

    /// Window filling, 50% overlap, row cap and an empty model (`WF.sequence`).
    @Test func waterfallSequenceMatchesJava() {
        let small = Waterfall(sampleRate: 12_000, maxHz: 3000, rows: 2)
        var seq: [String] = []
        seq.append(JavaDouble.toString(small.peakHz(lo: 0, hi: 6000)))
        seq.append(String(small.normalizedRows().count))
        seq.append(String(small.add([Double](repeating: 0, count: 2047))))
        seq.append(String(small.add([0])))
        seq.append(String(small.add([Double](repeating: 0, count: 1023))))
        seq.append(String(small.add([0])))
        seq.append(String(small.add(AudioSignals.tone(600, 1024, 0.5))))
        seq.append(String(small.normalizedRows().count))
        seq.append(JavaDouble.toString(small.peakHz(lo: 0, hi: 6000)))
        seq.append(String(small.add([])))
        #expect(ProbeRows.javaList(seq) == Self.extra("WF.sequence")[0][0])
    }

    // MARK: - CwDecoder

    /// The `CwDecoderTest` signals (`CWD.decode` from `research/`) and further speeds, tones, noises and splitting
    /// into blocks (`voice-audio/`): signal length, decoded text and `wpm` exactly.
    ///
    /// The signal fingerprint (column 6) is **not compared**: the noise is bitwise Java (`JavaRandom`), but the tone is
    /// `sin` from Darwin libm, not HotSpot (fdlibm) — the fingerprints differ for all 9 signals, even without noise
    /// (verified). The text and `wpm` must match anyway; bitwise-identical inputs are supplied by the parity suite
    /// as PCM fixtures.
    @Test func cwDecoderMatchesJava() {
        var rows: [[String]] = Self.research("CWD.decode").map { row in
            Array(row[0..<4]) + ["1024"] + Array(row[4...])
        }
        rows += Self.extra("CWD.decode")
        #expect(rows.count == 9)
        for row in rows {
            let signal = AudioSignals.cw(row[0], wpm: Int(row[1])!, tone: Self.double(row[2]), noise: Self.double(row[3]))
            #expect(String(signal.count) == row[5], "\(row)")
            let decoded = AudioSignals.decode(signal, tone: Self.double(row[2]), chunk: Int(row[4])!)
            #expect("'" + decoded.text + "'" == row[7], "\(row)")
            #expect(String(decoded.wpm) == row[8], "\(row)")
        }
    }

    @Test func cwDecoderToneAndFreshStateMatchJava() {
        let signal = AudioSignals.cw("CQ TEST", wpm: 25, tone: 600, noise: 0.01)
        var off = ""
        let mistuned = CwDecoder(sampleRate: 12_000, toneHz: 1500) { off.append($0) }
        mistuned.add(signal)
        var retuned = ""
        let decoder = CwDecoder(sampleRate: 12_000, toneHz: 1500) { retuned.append($0) }
        decoder.setTone(600)
        decoder.add(signal)
        let row = Self.extra("CWD.tone")[0]
        #expect(["'" + off + "'", String(mistuned.wpm()), "'" + retuned + "'", String(decoder.wpm())] == row)
        let fresh = Self.extra("CWD.fresh")[0]
        #expect(String(CwDecoder(sampleRate: 12_000, toneHz: 600) { _ in }.wpm()) == fresh[0])
        #expect(String(CwDecoder(sampleRate: 8_000, toneHz: 600) { _ in }.wpm()) == fresh[1])
    }

    @Test func callsignsMatchJava() {
        #expect(ProbeRows.javaList(CwDecoder.callsigns("CQ TEST OK2XYZ  OK1XOE 5NN 15 TU DL1ABC 599 *E", myCall: "OK1XOE"))
            == Self.research("CWD.callsigns")[0][0])
        for row in Self.extra("CWD.callsigns") {
            let my: String? = row[1] == "<null>" ? nil : row[1]
            #expect(ProbeRows.javaList(CwDecoder.callsigns(row[0], myCall: my)) == row[2], "\(row)")
        }
    }

    // MARK: - ContestRecorder (pure part)

    static func instant(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)!
    }

    @Test func recorderHeaderMatchesJava() {
        let recorder = ContestRecorder(dir: try! JavaPath("/r"), sampleRate: 12_000)
        let rows = Self.research("CR.header")
        #expect(rows.count == 4)
        for row in rows {
            let hex = recorder.header(Int64(row[0])!).map { byte in
                (byte < 16 ? "0" : "") + String(byte, radix: 16)
            }.joined()
            #expect(hex == row[1], "\(row)")
        }
    }

    @Test func recorderFileForMatchesJava() {
        let recorder = ContestRecorder(dir: try! JavaPath("/r"), sampleRate: 12_000)
        let rows = Self.research("CR.fileFor")
        #expect(rows.count == 4)
        for row in rows.dropLast() {
            #expect(recorder.fileFor(Self.instant(row[0])).description == row[1], "\(row)")
        }
        // `+10000-01-01T00:00:00Z` is not read by ISO8601DateFormatter; the instant is composed from the epoch day.
        let year10000 = JavaLocalDate.instant(epochDay: JavaLocalDate.epochDay(year: 10_000, month: 1, day: 1),
                                              secondOfDay: 0)
        #expect(recorder.fileFor(year10000).description == rows[3][1])
    }

    @Test func recorderSegmentMatchesJava() throws {
        let rows = Self.research("CR.segment")
        #expect(rows.count == 4)
        for row in rows {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("cr-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let recorder = ContestRecorder(dir: try JavaPath(dir.path), sampleRate: 12_000)
            let at = Self.instant(row[0])
            #expect(recorder.segment(qsoTime: at, beforeSec: Int32(row[1])!, afterSec: Int32(row[2])!) == nil)
            #expect(FileManager.default.createFile(atPath: recorder.fileFor(at).description, contents: Data(count: 10)))
            let segment = try #require(recorder.segment(qsoTime: at, beforeSec: Int32(row[1])!, afterSec: Int32(row[2])!))
            #expect("\(segment.offsetBytes)+\(segment.lengthBytes)" == row[3], "\(row)")
            #expect(segment.file == recorder.fileFor(at))
        }
    }

    /// `ContestRecorderTest.appendsAfterRestartAndFindsSegment` (segment) — 590 s × 24 000 B.
    @Test func recorderSegmentOverflowsLikeJava() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cr-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = ContestRecorder(dir: try JavaPath(dir.path), sampleRate: 12_000)
        let at = Self.instant("2026-11-28T12:10:00Z")
        FileManager.default.createFile(atPath: recorder.fileFor(at).description, contents: Data())
        let segment = try #require(recorder.segment(qsoTime: at, beforeSec: 10, afterSec: 5))
        #expect(segment.offsetBytes == 590 * 24_000)
        #expect(segment.lengthBytes == 15 * 24_000)
        // `beforeSec + afterSec` is a Java `int`: it overflows before widening to `long`.
        let wrapped = try #require(recorder.segment(qsoTime: at, beforeSec: .max, afterSec: 1))
        #expect(wrapped.lengthBytes == Int64(Int32.min) * 24_000)
        #expect(wrapped.offsetBytes == 0)
    }
}
