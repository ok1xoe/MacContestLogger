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

    /// A key of the window forwarded to the entry window (`DIGI_FUNCTION_KEYS`, Enter, Esc).
    public enum Key: Equatable, Sendable {
        /// F1–F12 (`index` 0…11).
        case function(Int)
        case enter
        case escape
    }

    /// How the text was clicked (macOS: Option = N1MM Alt).
    public enum Click: Equatable, Sendable {
        case plain
        /// Option+click (N1MM Alt+click): a call goes onto the call stack, the call field stays.
        case stack
        /// Cmd+click (N1MM Ctrl+click — Ctrl+click is the secondary click on macOS): the word goes into the entry
        /// field that has the typing cursor.
        case force
        /// Shift+click (N1MM): the word converted Letters ↔ Figures, then into the entry window.
        case lettersFigures
    }

    /// How a call is coloured: its status as in the bandmap and whether the validity resources know it.
    public struct CallMark: Equatable, Sendable {
        public let color: SpotColorClassifier.SpotColorKey
        /// Not found in the chosen resources (N1MM: yellow).
        public let unverified: Bool
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
        /// Received while the own station transmitted (fldigi's echo): shown dimmed, never grabbed.
        public var transmitted: Bool = false
    }

    struct Dependencies {
        /// 0 = DI1 (VFO A / rig 1), 1 = DI2 (VFO B / rig 2).
        var index: Int = 0
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
    /// The Grab window (N1MM): the calls heard, the next to grab first.
    public var recentCalls: [String] {
        app?.grabList.shown ?? []
    }

    /// The highlighted call of the Grab window.
    public var highlightedCall: String? {
        app?.grabList.highlighted
    }
    /// The ranges of `text` received while transmitting.
    public private(set) var transmittedRanges: [Range<Int>] = []
    /// The pause bar (N1MM): the window shows no new text until it is clicked again (fldigi is still read).
    public private(set) var paused = false
    /// Paused by the pointer over a call with an empty call field (N1MM pause routines).
    public private(set) var hoverPaused = false
    /// N1MM „MouseOver": the word under the pointer.
    public private(set) var mouseOver: String = ""
    /// N1MM „Letters/Figs": the word under the pointer in the other RTTY shift.
    public private(set) var lettersFigs: String = ""

    /// The RX text stream, read on the keyer lane and cleared on the main actor (under its lock).
    final class Stream: @unchecked Sendable {
        private let lock = NSLock()
        private let stream = RxTextStream(maxChars: DigitalInterfaceModel.maxChars)

        func pending(_ rxLength: Int32) -> RxTextStream.Span? {
            lock.withLock { stream.pending(rxLength) }
        }

        func append(_ chunk: String, transmitting: Bool) {
            lock.withLock { stream.append(chunk, transmitting: transmitting) }
        }

        var text: String {
            lock.withLock { stream.text }
        }

        var transmitted: [Range<Int>] {
            lock.withLock { stream.transmitted }
        }

        /// The text, its TX ranges and the units dropped before it, read together.
        var snapshot: (text: String, transmitted: [Range<Int>], dropped: Int) {
            lock.withLock { (stream.text, stream.transmitted, stream.dropped) }
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
        /// The modem's audio frequency (`nil` when fldigi does not answer `modem.get_carrier`).
        var carrier: Int32?
        /// The modem names, read once per session (`nil` = not read in this poll).
        var names: [String]?
        /// AFC, Lock and Rev, read with the names.
        var switches: [FldigiClient.Switch: Bool]?
        /// The new text of every additional RX window (`nil` = nothing new or not answering).
        var extra: [String?] = []
    }

    enum PollResult: Sendable {
        case read(Poll)
        case failed(String?)
    }

    @ObservationIgnored let stream = Stream()
    /// 0 = DI1 (VFO A / rig 1), 1 = DI2 (VFO B / rig 2).
    public let index: Int
    /// The additional RX windows' streams (DI1 only, up to 4).
    @ObservationIgnored let extraStreams: [Stream] = (0..<4).map { _ in Stream() }
    /// The additional RX windows' text (DI1; one per configured endpoint).
    public private(set) var extraTexts: [String] = []
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
    /// fldigi's modem names were asked for in this loop (once per open / address).
    @ObservationIgnored private var namesRead = false
    /// The call Hover Mode took last (it is not taken again while the pointer stays on it).
    @ObservationIgnored private var hoveredCall: String?
    /// The position (in all text ever received) up to which calls were offered to the Grab window.
    @ObservationIgnored private var grabbedUpTo: Int = 0
    /// The received text written to a file (Setup → Output RX window to text file).
    @ObservationIgnored lazy var rxLog: DigitalRxLog? = app.map { DigitalRxLog(dataDir: $0.dataDir) }
    @ObservationIgnored private var markKey: String = ""
    @ObservationIgnored private var markCache: [String: CallMark] = [:]
    @ObservationIgnored private var loggedCalls: Set<String>?
    /// One observation of the configuration at a time (a reopened model does not stack another).
    @ObservationIgnored private var observing = false

    init(_ dependencies: Dependencies) {
        index = dependencies.index
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
        let endpoint = digi.endpoint(index)
        return digi.engine.rawValue + "|" + endpoint.host + "|" + String(endpoint.port) + "|" + extraEndpoints
            .map { $0.host + ":" + String($0.port) }.joined(separator: ",")
    }

    /// The entry window this Digital Interface works with: DI2 the VFO B / rig 2 window, DI1 the main window when
    /// two entry windows are shown, otherwise the active one (N1MM: DI1 follows VFO A / radio 1, DI2 VFO B / radio 2).
    var targetEntry: EntryModel? {
        guard let app else { return nil }
        if index == 1 {
            return app.vfoB.entry
        }
        return app.rig.vfo.twoEntryWindows ? app.entry : (app.activeEntry ?? app.entry)
    }

    /// N1MM Skins, Colors and Fonts for the Digital Interface: font name, text and background colour (`#RRGGBB`,
    /// empty = the system's).
    public var appearance: (font: String, text: String, background: String) {
        let digital: DigitalConfig = config.config.digital
        return (digital.diFontName, digital.diTextColor, digital.diBackgroundColor)
    }

    /// N1MM's TX indicator: with two Digital Interfaces, this one has the transmit focus (its rig is active).
    public var hasTransmitFocus: Bool {
        guard let app, app.rig.vfo.twoEntryWindows else { return index == 0 }
        return app.rig.vfo.activeVfo == index
    }

    /// This window's fldigi state.
    var side: DigitalKeyerModel.Side {
        digital.sides[min(max(index, 0), 1)]
    }

    /// The additional RX windows' endpoints (DI1 only, at most 4).
    var extraEndpoints: [(host: String, port: Int)] {
        guard index == 0 else { return [] }
        return Target.parseAll(config.config.digital.extraRx).prefix(4).map { ($0.host, Int($0.port)) }
    }

    private func prefillExchange(_ values: [(id: String?, value: String)]) {
        var map = JavaLinkedMap<String>()
        for item in values {
            map.put(item.id, item.value)
        }
        targetEntry?.prefillExchange(map)
    }

    // MARK: - the loop

    /// The window opened: the poll loop starts.
    public func open() {
        guard !isOpen else { return }
        isOpen = true
        // `{CLRRX}` clears this window (DI1).
        if index == 0 {
            digital.clearRxWindow = { [weak self] in self?.clear() }
        }
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
        // N1MM applies AutoTRXUpdate only while the window is open.
        digital.sides[index].carrierHz = nil
        if index == 0 {
            digital.clearRxWindow = nil
        }
    }

    private func restart() {
        namesRead = false
        extraTexts = Array(repeating: "", count: extraEndpoints.count)
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
        if index == 0, config.config.digital.rttyRoute.decodes {
            tickTnc(started)
            return
        }
        guard digital.ready else {
            error = RadioWindowTexts.digitalNoModem
            status = ""
            schedule(Self.noModemMs, started)
            return
        }
        let (host, port): (String, Int) = config.config.digital.endpoint(index)
        let lane: KeyerLane = self.lane
        let stream: Stream = self.stream
        let extras: [(host: String, port: Int)] = extraEndpoints
        let extraStreams: [Stream] = self.extraStreams
        let needNames: Bool = !namesRead
        namesRead = true
        lane.run({ devices -> PollResult in
            do {
                let client: any FldigiPort = try lane.fldigi(devices, host: host, port: port)
                let length: Int32 = try client.rxLength()
                var chunk: String?
                if let span = stream.pending(length) {
                    chunk = try client.rxText(start: span.start, length: span.length)
                }
                let modem: String = try client.modemName()
                let trx: String = try client.trxState()
                if let chunk {
                    // Text read while fldigi transmits is its echo of the own transmission (N1MM: no grabbing).
                    stream.append(chunk, transmitting: trx == "TX")
                }
                var poll = Poll(chunk: chunk, modem: modem, trx: trx)
                // N1MM's additional RX windows: more fldigi instances decoding the same audio (a failing one is
                // skipped, it never stops the main window).
                for (slot, extra) in extras.enumerated() where slot < extraStreams.count {
                    guard let other = try? lane.fldigi(devices, host: extra.host, port: extra.port),
                          let length = try? other.rxLength(),
                          let span = extraStreams[slot].pending(length),
                          let read = try? other.rxText(start: span.start, length: span.length) else {
                        poll.extra.append(nil)
                        continue
                    }
                    extraStreams[slot].append(read, transmitting: trx == "TX")
                    poll.extra.append(read)
                }
                poll.carrier = try? client.carrier()
                if needNames {
                    poll.names = try? client.modemNames()
                    var switches: [FldigiClient.Switch: Bool] = [:]
                    for toggle in FldigiClient.Switch.allCases {
                        switches[toggle] = try? client.isOn(toggle)
                    }
                    poll.switches = switches
                }
                return .read(poll)
            } catch {
                return .failed(KeyingErrors.javaMessage(error))
            }
        }, then: { [weak self] result in
            guard let self, self.isOpen, started == self.generation else { return }
            self.apply(result, host: host, port: port)
            self.schedule(Self.pollMs, started)
        })
    }

    /// An external TU/TNC decodes: its serial port's text is the received text (no fldigi).
    private func tickTnc(_ started: Int) {
        let digital: DigitalConfig = config.config.digital
        let path: String = digital.tncPort
        let baud: Int = digital.tncBaud
        let lane: KeyerLane = self.lane
        let stream: Stream = self.stream
        lane.run({ devices -> String?? in
            guard !KotlinStrings.isBlank(path), let link = try? lane.serial(devices, path: path, baud: baud) else {
                return .some(nil)
            }
            let text: String = link.take()
            if !text.isEmpty {
                stream.append(text, transmitting: false)
            }
            return .some(text)
        }, then: { [weak self] result in
            guard let self, self.isOpen, started == self.generation else { return }
            if case .some(let text) = result, let text {
                self.error = nil
                self.status = "TNC · " + path
                if !text.isEmpty {
                    self.received()
                }
            } else {
                self.error = .verbatim("TNC: " + DigitalTexts.noSerialPort)
                self.status = ""
            }
            self.schedule(Self.pollMs, started)
        })
    }

    private func apply(_ result: PollResult, host: String, port: Int) {
        switch result {
        case .read(let poll):
            if let chunk = poll.chunk {
                if config.config.digital.rxOutputToFile {
                    rxLog?.append(chunk, at: Date())
                }
                received()
            }
            status = RadioWindowTexts.digitalStatus(modem: poll.modem, trx: poll.trx)
            error = nil
            digital.sides[index].carrierHz = poll.carrier.map { Int($0) }
            digital.sides[index].modem = poll.modem
            if let names = poll.names, !names.isEmpty {
                digital.sides[index].modemNames = names
            }
            if let switches = poll.switches {
                digital.sides[index].switches = switches
            }
            for (slot, extra) in poll.extra.enumerated() where slot < extraTexts.count {
                if let chunk = extra {
                    extraTexts[slot] = extraStreams[slot].text
                    if config.config.digital.extraRxToGrab {
                        offerCalls(in: extraStreams[slot].text, chunk: chunk)
                    }
                }
            }
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

    /// New text from fldigi: shown unless the window is paused; the calls heard outside the own transmission (and
    /// shown by the validity routines) go to the recent calls.
    private func received() {
        let (full, tx, dropped) = stream.snapshot
        if !isPaused {
            text = full
            transmittedRanges = tx
        }
        // Only calls new since the last poll and already followed by more text (a call at the very end may still
        // grow) go to the Grab window — a cleared Grab window does not fill again with old text.
        let own: String = myCall
        let validity: DigitalCallValidity = DigitalCallValidity.from(config.config.digital.callValidity)
        let length: Int = full.utf16.count
        var seen: Int = grabbedUpTo
        for hit in callHits(full) where hit.end < length && dropped + hit.end > grabbedUpTo {
            seen = max(seen, dropped + hit.end)
            guard hit.call != own, !tx.contains(where: { $0.contains(hit.start) }),
                  validity.highlight(verified: isVerified(hit.call)) != nil else { continue }
            app?.grabList.offer(hit.call)
        }
        grabbedUpTo = seen
    }

    /// The calls of an additional RX window's new text go to the Grab window (N1MM „RX Windows add to Grab window").
    private func offerCalls(in text: String, chunk: String) {
        let own: String = myCall
        let length: Int = chunk.utf16.count
        for hit in CallsignScanner.scan(chunk) where hit.end < length && hit.call != own {
            app?.grabList.offer(hit.call)
        }
    }

    // MARK: - the window's actions

    /// „Vymazat": the text and the recent calls (fldigi's position stays, the old text is not read again).
    public func clear() {
        stream.clear()
        app?.grabList.clear()
        text = ""
        transmittedRanges = []
    }

    // MARK: - transmitting (N1MM TX window, message buttons, text file)

    /// fldigi transmits a held transmission (the TX button / Alt+T).
    public var transmitting: Bool {
        digital.isHolding
    }

    /// The TX / RX buttons (Alt+T).
    public func toggleTransmit() {
        digital.toggleHold()
    }

    /// Text typed in the TX window: while transmitting it goes out at once; otherwise the line is sent as a
    /// message (with the usual return to receive).
    public func typed(_ text: String) {
        guard !text.isEmpty else { return }
        if digital.isHolding {
            digital.typeHeld(text)
        } else {
            digital.send(text, key: -1)
        }
    }

    /// The Digital Interface's message buttons shown (0, 8, 16, 24) with their labels.
    public var buttons: [FunctionKeyMessage] {
        let digi: DigitalConfig = config.config.digital
        return Array(digi.diMessages.prefix(digi.diButtonCount))
    }

    /// A message button pressed: sent from the active entry window (macros, `{LOGTHENPOP}`, the lamp, Esc).
    public func pressButton(_ index: Int) {
        app?.perform(.digitalButton(index), on: targetEntry)
    }

    public func setButtonCount(_ count: Int) {
        config.config.digital.diButtonCount = DigitalConfig.buttonCount(count)
        config.saveSilently()
    }

    /// Setup → Send Text File: the file's text through fldigi (at most 64 kB, line breaks kept).
    public func sendTextFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url), !data.isEmpty, data.count <= 65_536 else { return }
        let text: String = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        digital.send(text, key: -1)
    }

    // MARK: - fldigi's tuning (N1MM Align, AFC, NET, Rev, Lock)

    /// The switch as last read or set (`nil` = unknown).
    public func isOn(_ toggle: FldigiClient.Switch) -> Bool? {
        side.switches[toggle]
    }

    /// A switch button pressed.
    public func toggle(_ toggle: FldigiClient.Switch) {
        digital.set(toggle, !(side.switches[toggle] ?? false), side: index)
    }

    /// NET (fldigi: Lock off).
    public var net: Bool? {
        side.switches[.lock].map { !$0 }
    }

    /// The Align button.
    public func align() {
        targetEntry?.alignDigital()
    }

    /// The Grab button: the highlighted call into a wiped entry window.
    public func grab() {
        targetEntry?.grabFromList()
    }

    /// The window shows no new text (the pause bar or the pointer over a call).
    public var isPaused: Bool {
        paused || hoverPaused
    }

    /// The pause bar clicked: pause, or show everything that arrived meanwhile.
    public func togglePause() {
        paused.toggle()
        resumeIfNeeded()
    }

    private func resumeIfNeeded() {
        guard !isPaused else { return }
        text = stream.text
        transmittedRanges = stream.transmitted
    }

    /// The pointer over the text (`nil` = it left): the MouseOver and Letters/Figs indicators; with Hover Mode a
    /// call goes into the call field; with the pause routines a call under the pointer pauses the window while the
    /// call field is empty.
    public func hover(offset: Int?) {
        let word: TextTokens.Token? = offset.flatMap { wordAt($0) }
        mouseOver = word?.word ?? ""
        lettersFigs = word.map { LettersFigures.convert($0.word) } ?? ""
        let call: String? = offset.flatMap { callAt($0) }
        let digi: DigitalConfig = config.config.digital
        let fieldEmpty: Bool = KotlinStrings.isBlank(targetEntry?.form.call ?? "")
        let pause: Bool = digi.pauseOnCallHover && call != nil && fieldEmpty
        if pause != hoverPaused {
            hoverPaused = pause
            resumeIfNeeded()
        }
        if digi.hoverMode, let call, call != hoveredCall {
            hoveredCall = call
            take(call)
        } else if call == nil {
            hoveredCall = nil
        }
    }

    /// A right click in the text: with N1MM „Rt Click = Return NOT menu" it is Enter (ESM); `false` = not handled.
    @discardableResult
    public func rightClick() -> Bool {
        guard config.config.digital.rightClickReturn else { return false }
        app?.perform(.enter, on: targetEntry)
        return true
    }

    // MARK: - calls and their colours

    /// The calls of a text: whole words that look like a call, and with the garbage search the Master.scp calls
    /// inside other words.
    func callHits(_ text: String) -> [CallsignScanner.Hit] {
        var hits: [CallsignScanner.Hit] = CallsignScanner.scan(text)
        guard config.config.digital.scpGarbageSearch, let scp = app?.callData.scp, scp.size > 0 else { return hits }
        let covered: [Range<Int>] = hits.map { $0.start..<$0.end }
        for token in TextTokens.words(text) where !covered.contains(where: { $0.overlaps(token.start..<token.end) }) {
            guard token.word.uppercased().utf16.count == token.word.utf16.count,
                  let found = ScpGarbageSearch.find(token.word, contains: { scp.contains($0) }) else { continue }
            hits.append(CallsignScanner.Hit(start: token.start + found.start, end: token.start + found.end,
                                            call: found.call))
        }
        return hits.sorted { $0.start < $1.start }
    }

    /// The call under an offset of the shown text (not the own one).
    func callAt(_ offset: Int) -> String? {
        for span in spans where offset >= span.start && offset < span.end {
            if case .call(let call) = span.kind {
                return call
            }
        }
        return nil
    }

    /// The word under an offset of the shown text.
    func wordAt(_ offset: Int) -> TextTokens.Token? {
        TextTokens.words(text).first { offset >= $0.start && offset < $0.end }
    }

    /// The colour of a call (N1MM: the bandmap's colours by dupe and new multipliers; yellow when the validity
    /// resources do not know it). Cached until the log, the analysis, the resources or the band and mode change.
    public func mark(for call: String) -> CallMark {
        let key: String = markEpoch
        if key != markKey {
            markKey = key
            markCache = [:]
            loggedCalls = nil
        }
        if let cached = markCache[call] {
            return cached
        }
        var color: SpotColorClassifier.SpotColorKey = .good
        if let app {
            let entry: EntryModel = targetEntry ?? app.entry
            let status: SpotStatus = app.spotAnalysis.current().callStatus(
                call: call, freqHz: Int(clamping: entry.form.freqHz), mode: entry.form.mode.rawValue)
            color = SpotColorClassifier.classify(dupe: status.dupe, newMultCount: status.newMultCount)
        }
        let validity: DigitalCallValidity = DigitalCallValidity.from(config.config.digital.callValidity)
        let mark = CallMark(color: color, unverified: validity.highlight(verified: isVerified(call)) ?? true)
        markCache[call] = mark
        return mark
    }

    /// What invalidates the cached marks.
    private var markEpoch: String {
        guard let app else { return "" }
        let entry: EntryModel = targetEntry ?? app.entry
        return [String(app.logbook.rows.count), String(app.spotAnalysis.revision), String(app.callData.scpRevision),
                String(app.callData.callHistoryRevision), entry.band?.adif ?? "", entry.form.mode.rawValue,
                config.config.digital.callValidity].joined(separator: "|")
    }

    /// The call is in one of the chosen resources: Master.scp, the call history, the spots, this log.
    func isVerified(_ call: String) -> Bool {
        guard let app else { return true }
        let digi: DigitalConfig = config.config.digital
        if digi.validateScp && app.callData.scp.contains(call) {
            return true
        }
        if digi.validateCallHistory && app.callData.callHistory.lookup(call) != nil {
            return true
        }
        if digi.validateSpotted && app.dxCluster.spots.find(call) != nil {
            return true
        }
        if digi.validateLogged {
            if loggedCalls == nil {
                loggedCalls = Set(app.logbook.rows.map { KotlinStrings.uppercase($0.call) })
            }
            if loggedCalls?.contains(call) == true {
                return true
            }
        }
        return false
    }

    /// The underlined ranges: the calls (not the own one), then the words the contest definition takes as an
    /// exchange field — routed by the call on the same line, else by the typed call, against the exchange typed in
    /// the active entry window.
    public var spans: [Span] {
        let own: String = myCall
        var result: [Span] = []
        var taken: [Range<Int>] = []
        let validity: DigitalCallValidity = DigitalCallValidity.from(config.config.digital.callValidity)
        let tx: [Range<Int>] = transmittedRanges
        for hit in callHits(text) where hit.call != own {
            guard validity.highlight(verified: isVerified(hit.call)) != nil else { continue }
            result.append(Span(start: hit.start, end: hit.end, kind: .call(hit.call),
                               transmitted: tx.contains { $0.contains(hit.start) }))
            taken.append(hit.start..<hit.end)
        }
        let current: JavaLinkedMap<String> = targetEntry?.form.contestExchange ?? JavaLinkedMap()
        let typed: String = targetEntry?.form.call ?? ""
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
    private static func exchangeSpans(_ line: [TextTokens.Token], taken: [Range<Int>],
                                      fields: [ContestDefinition.ExchangeField],
                                      current: JavaLinkedMap<String>) -> [Span] {
        var spans: [Span] = []
        for token in line where !taken.contains(where: { $0.overlaps(token.start..<token.end) }) {
            guard let grab = try? ExchangeGrab.route(fields, current, token.word) else { continue }
            spans.append(Span(start: token.start, end: token.end,
                              kind: .exchange(fieldId: grab.fieldId, value: grab.value)))
        }
        return spans
    }

    /// A click at a UTF-16 offset of the text: a call goes into the call field, otherwise an exchange word into its
    /// field (calls first, as Kotlin).
    public func tap(offset: Int, click: Click = .plain) {
        switch click {
        case .force:
            if let word = wordAt(offset) {
                targetEntry?.insertIntoFocusedField(word.word)
            }
            return
        case .lettersFigures:
            if let word = wordAt(offset) {
                takeConverted(LettersFigures.convert(word.word))
            }
            return
        case .plain, .stack:
            break
        }
        let all: [Span] = spans
        let hit: (Span) -> Bool = { offset >= $0.start && offset < $0.end }
        for span in all where hit(span) {
            if case .call(let call) = span.kind {
                take(call, click: click)
                return
            }
        }
        for span in all where hit(span) {
            if case .exchange(let fieldId, let value) = span.kind {
                prefillExchange([(id: fieldId, value: value)])
                return
            }
        }
    }

    /// A click on a call (in the text or in the recent calls). Option+click stacks it. With Digital Call Stacking on,
    /// in Run, a plain click while the call field holds another call stacks one of them instead of replacing it
    /// (N1MM): FIFO the clicked call, LIFO the call in the field (the clicked one goes into the field).
    public func take(_ call: String, click: Click = .plain) {
        guard let app, let target = targetEntry else { return }
        // N1MM: a call taken from the text leaves the Grab window.
        app.grabList.remove(call)
        if click == .stack {
            app.callStack?.push(call)
            return
        }
        defer {
            // N1MM „Send Space on Callsign Mouse Click": the cursor moves on to the exchange.
            if config.config.digital.sendSpaceOnClick, CallStack.normalize(target.form.call) == CallStack.normalize(call) {
                target.jumpToExchange()
            }
        }
        let typed: String = CallStack.normalize(target.form.call)
        let stacking: Bool = config.config.digital.digitalCallStacking && app.operating.isRun
        guard stacking, !typed.isEmpty, typed != CallStack.normalize(call), let stack = app.callStack else {
            target.prefillCall(call)
            return
        }
        if CallStack.Order.from(config.config.esm.callStackOrder) == .lifo {
            if stack.push(typed) {
                target.prefillCall(call)
            }
        } else {
            stack.push(call)
        }
    }

    /// A Shift+clicked word after the Letters/Figures conversion: a call into the call field, an exchange word into
    /// its field, anything else into the field with the typing cursor.
    private func takeConverted(_ word: String) {
        guard let target = targetEntry else { return }
        if let call = CallsignScanner.scan(word).first?.call, call.utf16.count == word.utf16.count {
            take(call)
            return
        }
        let fields: [ContestDefinition.ExchangeField] = contest.exchangeFields(call: target.form.call)
        if let grab = try? ExchangeGrab.route(fields, target.form.contestExchange, word) {
            prefillExchange([(id: grab.fieldId, value: grab.value)])
            return
        }
        target.insertIntoFocusedField(word)
    }

    // MARK: - frequency and modem

    /// The caption's frequency (N1MM shows the exact frequency): the transmitted frequency (dial ± audio in a
    /// sideband mode with AutoTRXUpdate) and the audio frequency; `""` without a rig frequency.
    public var frequencyCaption: String {
        guard let app, let target = targetEntry else { return "" }
        let state: RigState? = app.rig.vfo.twoEntryWindows ? app.rig.snapshot(vfo: index).state : app.rig.activeState
        let dial: Int64 = state?.freqHz ?? target.form.freqHz
        // N1MM „Display Radio Freq and not Exact Freq in DI Caption".
        let transmit: Int64 = config.config.digital.captionRadioFrequency
            ? dial : digital.transmitHz(dialHz: dial, rawMode: state?.rawMode, side: index)
        return DigitalTexts.frequencyCaption(transmitHz: transmit, carrierHz: side.carrierHz)
    }

    /// The modems of the Op Mode menu: the contest ones first (RTTY, PSK, CW as fldigi names them), then the rest.
    public var opModes: (common: [String], other: [String]) {
        let names: [String] = side.modemNames
        let preferred: [String] = ["RTTY", "BPSK31", "BPSK63", "BPSK125", "QPSK31", "QPSK63", "CW"]
        let common: [String] = names.isEmpty ? preferred : preferred.filter { names.contains($0) }
        return (common, names.filter { !common.contains($0) })
    }

    /// The current modem (fldigi's answer).
    public var currentModem: String {
        side.modem
    }

    /// N1MM Op Mode: switches fldigi's modem; RTTY/PSK modems put the active entry window into that mode too.
    public func selectModem(_ name: String) {
        digital.setModem(name, side: index)
        guard let entry = targetEntry, !entry.modeLocked else { return }
        let upper: String = KotlinStrings.uppercase(name)
        if upper.hasPrefix("RTTY") && entry.form.mode != .rtty {
            entry.setMode(.rtty)
        } else if upper.contains("PSK") && entry.form.mode != .psk {
            entry.setMode(.psk)
        }
    }

    // MARK: - Setup menu

    /// N1MM Setup → Digital Call Stacking: `nil` = disabled, else the order calls come off the stack (shared with
    /// the CW/SSB stack, Settings → Function Keys).
    public var digitalCallStacking: CallStack.Order? {
        config.config.digital.digitalCallStacking ? CallStack.Order.from(config.config.esm.callStackOrder) : nil
    }

    /// N1MM Setup → Turn AutoTRXUpdate On/Off.
    public var autoTrxUpdate: Bool {
        config.config.digital.autoTrxUpdate
    }

    public func setAutoTrxUpdate(_ on: Bool) {
        config.config.digital.autoTrxUpdate = on
        config.saveSilently()
    }

    /// A switch of the window's Setup menu (saved at once).
    public func option(_ path: WritableKeyPath<DigitalConfig, Bool>) -> Bool {
        config.config.digital[keyPath: path]
    }

    public func setOption(_ path: WritableKeyPath<DigitalConfig, Bool>, _ on: Bool) {
        config.config.digital[keyPath: path] = on
        config.saveSilently()
        if path == \DigitalConfig.pauseOnCallHover && !on && hoverPaused {
            hoverPaused = false
            resumeIfNeeded()
        }
    }

    /// N1MM Callsign Validity and Highlight.
    public var callValidity: DigitalCallValidity {
        DigitalCallValidity.from(config.config.digital.callValidity)
    }

    public func setCallValidity(_ validity: DigitalCallValidity) {
        config.config.digital.callValidity = validity.rawValue
        config.saveSilently()
    }

    /// Chooses Digital Call Stacking (`nil` = disable); saved at once.
    public func setDigitalCallStacking(_ order: CallStack.Order?) {
        config.config.digital.digitalCallStacking = order != nil
        if let order {
            config.config.esm.callStackOrder = order.rawValue
        }
        config.saveSilently()
    }

    /// A key of the window (`onPreviewKeyEvent`): F1–F12 fire on the press (Shift = the opposite set), Enter and Esc
    /// on the release; all of them are consumed (`true`) on both, so nothing else in the window sees them.
    public func key(_ key: Key, down: Bool, shift: Bool) -> Bool {
        switch key {
        case .function(let index):
            if down {
                app?.perform(.functionKey(index, opposite: shift), on: targetEntry)
            }
        case .enter:
            if !down {
                app?.perform(.enter, on: targetEntry)
            }
        case .escape:
            if !down {
                app?.perform(.stopSending, on: targetEntry)
            }
        }
        return true
    }
}
