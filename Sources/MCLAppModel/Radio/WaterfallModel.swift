import CoreGraphics
import Foundation
import MCLCore
import Observation

/// The waterfall / spectrum display window (`WaterfallWindow.kt`, extended to N1MM+'s Spectrum Display): an FFT of
/// the receiver audio 0–3 kHz as a spectrum pane (instant and decaying levels, the threshold line, the RX and TX
/// lines) above the waterfall, the newest row on top. The hover shows the frequency on the band, a click tunes the
/// rig there (snapped to the nearest signal), Cmd+click sets the split transmit frequency, the wheel moves the
/// levels over the spectrum and tunes over the waterfall.
///
/// The audio queue feeds `Waterfall` (thread-safe); every 100 ms the source's newest line goes through the shared
/// `SpectrumPipeline` and the image is rendered off the main actor (`WaterfallPixels` → a `CGImage`), and both are
/// handed to the view on the main actor. The window holds the receiver audio (`acquire("waterfall")`) while it is
/// open and releases it, with its listener, when it closes. Nothing here transmits: the rig is only tuned.
@Observable @MainActor
public final class WaterfallModel {

    /// The refresh period (`delay(100)`).
    static let refreshMs = 100
    /// The audio user name (`acquireAudio("waterfall")`).
    static let audioUser = "waterfall"

    /// A rendered image handed from the render lane to the main actor.
    struct Rendered: @unchecked Sendable {
        let image: CGImage?
        let picture: SpectrumPicture?
    }

    /// The last rendered image (`nil` = no rows yet: the view shows black).
    public private(set) var image: CGImage?
    /// The last spectrum line to draw (`nil` = nothing yet).
    public private(set) var picture: SpectrumPicture?
    /// The audio error (`nil` = the input runs).
    public private(set) var error: String?
    /// The audio frequency under the pointer (`nil` = the pointer is outside).
    public private(set) var hoverHz: Double?
    /// The frequency on the band under the pointer.
    public private(set) var hoverRfHz: Int64?
    /// The zoom level (N1MM +/-; not saved).
    public private(set) var zoom: Int = 1
    /// The pane layout follows the window's shape (N1MM „Auto" orientation); reported by the view.
    public private(set) var isHorizontal = true
    /// N1MM's CQ button: the recommended CQ frequencies, best first (empty = the markers are off).
    public internal(set) var cqFrequencies: [Double] = []

    /// The spots over the spectrum (telnet and local spots with their dupe / mult state); wired by the app model.
    @ObservationIgnored var spotsProvider: (@MainActor (_ lowHz: Double, _ highHz: Double) -> [SpectrumSpot])?
    /// Puts the `@frequency` spots of unknown signals into the spot buffer (replacing the previous ones); wired by
    /// the app model.
    @ObservationIgnored var publishUnknown: (@MainActor (_ spots: [(call: String, freqHz: Int)]) -> Void)?
    /// Refreshes since the last `@frequency` update (they are published every 2 s).
    @ObservationIgnored var unknownCountdown = 0
    /// The `@frequency` spots are in the buffer (they go when the option or the window does).
    @ObservationIgnored var publishedUnknown = false

    /// The FFT rows (`Waterfall(SAMPLE_RATE, WATERFALL_MAX_HZ, WATERFALL_ROWS)`).
    @ObservationIgnored let waterfall = Waterfall(sampleRate: Double(AudioCapture.sampleRate),
                                                  maxHz: WaterfallPixels.maxHz,
                                                  rows: Int32(WaterfallPixels.rows))
    /// The receiver audio as a spectrum source.
    @ObservationIgnored let audioSource: AudioSpectrumSource
    /// The spectrum lines of external programs over UDP (N1MM 13064).
    @ObservationIgnored let externalSource = ExternalSpectrumSource()
    /// The network ports (the UDP receiver and the relay); wired by the app model, `nil` = none.
    @ObservationIgnored var network: NetworkPorts?
    /// The bound UDP receiver and the address it was bound with.
    @ObservationIgnored var listener: (any UdpListening)?
    @ObservationIgnored var listenerBind: String?
    /// Raised for every bind attempt: a bind that finishes after a newer one (or the close) is dropped.
    @ObservationIgnored var bindGeneration = 0
    /// The lane of the blocking socket work (bind, the relay's sends) — never the main thread.
    @ObservationIgnored let socketQueue = DispatchQueue(label: "spectrum-udp", qos: .utility)
    /// Refreshes until the next relayed line (5 a second).
    @ObservationIgnored var relayCountdown = 0
    /// The UDP receiver could not bind (shown in the info line).
    public internal(set) var receiveError: String?
    /// The external source names heard so far (N1MM's source drop-down).
    public internal(set) var heardSources: [String] = []
    /// The trace, decay and detection shared by every source.
    @ObservationIgnored let pipeline = SpectrumPipeline()
    @ObservationIgnored private let audio: AudioModel
    @ObservationIgnored let rig: RigModel
    @ObservationIgnored let config: ConfigModel
    @ObservationIgnored private let clock: any RescoreClock
    /// One long-lived serial queue for the renders (CPU work only, never the cooperative pool; no thread per render).
    @ObservationIgnored private let renderQueue = DispatchQueue(label: "waterfall-render", qos: .userInitiated)
    @ObservationIgnored private var timer: (any RescoreTimer)?
    @ObservationIgnored private(set) var isOpen = false
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
        audioSource = AudioSpectrumSource(waterfall: waterfall, sampleRate: Double(AudioCapture.sampleRate))
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
        applyNetwork()
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
        withdrawUnknownSpots()
        cqFrequencies = []
        stopReceiving()
        timer?.cancel()
        timer = nil
        hold.release()
    }

    // MARK: - the rig and the options

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

    /// The split transmit frequency the rig reports (`nil` without split).
    public var txHz: Int64? {
        guard let state = rig.activeState, state.split, state.txFreqHz > 0 else { return nil }
        return state.txFreqHz
    }

    /// The display options (N1MM's right-click menu and gear dialog), saved in the configuration.
    public var setup: SpectrumSetup {
        config.config.spectrum
    }

    /// Changes the display options and saves them.
    public func updateSetup(_ change: (inout SpectrumSetup) -> Void) {
        var edited: SpectrumSetup = config.config.spectrum
        change(&edited)
        guard edited != config.config.spectrum else { return }
        config.config.spectrum = edited
        config.saveSilently()
        applyNetwork()
    }

    /// The view's shape (N1MM „Auto" orientation follows it).
    public func layout(width: Double, height: Double) {
        let horizontal: Bool = setup.orientation.isHorizontal(width: width, height: height)
        if horizontal != isHorizontal {
            isHorizontal = horizontal
        }
    }

    /// What the waterfall shows now for the Available window's speaker column; `nil` while the window is closed
    /// (the receiver audio is not held then).
    public func spectrum() -> SignalHeard.Spectrum? {
        guard isOpen else { return nil }
        return SignalHeard.Spectrum(rows: waterfall.latestRows(SignalHeard.rowsToCheck), maxHz: waterfall.maxHz,
                                    dialHz: dialHz, rawMode: rawMode, cwPitch: Int32(clamping: pitchHz))
    }

    // MARK: - the info line

    /// The line above the panes: the audio error, otherwise the hover frequency, otherwise the mode and pitch.
    public var infoLine: (text: EntryStatus, isError: Bool) {
        if let receiveError {
            return (RadioWindowTexts.spectrumReceiveError(receiveError), true)
        }
        if setup.source == .external {
            if let hoverHz = hoverRfHz {
                return (.verbatim(RadioWindowTexts.spectrumHover(rfHz: hoverHz)), false)
            }
            if picture == nil {
                return (RadioWindowTexts.spectrumWaiting(name: setup.text(.externalName),
                                                         receiving: setup.flag(.udpReceive)), false)
            }
            return (RadioWindowTexts.spectrumExternalInfo(name: externalSource.currentName ?? ""), false)
        }
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

    /// The stats box (N1MM: the threshold, the signal count and the Hz per bin): `nil` before the first line.
    public var statsLine: EntryStatus? {
        guard let picture else { return nil }
        return RadioWindowTexts.spectrumStats(floorDb: picture.floorDb, thresholdDb: setup.scale.thresholdDb,
                                              signals: picture.signals.count, hzPerBin: picture.binWidthHz)
    }

    // MARK: - positions

    /// The tuning the source's bins are put on the band with.
    var tuning: SpectrumTuning {
        SpectrumTuning(dialHz: dialHz, rawMode: rawMode, cwPitch: Int32(clamping: pitchHz))
    }

    /// The axis and visible bins now: the last picture's, or (before the first line) the receiver audio's on the
    /// current tuning.
    private var axisAndWindow: (axis: SpectrumFrame, window: Range<Int>) {
        if setup.source == .external, let picture {
            return (picture.axis, picture.window)
        }
        let bins: Int = Int(waterfall.bins)
        let axis: SpectrumFrame = SpectrumFrame.audio(levelsDb: [Double](repeating: 0, count: Swift.max(0, bins)),
                                                      maxHz: waterfall.maxHz, dialHz: tuning.dialHz,
                                                      rawMode: tuning.rawMode, cwPitch: tuning.cwPitch)
        if let picture, picture.axis.startHz == axis.startHz, picture.axis.stepHz == axis.stepHz {
            return (picture.axis, picture.window)
        }
        let center: Double? = axis.bin(ofHz: Double(rxHz))
        return (axis, SpectrumZoom.window(count: bins, zoom: zoom, centerBin: center))
    }

    /// The receive frequency the RX line marks (in CW the CW pitch sits on it).
    var rxHz: Int64 {
        dialHz
    }

    /// The frequency on the band at a position along the frequency axis (0…1).
    public func hz(atFraction fraction: Double) -> Double {
        let current = axisAndWindow
        return current.axis.hz(atBin: SpectrumZoom.bin(atFraction: fraction, window: current.window))
    }

    /// The position of a frequency along the frequency axis (0…1), `nil` when it is not shown.
    public func fraction(ofHz hz: Double) -> Double? {
        let current = axisAndWindow
        guard let bin = current.axis.bin(ofHz: hz) else { return nil }
        return SpectrumZoom.fraction(ofBin: bin, window: current.window)
    }

    /// The yellow RX line (in CW the CW pitch line) as a fraction of the frequency axis, `nil` outside CW (the
    /// receiver audio has no line for the carrier of a sideband).
    public var pitchLine: Double? {
        if setup.source == .external {
            // An SDR shows the band: the RX line is the dial frequency in every mode.
            return dialHz > 0 ? fraction(ofHz: Double(rxHz)) : nil
        }
        guard RadioWindowTexts.showsPitchLine(rawMode: rawMode) else { return nil }
        guard dialHz > 0 else {
            return fraction(ofHz: Double(pitchHz))
        }
        return fraction(ofHz: Double(rxHz))
    }

    /// The x of the pitch line in an image `width` wide (`(pitch / maxHz * width).toFloat()`), `nil` outside CW.
    public func pitchLineX(width: Float) -> Float? {
        guard RadioWindowTexts.showsPitchLine(rawMode: rawMode) else { return nil }
        guard zoom == 1 else {
            return pitchLine.map { Float($0 * Double(width)) }
        }
        return WaterfallPixels.pitchLineX(pitchHz: pitchHz, maxHz: waterfall.maxHz, width: width)
    }

    /// The red TX line of a split as a fraction of the frequency axis, `nil` without split or off the display.
    public var txLine: Double? {
        txHz.flatMap { fraction(ofHz: Double($0)) }
    }

    // MARK: - the pointer

    /// The pointer moved over the image (`x` from the image's left edge, `width` its width).
    public func hover(x: Float, width: Float) {
        hover(fraction: Double(x / width))
    }

    /// The pointer moved to a position along the frequency axis (0…1).
    public func hover(fraction: Double) {
        let hz: Double = hz(atFraction: fraction)
        hoverRfHz = Int64(hz.rounded())
        hoverHz = SignalHeard.audioHz(rfHz: Int64(hz.rounded()), dialHz: dialHz, rawMode: rawMode,
                                      cwPitch: Int32(clamping: pitchHz))
        if dialHz <= 0 {
            hoverHz = hz
        }
    }

    /// The pointer left the image.
    public func hoverEnded() {
        hoverHz = nil
        hoverRfHz = nil
    }

    /// A press on the waterfall image: with a known dial frequency the rig tunes to that audio frequency on the band.
    public func click(x: Float, width: Float) {
        press(fraction: Double(x / width), command: false, inSpectrum: false)
    }

    /// A press at a position along the frequency axis: Cmd (N1MM Ctrl) sets the split transmit frequency there;
    /// otherwise the rig tunes there — in the spectrum pane with „Snap to Signal" onto the centre of the nearest
    /// signal within 2 kHz (N1MM: no snapping in the waterfall). Nothing happens without a dial frequency.
    public func press(fraction: Double, command: Bool, inSpectrum: Bool) {
        let dial: Int64 = dialHz
        guard dial > 0 else { return }
        let hz: Double = hz(atFraction: fraction)
        if command {
            rig.setSplit(Int64(hz.rounded()))
            return
        }
        var target: Double = hz
        if inSpectrum, setup.flag(.snapToSignal), let picture,
           let snapped = SignalDetector.snap(hz, signals: picture.signals) {
            target = snapped
        }
        rig.tuneTo(Int64(target.rounded()))
    }

    /// The mouse wheel over the spectrum pane: the threshold, with Cmd the reference level, with Cmd+Shift the dB
    /// range (N1MM's „strange and mysterious mouse wheel").
    public func wheelLevels(_ steps: Int, target: SpectrumScale.WheelTarget) {
        guard steps != 0 else { return }
        updateSetup { setup in
            setup.scale = setup.scale.wheel(steps, target)
        }
    }

    /// The mouse wheel over the waterfall: tunes the rig by the tuning step of the mode (N1MM Configurer → Other),
    /// with Shift or Cmd ten steps at a time; up = higher.
    public func wheelTune(_ steps: Int, large: Bool) {
        let dial: Int64 = dialHz
        guard steps != 0, dial > 0 else { return }
        let mode: Mode = rig.activeState?.mode ?? .cw
        let step: Int64 = rig.tuneStepHz(mode) * (large ? 10 : 1)
        rig.tuneTo(dial + Int64(steps) * step)
    }

    /// N1MM `+` / `-`.
    public func zoom(by direction: Int) {
        let next: Int = SpectrumZoom.step(zoom, by: direction)
        guard next != zoom else { return }
        zoom = next
        refresh()
    }

    // MARK: - rendering

    /// The pipeline's settings now (the saved options, the zoom and the receive frequency).
    var pipelineSettings: SpectrumPipeline.Settings {
        let setup: SpectrumSetup = self.setup
        return SpectrumPipeline.Settings(scale: setup.scale, decay: setup.decaySpeed,
                                         staticSensitivity: setup.staticSensitivity,
                                         resetOnRetune: setup.flag(.reduceSmearing), zoom: zoom, rxHz: Double(rxHz))
    }

    /// One refresh: the source's newest line through the pipeline and the waterfall rows into an image on the render
    /// queue (one render at a time), the result set on the main actor.
    func refresh() {
        guard !rendering else { return }
        rendering = true
        let source: any SpectrumSource = activeSource
        if setup.source == .external {
            externalSource.select(setup.text(.externalName))
        }
        let pipeline: SpectrumPipeline = self.pipeline
        let tuning: SpectrumTuning = self.tuning
        let setup: SpectrumSetup = self.setup
        let settings = pipelineSettings
        let vertical: Bool = !isHorizontal
        let binZeroAtBottom: Bool = !setup.flag(.reverseScale)
        let started: Int = generation
        renderQueue.async { [weak self] in
            let picture: SpectrumPicture? = pipeline.step(source, tuning: tuning, settings: settings)
            var rows: [[Float]] = source.waterfallRows()
            if let picture, picture.count == rows.first?.count {
                rows = SpectrumPixels.crop(rows, window: picture.window)
            }
            var pixels: WaterfallPixels.Image? = WaterfallPixels.render(rows: rows)
            if vertical, let horizontal = pixels {
                pixels = SpectrumPixels.vertical(horizontal, binZeroAtBottom: binZeroAtBottom)
            }
            let rendered = Rendered(image: pixels.flatMap(Self.cgImage), picture: picture)
            MainHop.post { [weak self] in
                guard let self else { return }
                self.rendering = false
                guard self.generation == started else { return }
                self.image = rendered.image
                if self.picture != rendered.picture {
                    self.picture = rendered.picture
                    self.pictureChanged()
                    self.relayIfDue()
                }
                self.noteHeardSources()
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
