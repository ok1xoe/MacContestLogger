import CoreGraphics
import Foundation
import MCLCore
import Observation

/// The waterfall window (`WaterfallWindow.kt`): an FFT of the receiver audio 0–3 kHz, the newest row on top. The
/// hover shows the frequency on the band, a click tunes the rig there (in CW onto the CW pitch).
///
/// The audio queue feeds `Waterfall` (thread-safe), every 100 ms the image is rendered off the main
/// actor (`WaterfallPixels` → a `CGImage`) and only handed to the view on the main actor. The window holds the
/// receiver audio (`acquire("waterfall")`) while it is open and releases it, with its listener, when it closes.
@Observable @MainActor
public final class WaterfallModel {

    /// The refresh period (`delay(100)`).
    static let refreshMs = 100
    /// The audio user name (`acquireAudio("waterfall")`).
    static let audioUser = "waterfall"

    /// A rendered image handed from the render lane to the main actor.
    struct Rendered: @unchecked Sendable {
        let image: CGImage?
    }

    /// The last rendered image (`nil` = no rows yet: the view shows black).
    public private(set) var image: CGImage?
    /// The audio error (`nil` = the input runs).
    public private(set) var error: String?
    /// The audio frequency under the pointer (`nil` = the pointer is outside).
    public private(set) var hoverHz: Double?

    /// The FFT rows (`Waterfall(SAMPLE_RATE, WATERFALL_MAX_HZ, WATERFALL_ROWS)`).
    @ObservationIgnored let waterfall = Waterfall(sampleRate: Double(AudioCapture.sampleRate),
                                                  maxHz: WaterfallPixels.maxHz,
                                                  rows: Int32(WaterfallPixels.rows))
    @ObservationIgnored private let audio: AudioModel
    @ObservationIgnored private let rig: RigModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let clock: any RescoreClock
    /// One long-lived serial queue for the renders (CPU work only, never the cooperative pool; no thread per render).
    @ObservationIgnored private let renderQueue = DispatchQueue(label: "waterfall-render", qos: .userInitiated)
    @ObservationIgnored private var timer: (any RescoreTimer)?
    @ObservationIgnored private var isOpen = false
    /// The listener and the audio user (given back on close, or by `deinit` if the model goes without one).
    @ObservationIgnored private let hold: AudioHold
    @ObservationIgnored private var rendering = false
    /// Raised by `close`: a render still on the lane does not set the image of a closed window.
    @ObservationIgnored private var generation = 0

    init(audio: AudioModel, rig: RigModel, config: ConfigModel, clock: any RescoreClock) {
        self.audio = audio
        hold = AudioHold(audio: audio, user: Self.audioUser)
        self.rig = rig
        self.config = config
        self.clock = clock
    }

    /// The window opened (`DisposableEffect`): the listener, then the audio (the error shows), and the refresh.
    /// A cancelled opening (the window went before its task ran, or while the input was starting) holds nothing.
    public func open() async {
        guard !isOpen, !Task.isCancelled else { return }
        isOpen = true
        let waterfall: Waterfall = self.waterfall
        hold.listen { samples in
            _ = waterfall.add(samples)
        }
        schedule()
        hold.willAcquire()
        let failure: String? = await audio.acquire(Self.audioUser)
        guard isOpen else {
            // Closed while the input was being acquired: a registration that landed after the close goes again.
            if failure == nil {
                audio.release(Self.audioUser)
            }
            return
        }
        guard !Task.isCancelled else {
            close()
            return
        }
        error = failure
    }

    /// The window closed: the listener goes, the audio is released, the refresh stops.
    public func close() {
        guard isOpen else { return }
        isOpen = false
        generation += 1
        timer?.cancel()
        timer = nil
        hold.release()
    }

    // MARK: - the info line, hover and click

    /// `state.cat.state?.freqHz() ?: state.tunedFreqHz`.
    public var dialHz: Int64 {
        rig.activeState?.freqHz ?? rig.tuning.tunedFreqHz
    }

    /// `state.cat.state?.rawMode() ?: ""`.
    public var rawMode: String {
        rig.activeState?.rawMode ?? ""
    }

    /// `config.cwPitchHz`.
    public var pitchHz: Int {
        config.config.cwPitchHz
    }

    /// The line above the image: the audio error, otherwise the hover frequency, otherwise the mode and pitch.
    public var infoLine: (text: EntryStatus, isError: Bool) {
        if let error {
            return (RadioWindowTexts.waterfallError(error), true)
        }
        if let hoverHz {
            let rf: Int64 = AudioToRf.rfHz(dialHz: dialHz, rawMode: rawMode, audioHz: hoverHz,
                                           cwPitch: Int32(clamping: pitchHz))
            return (.verbatim(RadioWindowTexts.waterfallHover(audioHz: hoverHz, rfHz: rf)), false)
        }
        return (RadioWindowTexts.waterfallInfo(rawMode: rawMode, pitchHz: pitchHz), false)
    }

    /// The pointer moved over the image (`x` from the image's left edge, `width` its width).
    public func hover(x: Float, width: Float) {
        hoverHz = WaterfallPixels.audioHz(x: x, width: width, maxHz: waterfall.maxHz)
    }

    /// The pointer left the image.
    public func hoverEnded() {
        hoverHz = nil
    }

    /// A press on the image: with a known dial frequency the rig tunes to that audio frequency on the band.
    public func click(x: Float, width: Float) {
        let hz: Double = WaterfallPixels.audioHz(x: x, width: width, maxHz: waterfall.maxHz)
        let dial: Int64 = dialHz
        guard dial > 0 else { return }
        rig.tuneTo(AudioToRf.rfHz(dialHz: dial, rawMode: rawMode, audioHz: hz, cwPitch: Int32(clamping: pitchHz)))
    }

    /// The yellow CW pitch line as a fraction of the width (`pitch / model.maxHz()`), `nil` outside CW.
    public var pitchLine: Double? {
        guard RadioWindowTexts.showsPitchLine(rawMode: rawMode) else { return nil }
        return Double(pitchHz) / waterfall.maxHz
    }

    /// The x of the pitch line in an image `width` wide (`(pitch / maxHz * width).toFloat()`), `nil` outside CW.
    public func pitchLineX(width: Float) -> Float? {
        guard RadioWindowTexts.showsPitchLine(rawMode: rawMode) else { return nil }
        return WaterfallPixels.pitchLineX(pitchHz: pitchHz, maxHz: waterfall.maxHz, width: width)
    }

    // MARK: - rendering

    /// One refresh: the rows are rendered on the render queue (one render at a time), the image set on the main actor.
    func refresh() {
        guard !rendering else { return }
        rendering = true
        let waterfall: Waterfall = self.waterfall
        let started: Int = generation
        renderQueue.async { [weak self] in
            let pixels: WaterfallPixels.Image? = WaterfallPixels.render(rows: waterfall.normalizedRows())
            let rendered = Rendered(image: pixels.flatMap(Self.cgImage))
            MainHop.post { [weak self] in
                guard let self else { return }
                self.rendering = false
                guard self.generation == started else { return }
                self.image = rendered.image
            }
        }
    }

    /// Waits for the renders queued before (tests); their results then follow on the main queue.
    func settle() async {
        let queue: DispatchQueue = renderQueue
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                continuation.resume()
            }
        }
    }

    private func schedule() {
        timer = clock.schedule(afterMilliseconds: Self.refreshMs) { [weak self] in
            guard let self, self.isOpen else { return }
            self.refresh()
            self.schedule()
        }
    }

    /// `0x00RRGGBB` pixels (row-major from the top) as an sRGB `CGImage` (`BufferedImage.TYPE_INT_RGB`): 32-bit
    /// little-endian words (the host order of every Mac) with the unused high byte skipped.
    nonisolated static func cgImage(_ image: WaterfallPixels.Image) -> CGImage? {
        guard image.width > 0, image.height > 0, image.pixels.count == image.width * image.height else { return nil }
        let data: Data = image.pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.noneSkipFirst.rawValue)
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: image.width * 4, space: srgb, bitmapInfo: info,
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
