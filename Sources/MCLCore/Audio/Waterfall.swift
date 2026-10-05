import Foundation
import os

/// Waterfall model (Java `audio/Waterfall`): assembles sample blocks into FFT windows (50 % overlap), keeps
/// the last N spectrum rows (0 … maxHz) and converts level to brightness 0…1 using an automatic noise
/// threshold (median of the **last** row, 40 dB range). Methods are locked like Java `synchronized`
/// (the audio thread adds, the UI reads).
///
/// `bins = (int) min(1024, ceil(maxHz × 2048 / fs))` — 3000 Hz → 512, 2999.9 → 512, 7000 → 1024,
/// 0 or negative → 0 (`-0.0`), `NaN` → 0. **Divergences only outside UI reach** (the UI gives a fixed 3000 Hz):
/// a negative bin count (`maxHz < −fs/2048`) makes Java throw `NegativeArraySizeException` in `add`, here the
/// rows are empty; `normalizedRows` over empty rows (0 bins) makes Java throw on `latest[0]`, here it returns
/// an empty list; a negative row count (`rows < 0`) makes Java throw `NoSuchElementException` in
/// `history.removeLast()` on an empty deque, here the history stays empty.
public final class Waterfall: Sendable {

    public static let fftSize = 2048

    private struct State {
        var window = [Double](repeating: 0, count: Waterfall.fftSize)
        var filled = 0
        /// Newest first (Java `ArrayDeque.addFirst`).
        var history: [[Double]] = []
    }

    private let sampleRate: Double
    private let rows: Int32
    public let bins: Int32
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// - Parameter maxHz: upper display frequency (e.g. 3000 Hz)
    public init(sampleRate: Double, maxHz: Double, rows: Int32) {
        self.sampleRate = sampleRate
        self.rows = rows
        let fft = Double(Self.fftSize)
        bins = JavaMath.d2i(JavaMath.min(fft / 2, (maxHz * fft / sampleRate).rounded(.up)))
    }

    public var maxHz: Double {
        Fft.binHz(Int(bins), fftSize: Self.fftSize, sampleRate: sampleRate)
    }

    /// Adds samples; returns `true` when a row was added.
    @discardableResult
    public func add(_ samples: [Double]) -> Bool {
        let size = Self.fftSize
        let count = Swift.max(Int(bins), 0)
        let limit = Int(rows)
        return state.withLock { s in
            var added = false
            for sample in samples {
                s.window[s.filled] = sample
                s.filled += 1
                if s.filled == size {
                    // A length of 2048 is a power of two — `magnitudesDb` does not throw.
                    let db = (try? Fft.magnitudesDb(s.window)) ?? []
                    s.history.insert(Array(db[0..<count]), at: 0)
                    while s.history.count > limit && !s.history.isEmpty {
                        s.history.removeLast()
                    }
                    // 50 % window overlap — a smoother waterfall.
                    for i in 0..<(size / 2) {
                        s.window[i] = s.window[size / 2 + i]
                    }
                    s.filled = size / 2
                    added = true
                }
            }
            return added
        }
    }

    /// Rows from newest, values 0…1 (noise ≈ 0, strong signal ≈ 1).
    public func normalizedRows() -> [[Float]] {
        state.withLock { s in
            guard let first = s.history.first, !first.isEmpty else { return [] }
            let latest = first.sorted(by: Self.javaLess)
            let floor = latest[latest.count / 2] // median = noise floor
            let span = 40.0 // dB above noise = full brightness
            return s.history.map { row in
                row.map { value in Float(JavaMath.max(0, JavaMath.min(1, (value - floor) / span))) }
            }
        }
    }

    /// Frequency (Hz) of the strongest signal in the last row within the range lo…hi; `-1` if none.
    public func peakHz(lo loHz: Double, hi hiHz: Double) -> Double {
        state.withLock { s in
            guard let row = s.history.first else { return -1 }
            var best = -1
            for i in row.indices {
                let f = Fft.binHz(i, fftSize: Self.fftSize, sampleRate: sampleRate)
                if f >= loHz && f <= hiHz && (best < 0 || row[i] > row[best]) {
                    best = i
                }
            }
            return best < 0 ? -1 : Fft.binHz(best, fftSize: Self.fftSize, sampleRate: sampleRate)
        }
    }

    /// Order of Java `Arrays.sort(double[])`: `-0.0` before `0.0`, `NaN` at the end.
    private static func javaLess(_ a: Double, _ b: Double) -> Bool {
        if a.isNaN { return false }
        if b.isNaN { return true }
        if a == b { return a.sign == .minus && b.sign == .plus }
        return a < b
    }
}
