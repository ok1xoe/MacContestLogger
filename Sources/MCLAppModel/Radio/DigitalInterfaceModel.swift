import Foundation
import MCLCore
import Observation

/// The Digital Interface window (`DigitalInterfaceWindow.kt`, N1MM): fldigi's decoded text pulled over XML-RPC and
/// shown here. A click on a call puts it into the call field, a click on another underlined word into the exchange
/// (N1MM „grab", by the contest definition); F1–F12, Enter and Esc go to the active entry window.
///
/// The poll runs every 300 ms on the keyer lane (fldigi's calls share it with the digital keyer); without
/// a modem the window shows a hint and checks again after 1 s. A change of the engine, host or port restarts the loop
/// (Kotlin `LaunchedEffect(digi.engine, digi.fldigiHost, digi.fldigiPort)`): a poll of the old address in flight is
/// dropped by its generation. The loop runs only while the window is open.
@Observable @MainActor
public final class DigitalInterfaceModel {

    /// `DIGI_MAX_CHARS`.
    nonisolated static let maxChars: Int32 = 4000
    /// `DIGI_POLL_MS`.
    static let pollMs = 300
    /// The wait without a modem (`delay(1000)`).
    static let noModemMs = 1000
    /// `DIGI_RECENT_CALLS`.
    static let recentCallCount: Int32 = 8

    /// A key of the window forwarded to the entry window (`DIGI_FUNCTION_KEYS`, Enter, Esc).
    public enum Key: Equatable, Sendable {
        /// F1–F12 (`index` 0…11).
        case function(Int)
        case enter
        case escape
    }

    /// An underlined range of the text: a call, or a word the contest takes as an exchange field.
    public struct Span: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case call(String)
            case exchange(fieldId: String?, value: String)
        }

        /// UTF-16 offsets, `end` exclusive.
        public let start: Int
        public let end: Int
        public let kind: Kind
    }

    struct Dependencies {
        let config: ConfigModel
        let contest: ContestModel
        let digital: DigitalKeyerModel
        let lane: KeyerLane
        let clock: any RescoreClock
        weak var app: AppModel?
    }

    /// The received text (at most 4000 characters).
    public private(set) var text: String = ""
    /// `"modem · trx"` (empty when not known).
    public private(set) var status: String = ""
    /// The error line (no modem, fldigi not answering).
    public private(set) var error: EntryStatus?
    /// The last calls heard (at most 8, in order of first appearance).
    public private(set) var recentCalls: [String] = []

    /// The RX text stream, read on the keyer lane and cleared on the main actor (under its lock).
    final class Stream: @unchecked Sendable {
        private let lock = NSLock()
        private let stream = RxTextStream(maxChars: DigitalInterfaceModel.maxChars)

        func pending(_ rxLength: Int32) -> RxTextStream.Span? {
            lock.withLock { stream.pending(rxLength) }
        }

        func append(_ chunk: String) {
            lock.withLock { stream.append(chunk) }
        }

        var text: String {
            lock.withLock { stream.text }
        }

        func clear() {
            lock.withLock { stream.clear() }
        }
    }

    /// What one poll read from fldigi.
    struct Poll: Sendable {
        let chunk: String?
        let modem: String
        let trx: String
    }

    enum PollResult: Sendable {
        case read(Poll)
        case failed(String?)
    }

    @ObservationIgnored let stream = Stream()
    @ObservationIgnored private let recent = RecentCalls(max: DigitalInterfaceModel.recentCallCount)
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let digital: DigitalKeyerModel
    @ObservationIgnored private let lane: KeyerLane
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var timer: (any RescoreTimer)?
    @ObservationIgnored private var isOpen = false
    @ObservationIgnored private(set) var generation = 0
    @ObservationIgnored private var loopKey: String?
    /// One observation of the configuration at a time (a reopened model does not stack another).
    @ObservationIgnored private var observing = false

    init(_ dependencies: Dependencies) {
        config = dependencies.config
        contest = dependencies.contest
        digital = dependencies.digital
        lane = dependencies.lane
        clock = dependencies.clock
        app = dependencies.app
    }

    /// `myCall`: the own call in upper case (never underlined, never offered).
    private var myCall: String {
        KotlinStrings.uppercase(config.config.station.call)
    }

    /// The loop's key: engine, host and port.
    private var currentKey: String {
        let digi: DigitalConfig = config.config.digital
        return digi.engine.rawValue + "|" + digi.fldigiHost + "|" + String(digi.fldigiPort)
    }

    // MARK: - the loop

    /// The window opened: the poll loop starts.
    public func open() {
        guard !isOpen else { return }
        isOpen = true
        observeConfig()
        restart()
    }

    /// The window closed: the loop stops; a poll in flight is dropped.
    public func close() {
        guard isOpen else { return }
        isOpen = false
        generation += 1
        timer?.cancel()
        timer = nil
    }

    private func restart() {
        generation += 1
        loopKey = currentKey
        timer?.cancel()
        timer = nil
        tick(generation)
    }

    /// Restarts the loop when the engine, host or port changed (any change of the configuration is observed).
    private func observeConfig() {
        guard !observing else { return }
        observing = true
        withObservationTracking {
            _ = config.config.digital
        } onChange: { [weak self] in
            MainHop.post {
                guard let self else { return }
                self.observing = false
                guard self.isOpen else { return }
                if self.currentKey != self.loopKey {
                    self.restart()
                }
                self.observeConfig()
            }
        }
    }

    private func tick(_ started: Int) {
        guard isOpen, started == generation else { return }
        guard digital.ready else {
            error = RadioWindowTexts.digitalNoModem
            status = ""
            schedule(Self.noModemMs, started)
            return
        }
        let host: String = config.config.digital.fldigiHost
        let port: Int = config.config.digital.fldigiPort
        let lane: KeyerLane = self.lane
        let stream: Stream = self.stream
        lane.run({ devices -> PollResult in
            do {
                let client: any FldigiPort = try lane.fldigi(devices, host: host, port: port)
                let length: Int32 = try client.rxLength()
                var chunk: String?
                if let span = stream.pending(length) {
                    let read: String = try client.rxText(start: span.start, length: span.length)
                    stream.append(read)
                    chunk = read
                }
                return .read(Poll(chunk: chunk, modem: try client.modemName(), trx: try client.trxState()))
            } catch {
                return .failed(KeyingErrors.javaMessage(error))
            }
        }, then: { [weak self] result in
            guard let self, self.isOpen, started == self.generation else { return }
            self.apply(result, host: host, port: port)
            self.schedule(Self.pollMs, started)
        })
    }

    private func apply(_ result: PollResult, host: String, port: Int) {
        switch result {
        case .read(let poll):
            if poll.chunk != nil {
                text = stream.text
                let own: String = myCall
                for hit in CallsignScanner.scan(text) where hit.call != own {
                    recent.offer(hit.call)
                }
                recentCalls = recent.calls
            }
            status = RadioWindowTexts.digitalStatus(modem: poll.modem, trx: poll.trx)
            error = nil
        case .failed(let message):
            error = RadioWindowTexts.fldigiUnavailable(host: host, port: port, message: message)
            status = ""
        }
    }

    private func schedule(_ milliseconds: Int, _ started: Int) {
        timer = clock.schedule(afterMilliseconds: milliseconds) { [weak self] in
            self?.tick(started)
        }
    }

    // MARK: - the window's actions

    /// „Vymazat": the text and the recent calls (fldigi's position stays, the old text is not read again).
    public func clear() {
        stream.clear()
        recent.clear()
        text = ""
        recentCalls = []
    }

    /// The underlined ranges: the calls (not the own one), then the words the contest definition takes as an
    /// exchange field — routed by the call on the same line, else by the typed call, against the exchange typed in
    /// the active entry window.
    public var spans: [Span] {
        let own: String = myCall
        var result: [Span] = []
        var taken: Set<Int> = []
        for hit in CallsignScanner.scan(text) where hit.call != own {
            result.append(Span(start: hit.start, end: hit.end, kind: .call(hit.call)))
            taken.insert(hit.start)
        }
        let current: JavaLinkedMap<String> = app?.currentExchange ?? JavaLinkedMap()
        let typed: String = app?.typedCall ?? ""
        for line in TextTokens.byLine(text) {
            let lineCall: String = Self.lineCall(line, own: own) ?? typed
            let fields: [ContestDefinition.ExchangeField] = contest.exchangeFields(call: lineCall)
            result += Self.exchangeSpans(line, taken: taken, fields: fields, current: current)
        }
        return result
    }

    /// The first call on the line that is not the own one (`line.firstNotNullOfOrNull`).
    private static func lineCall(_ line: [TextTokens.Token], own: String) -> String? {
        for token in line {
            if let call = CallsignScanner.scan(token.word).first?.call, call != own {
                return call
            }
        }
        return nil
    }

    /// The words of a line (not a call's start) the contest takes as an exchange field. A broken
    /// `validation.regex` would throw in Kotlin's composition; here the word is not offered.
    private static func exchangeSpans(_ line: [TextTokens.Token], taken: Set<Int>,
                                      fields: [ContestDefinition.ExchangeField],
                                      current: JavaLinkedMap<String>) -> [Span] {
        var spans: [Span] = []
        for token in line where !taken.contains(token.start) {
            guard let grab = try? ExchangeGrab.route(fields, current, token.word) else { continue }
            spans.append(Span(start: token.start, end: token.end,
                              kind: .exchange(fieldId: grab.fieldId, value: grab.value)))
        }
        return spans
    }

    /// A click at a UTF-16 offset of the text: a call goes into the call field, otherwise an exchange word into its
    /// field (calls first, as Kotlin).
    public func tap(offset: Int) {
        let all: [Span] = spans
        let hit: (Span) -> Bool = { offset >= $0.start && offset < $0.end }
        for span in all where hit(span) {
            if case .call(let call) = span.kind {
                app?.prefillCall(call)
                return
            }
        }
        for span in all where hit(span) {
            if case .exchange(let fieldId, let value) = span.kind {
                app?.prefillExchange([(id: fieldId, value: value)])
                return
            }
        }
    }

    /// A click on a recent call.
    public func take(_ call: String) {
        app?.prefillCall(call)
    }

    /// A key of the window (`onPreviewKeyEvent`): F1–F12 fire on the press (Shift = the opposite set), Enter and Esc
    /// on the release; all of them are consumed (`true`) on both, so nothing else in the window sees them.
    public func key(_ key: Key, down: Bool, shift: Bool) -> Bool {
        switch key {
        case .function(let index):
            if down {
                app?.perform(.functionKey(index, opposite: shift))
            }
        case .enter:
            if !down {
                app?.perform(.enter)
            }
        case .escape:
            if !down {
                app?.perform(.stopSending)
            }
        }
        return true
    }
}
