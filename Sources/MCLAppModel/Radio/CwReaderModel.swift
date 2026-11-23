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

    /// What a click on a word of the text needs from the entry window this reader feeds: the received exchange fields
    /// of the contest for a call, the call typed in the window, the exchange typed so far and where a word goes.
    struct ExchangeAccess {
        let fields: @MainActor (String) -> [ContestDefinition.ExchangeField]
        let typedCall: @MainActor () -> String
        let current: @MainActor () -> JavaLinkedMap<String>
        let prefill: @MainActor ([(id: String?, value: String)]) -> Void
    }

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
    /// N1MM "pause scrolling": the window keeps showing `frozenText` (and stops scrolling) while decoding goes on.
    public private(set) var scrollPaused = false
    /// The text shown when scrolling was paused.
    public private(set) var frozenText: String = ""
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
    @ObservationIgnored private let exchange: ExchangeAccess?
    @ObservationIgnored private var timer: (any RescoreTimer)?
    @ObservationIgnored private var isOpen = false
    /// The listener and the audio user (given back on close, or by `deinit` if the model goes without one).
    @ObservationIgnored private let hold: AudioHold

    init(audio: AudioModel, config: ConfigModel, clock: any RescoreClock,
         exchange: ExchangeAccess? = nil, prefill: @escaping @MainActor (String) -> Void) {
        self.audio = audio
        self.exchange = exchange
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
        frozenText = ""
    }

    /// The text the window shows: the frozen one while scrolling is paused.
    public var shownText: String {
        scrollPaused ? frozenText : text
    }

    /// N1MM "pause scrolling" on / off: paused, the shown text stays as it is (to read or click a call) while the
    /// decoder goes on; resumed, the window jumps to the current text.
    public func toggleScrollPause() {
        scrollPaused.toggle()
        frozenText = scrollPaused ? text : ""
    }

    /// Up to six decoded calls of the shown text, newest first, without the own call (`CwDecoder.callsigns(text.takeLast(200), …)`).
    public var calls: [String] {
        let units: [UInt16] = Array(shownText.utf16.suffix(200))
        let tail: String = String(decoding: units, as: UTF16.self)
        let myCall: String = config.config.station.call
        return Array(CwDecoder.callsigns(tail, myCall: myCall).prefix(6))
    }

    /// A click on a call: it goes into the active window's call field.
    public func take(_ call: String) {
        prefill(call)
    }

    /// The underlined ranges of the shown text: the calls (not the own one) and, while a contest is active, the words
    /// its definition takes as a received exchange field. The exchange is routed by the call typed in the window, else
    /// by the last call before the word (a CW exchange follows the call it belongs to).
    public var spans: [DigitalInterfaceModel.Span] {
        let text: String = shownText
        let own: String = KotlinStrings.uppercase(config.config.station.call)
        let hits: [CallsignScanner.Hit] = CallsignScanner.scan(text).filter { $0.call != own }
        var result: [DigitalInterfaceModel.Span] = hits.map {
            DigitalInterfaceModel.Span(start: $0.start, end: $0.end, kind: .call($0.call))
        }
        guard let exchange else { return result }
        let taken: [Range<Int>] = hits.map { $0.start..<$0.end }
        let typed: String = exchange.typedCall()
        let current: JavaLinkedMap<String> = exchange.current()
        var fieldsByCall: [String: [ContestDefinition.ExchangeField]] = [:]
        for token in TextTokens.words(text) where !taken.contains(where: { $0.overlaps(token.start..<token.end) }) {
            let call: String = typed.isEmpty ? (hits.last { $0.end <= token.start }?.call ?? "") : typed
            let fields: [ContestDefinition.ExchangeField]
            if let cached = fieldsByCall[call] {
                fields = cached
            } else {
                fields = exchange.fields(call)
                fieldsByCall[call] = fields
            }
            guard let grab = try? ExchangeGrab.route(fields, current, token.word) else { continue }
            result.append(DigitalInterfaceModel.Span(start: token.start, end: token.end,
                                                     kind: .exchange(fieldId: grab.fieldId, value: grab.value)))
        }
        return result
    }

    /// A click at a UTF-16 offset of the shown text: a call goes into the call field, otherwise an exchange word into
    /// its field (calls first, as in the Digital Interface).
    public func tap(offset: Int) {
        let all: [DigitalInterfaceModel.Span] = spans
        for span in all where offset >= span.start && offset < span.end {
            if case .call(let call) = span.kind {
                take(call)
                return
            }
        }
        for span in all where offset >= span.start && offset < span.end {
            if case .exchange(let fieldId, let value) = span.kind {
                exchange?.prefill([(id: fieldId, value: value)])
                return
            }
        }
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
