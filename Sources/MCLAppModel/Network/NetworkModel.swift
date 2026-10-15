import Foundation
import MCLCore
import Observation

/// The multi-op messages of v1.1.1 (`AppState` `chatLines`, `chatUnread`, `passPending`, `stackedCalls`, `sendChat`,
/// `startPass`, `passCall`, `stackCall`, `popStackedCall`, `onNetMessage`, `AS:2955-3108`) over the cluster session:
/// chat, PASS (a call handed to a station, which gets it into its band map) and the partner's call stack. The
/// decisions are `NetMessages` of the core; this model sends on the sync lane, takes the replies back on the main
/// actor, shows the status lines and puts a passed call into the spot buffer.
@Observable @MainActor
public final class NetworkModel {

    /// The chat lines, the unread count, the call stack and the call waiting to be passed.
    public private(set) var chat = NetMessages()

    /// The call waiting to be passed (the network status window offers a „Předat" button per station).
    public var passPending: String {
        get { chat.passPending }
        set { chat.passPending = newValue }
    }

    /// The pass frequency this station announced last (Alt+Z), 0 = none.
    public private(set) var ownPassFrequencyHz: Int = 0

    /// `{LASTPASSEDFREQ}`: the frequency of the station last alerted to expect a pass (`{PASS …}`, a PASS sent), 0 =
    /// none.
    public var lastPassedFreqHz: Int = 0

    /// The message trace, the stations' setups and the master's time (Network Status Messages / Actions).
    public internal(set) var tools = NetworkToolsState()

    @ObservationIgnored let cluster: ClusterSyncModel
    @ObservationIgnored let status: StatusModel
    @ObservationIgnored let language: LanguageModel
    @ObservationIgnored private let spots: SpotBuffer
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let config: ConfigModel
    @ObservationIgnored let logbook: LogbookModel
    /// Kotlin `prefillCall = …`: the call goes into the active entry window; set by the app.
    @ObservationIgnored var prefillCall: @MainActor (String) -> Void = { _ in }
    /// Kotlin `showNetStatus = true`: the network status window opens; set by the app.
    @ObservationIgnored var openStatusWindow: @MainActor () -> Void = {}
    /// Whether the chat window is open (set by the app): Kotlin zeroes `chatUnread` as a side effect of drawing the
    /// window (`LaunchedEffect(chatLines.size)`), so a line that arrives while it is open is read at once.
    @ObservationIgnored var isChatOpen: @MainActor () -> Bool = { false }
    /// The station's call stack takes a partner's STACK call (set by the app); without it the calls stay in
    /// `chat.stack`.
    @ObservationIgnored var stackReceived: (@MainActor (String) -> Void)?
    /// This station's setup for the others (version, contest, category, master); set by the app.
    /// Wipes the entry windows holding this call (N1MM: the partner's call is wiped once the stack target logs it);
    /// set by the app.
    @ObservationIgnored var wipeCall: @MainActor (String) -> Void = { _ in }
    /// Calls this station put on another station's stack, by call → target station.
    @ObservationIgnored var stackedCalls: [String: String] = [:]
    @ObservationIgnored var ownProfile: @MainActor () -> StationProfile = { StationProfile() }
    /// The alert of a call for help (the system beep; silent in tests); set by the app.
    @ObservationIgnored var alert: @MainActor () -> Void = {}
    /// The offset this station's QSO times are corrected by (ms; the master adds it to the time it hands out).
    @ObservationIgnored var ownClockOffsetMs: @MainActor () -> Int64 = { 0 }

    public init(cluster: ClusterSyncModel, status: StatusModel, language: LanguageModel, spots: SpotBuffer,
                config: ConfigModel, logbook: LogbookModel, now: @escaping @Sendable () -> Date) {
        self.config = config
        self.logbook = logbook
        self.cluster = cluster
        self.status = status
        self.language = language
        self.spots = spots
        self.now = now
        cluster.onMessage = { [weak self] message in
            self?.receive(message)
        }
        cluster.onSent = { [weak self] message in
            self?.traceSent(message)
        }
        cluster.onConnected = { [weak self] in
            self?.connected()
        }
        cluster.onTick = { [weak self] in
            self?.tick()
        }
        cluster.remoteQsoObservers.append { [weak self] qsos in
            self?.remoteLogged(qsos)
        }
    }

    private var instant: JavaInstant {
        JavaInstant(date: now())
    }

    func show(_ message: EntryStatus) {
        status.showJoined(message.parts, separator: "")
    }

    private func peers() -> [StationNetwork.Peer]? {
        cluster.stationNetwork?.peers()
    }

    private func ownFrequency() -> Int {
        cluster.sources.catFreqHz() ?? cluster.sources.tunedFreqHz()
    }

    // MARK: - receiving

    /// `onNetMessage`: CHAT, STACK, PASS and the other types into the lines, the stack and the status; a PASS with a
    /// frequency into the spot buffer.
    func receive(_ message: NetMessageWire) {
        traceReceived(message)
        if receiveTool(message) {
            return
        }
        let effects: [NetEffect] = chat.receive(message, catFreqHz: cluster.sources.catFreqHz(),
                                                tunedHz: cluster.sources.tunedFreqHz(), now: instant)
        for effect in effects {
            switch effect {
            case .addSpot(let spot):
                spots.add(spot)
            case .status(let text):
                show(text)
            }
        }
        if let stackReceived {
            for call in chat.drainStack() {
                stackReceived(call)
            }
        }
        if isChatOpen() {
            chat.markRead()
        }
    }

    // MARK: - sending

    /// Kotlin `sendChat(to, text)`: `to` empty = everyone.
    public func sendChat(to: String, text: String) {
        switch NetMessages.planChat(connected: cluster.isRunning, text: text) {
        case .rejected(let message):
            show(message)
        case .ignore:
            break
        case .send(let trimmed):
            cluster.send(type: NetMessageWire.chat, to: to, text: trimmed, call: nil, freqHz: 0, mode: nil) {
                [weak self] result in
                self?.chatSent(result)
            }
        }
    }

    private func chatSent(_ result: Result<NetMessageWire, any Error>) {
        switch result {
        case .success(let sent):
            chat.sentChat(sent, now: instant)
        case .failure(let error):
            show(NetMessages.failure("Chat", message: ErrorText.message(error)))
        }
    }

    /// Kotlin `startPass()` (Ctrl+Alt+P): the typed call to the only online station at once, otherwise to be chosen
    /// in the network status window.
    public func startPass() {
        switch NetMessages.startPass(typedCall: cluster.sources.typedCall(), peers: peers()) {
        case .rejected(let message):
            show(message)
        case .direct(let to, let call):
            passCall(to: to, call: call)
        case .choose(let call, let message):
            chat.passPending = call
            openStatusWindow()
            show(message)
        }
    }

    /// N1MM right-click on a band button with a call typed: the call goes to the network station working that band
    /// (its pass frequency, else its own frequency). `false` = the network log is not connected — the caller does the
    /// local action instead.
    public func passToBand(_ band: Band, call: String) -> Bool {
        guard isConnected, let peers = peers() else { return false }
        let upper: String = KotlinStrings.uppercase(KotlinStrings.trim(call))
        guard !upper.isEmpty else { return false }
        guard let target = NetMessages.peerOnBand(band, peers: peers, passFrequencies: chat.passFrequencies) else {
            show(.tr(NetTexts.passNoStationOnBandKey, .string(band.adif)))
            return true
        }
        passCall(to: target, call: upper)
        return true
    }

    /// Kotlin `passCall(to, call)`: the call goes with the target station's frequency (it is on its own band) and the
    /// own frequency in the text; without a call the pending or the typed one.
    public func passCall(to: String, call: String? = nil) {
        let passed: String = call ?? NetMessages.defaultPassCall(pending: chat.passPending,
                                                                 typedCall: cluster.sources.typedCall())
        guard let message = NetMessages.passMessage(to: to, call: passed, peers: peers(), myFreqHz: ownFrequency(),
                                                    translator: language.translator,
                                                    passFrequencyHz: chat.passFrequencies[to]) else { return }
        if message.freqHz > 0 {
            lastPassedFreqHz = message.freqHz
        }
        cluster.send(type: NetMessageWire.pass, to: message.to, text: message.note, call: message.call,
                     freqHz: message.freqHz, mode: message.mode) { [weak self] result in
            self?.passSent(result, to: to, call: passed)
        }
    }

    private func passSent(_ result: Result<NetMessageWire, any Error>, to: String, call: String) {
        switch result {
        case .success(let sent):
            show(chat.sentPass(sent, to: to, call: call, now: instant))
        case .failure(let error):
            show(NetMessages.failure("Pass", message: ErrorText.message(error)))
        }
    }

    /// N1MM Alt+Z: this station's pass frequency (kHz, empty = clear) to all stations; a PASS to this station then
    /// lands there. A text that is no frequency does nothing.
    public func setPassFrequency(_ text: String) {
        guard let hz = NetMessages.passFrequencyHz(text) else { return }
        guard cluster.isRunning else {
            show(NetMessages.passFrequencyNotConnectedStatus)
            return
        }
        cluster.send(type: NetMessageWire.passFrequency, to: "", text: "", call: nil, freqHz: hz, mode: nil) {
            [weak self] result in
            switch result {
            case .success:
                self?.ownPassFrequencyHz = hz
                self?.show(NetMessages.sentPassFrequency(hz))
            case .failure(let error):
                self?.show(NetMessages.failure("Pass", message: ErrorText.message(error)))
            }
        }
    }

    /// Kotlin `stackCall(to, call)`: the call into the stack of the station `to` (partner → runner).
    public func stackCall(to: String, call: String) {
        switch NetMessages.planStack(connected: cluster.isRunning, to: to, call: call) {
        case .rejected(let message):
            show(message)
        case .ignore:
            break
        case .send(let target, let upper):
            cluster.send(type: NetMessageWire.stack, to: target, text: "", call: upper, freqHz: 0, mode: nil) {
                [weak self] result in
                self?.stackSent(result, to: target, call: upper)
            }
        }
    }

    private func stackSent(_ result: Result<NetMessageWire, any Error>, to: String, call: String) {
        switch result {
        case .success:
            stackedCalls[call] = to
            show(NetMessages.sentStack(call: call, to: to))
        case .failure(let error):
            show(NetMessages.failure("Partner", message: ErrorText.message(error)))
        }
    }

    /// The stack target logged a call this station stacked for it: the call is wiped from the entry windows here.
    func remoteLogged(_ qsos: [Qso]) {
        for qso in qsos {
            let call: String = KotlinStrings.uppercase(qso.call)
            guard let target = stackedCalls[call], target == qso.stationId else { continue }
            stackedCalls[call] = nil
            wipeCall(call)
        }
    }

    /// Kotlin `popStackedCall()` (Ctrl+Alt+K): the oldest call of the stack into the call field.
    public func popStack() {
        guard let call = chat.popStack() else {
            show(NetMessages.stackEmptyStatus)
            return
        }
        prefillCall(call)
    }

    /// The partner window's call field (Kotlin `it.uppercase().filter { c -> c.isLetterOrDigit() || c == '/' }`).
    public static func partnerCallFilter(_ text: String) -> String {
        String(KotlinStrings.uppercase(text).filter { $0.isLetter || $0.isNumber || $0 == "/" })
    }

    // MARK: - multi-user macros

    /// The network log is connected (the multi-user macros are substituted only then).
    public var isConnected: Bool {
        cluster.isRunning
    }

    /// The online stations for `{PASS …}` / `{PASSMSG …}`.
    public func macroPassTargets() -> [MacroPassTarget] {
        (peers() ?? []).filter(\.online).compactMap { peer in
            guard let id = peer.status.stationId else { return nil }
            let run: Bool = peer.status.runMode == "RUN" || (peer.status.stationType ?? "").hasPrefix("RUN")
            return MacroPassTarget(station: id, freqHz: peer.status.freqHz, passHz: chat.passFrequencies[id] ?? 0,
                                   run: run)
        }
    }

    /// `{MESSAGE}`: the talk message to the named station or to all.
    public func sendMacroMessage(_ text: String) {
        let stations: [String] = macroPassTargets().map(\.station)
        let (to, body) = MultiUserMacro.messageTarget(text, stations: stations)
        sendChat(to: to, text: body)
    }

    /// `{PASSMSG …}`: the last QSO's call passed to the named station or to the run station of the band.
    public func passLastQso(_ argument: String, call: String) {
        guard !KotlinStrings.isBlank(call) else {
            show(.tr(NetTexts.passNeedCallKeyPublic))
            return
        }
        guard let target = MultiUserMacro.target(argument, in: macroPassTargets()) else {
            show(.tr(NetworkMacroTexts.noTargetKey, .string(argument)))
            return
        }
        passCall(to: target.station, call: call)
    }

    // MARK: - the station table

    /// The columns of the Network Status station table (N1MM: right-click the header to choose them).
    public var columns: [NetworkStationColumn] {
        NetworkStationColumn.resolve(config.config.cluster.statusColumns)
    }

    /// Shows or hides a column (saved).
    public func toggleColumn(_ column: NetworkStationColumn) {
        saveColumns(NetworkStationColumn.toggled(columns, column))
    }

    /// Moves a column one place left (`-1`) or right (`1`) (saved).
    public func moveColumn(_ column: NetworkStationColumn, by delta: Int) {
        saveColumns(NetworkStationColumn.moved(columns, column, by: delta))
    }

    /// Back to the default columns.
    public func resetColumns() {
        saveColumns([])
    }

    private func saveColumns(_ next: [NetworkStationColumn]) {
        let names: [String] = next == NetworkStationColumn.defaultOrder ? [] : next.map(\.rawValue)
        guard names != config.config.cluster.statusColumns else { return }
        config.config.cluster.statusColumns = names
        config.saveSilently()
    }

    /// Rates, last QSO and pass frequency of every station (from the shared log and the Alt+Z announcements).
    public func stationExtras() -> [String: NetworkStationExtras] {
        NetworkStationExtras.compute(logbook.rows, passFrequencies: chat.passFrequencies)
    }

    /// The chat window is open: everything is read (the window calls it when it appears; a line arriving while it is
    /// open is read by `receive`).
    public func markChatRead() {
        chat.markRead()
    }
}
