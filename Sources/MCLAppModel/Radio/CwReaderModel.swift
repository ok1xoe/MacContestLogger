import Foundation
import MCLCore
import Observation

/// The CW Reader window (`CwReaderWindow.kt`, DXLog): the receiver audio decoded at the CW pitch; decoded calls go
/// into the call field with a click.
///
/// `CwDecoder` is not thread-safe, so it lives under a lock — the audio queue `add`s the blocks, the
/// window takes the decoded characters (`pending`) and the speed every 150 ms on the main actor. The window holds
/// the receiver audio (`acquire("cwreader")`) while it is open and releases it, with its listener, when it closes.
@Observable @MainActor
public final class CwReaderModel {

    /// `READER_MAX_CHARS`.
    static let maxChars = 2000
    /// The refresh period (`delay(150)`).
    static let refreshMs = 150
    /// The audio user name (`acquireAudio("cwreader")`).
    static let audioUser = "cwreader"

    /// The decoder and the characters it produced, shared with the audio queue.
    final class Decoder: @unchecked Sendable {
        private let lock = NSLock()
        private var decoder: CwDecoder?
        private var pending: String = ""

        init(toneHz: Int) {
            decoder = CwDecoder(sampleRate: Double(AudioCapture.sampleRate), toneHz: Double(toneHz)) { [unowned self] c in
                // Called by `add` with the lock held.
                self.pending.append(c)
            }
        }

        func add(_ samples: [Double]) {
            lock.withLock { decoder?.add(samples) }
        }

        func setTone(_ hz: Int) {
            lock.withLock { decoder?.setTone(Double(hz)) }
        }

        /// The characters decoded since the last call and the current speed.
        func take() -> (chunk: String, wpm: Int) {
            lock.withLock {
                let chunk: String = pending
                pending = ""
                return (chunk, Int(decoder?.wpm() ?? 0))
            }
        }
    }

    /// The decoded text (the last 2000 characters).
    public private(set) var text: String = ""
    public private(set) var wpm: Int = 0
    /// The audio error (`nil` = the input runs).
    public private(set) var error: String?
    /// The tone field (Kotlin `pitchText`, starts with `config.cwPitchHz`).
    public private(set) var pitchText: String

    @ObservationIgnored let decoder: Decoder
    @ObservationIgnored private let audio: AudioModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private let prefill: @MainActor (String) -> Void
    @ObservationIgnored private var timer: (any RescoreTimer)?
    @ObservationIgnored private var isOpen = false
    /// The listener and the audio user (given back on close, or by `deinit` if the model goes without one).
    @ObservationIgnored private let hold: AudioHold

    init(audio: AudioModel, config: ConfigModel, clock: any RescoreClock,
         prefill: @escaping @MainActor (String) -> Void) {
        self.audio = audio
        hold = AudioHold(audio: audio, user: Self.audioUser)
        self.config = config
        self.clock = clock
        self.prefill = prefill
        let pitch: Int = config.config.cwPitchHz
        pitchText = String(pitch)
        decoder = Decoder(toneHz: pitch)
    }

    /// The window opened (`DisposableEffect`): the listener, then the audio (the error shows), and the refresh.
    /// A cancelled opening (the window went before its task ran, or while the input was starting) holds nothing.
    public func open() async {
        guard !isOpen, !Task.isCancelled else { return }
        isOpen = true
        let decoder: Decoder = self.decoder
        hold.listen { samples in
            decoder.add(samples)
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
        timer?.cancel()
        timer = nil
        hold.release()
    }

    /// The tone field changed: digits only (at most 4); a tone in 200…3000 Hz retunes the decoder.
    public func pitchChanged(_ value: String) {
        pitchText = RadioWindowTexts.digits(value, limit: 4)
        if let hz = RadioWindowTexts.readerTone(pitchText) {
            decoder.setTone(hz)
        }
    }

    /// „Vymazat".
    public func clear() {
        text = ""
    }

    /// Up to six decoded calls, newest first, without the own call (`CwDecoder.callsigns(text.takeLast(200), …)`).
    public var calls: [String] {
        let units: [UInt16] = Array(text.utf16.suffix(200))
        let tail: String = String(decoding: units, as: UTF16.self)
        let myCall: String = config.config.station.call
        return Array(CwDecoder.callsigns(tail, myCall: myCall).prefix(6))
    }

    /// A click on a call: it goes into the active window's call field.
    public func take(_ call: String) {
        prefill(call)
    }

    /// One refresh (every 150 ms): the decoded characters appended (the text kept to 2000 characters), the speed.
    func refresh() {
        let taken: (chunk: String, wpm: Int) = decoder.take()
        if !taken.chunk.isEmpty {
            let joined: [UInt16] = Array((text + taken.chunk).utf16)
            text = String(decoding: joined.suffix(Self.maxChars), as: UTF16.self)
        }
        wpm = taken.wpm
    }

    private func schedule() {
        timer = clock.schedule(afterMilliseconds: Self.refreshMs) { [weak self] in
            guard let self, self.isOpen else { return }
            self.refresh()
            self.schedule()
        }
    }
}
