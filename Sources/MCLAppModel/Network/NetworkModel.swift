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

    @ObservationIgnored private let cluster: ClusterSyncModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let spots: SpotBuffer
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Kotlin `prefillCall = …`: the call goes into the active entry window; set by the app.
    @ObservationIgnored var prefillCall: @MainActor (String) -> Void = { _ in }
    /// Kotlin `showNetStatus = true`: the network status window opens; set by the app.
    @ObservationIgnored var openStatusWindow: @MainActor () -> Void = {}
    /// Whether the chat window is open (set by the app): Kotlin zeroes `chatUnread` as a side effect of drawing the
    /// window (`LaunchedEffect(chatLines.size)`), so a line that arrives while it is open is read at once.
    @ObservationIgnored var isChatOpen: @MainActor () -> Bool = { false }

    public init(cluster: ClusterSyncModel, status: StatusModel, language: LanguageModel, spots: SpotBuffer,
                now: @escaping @Sendable () -> Date) {
        self.cluster = cluster
        self.status = status
        self.language = language
        self.spots = spots
        self.now = now
        cluster.onMessage = { [weak self] message in
            self?.receive(message)
        }
    }

    private var instant: JavaInstant {
        JavaInstant(date: now())
    }

    private func show(_ message: EntryStatus) {
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

    /// Kotlin `passCall(to, call)`: the call goes with the target station's frequency (it is on its own band) and the
    /// own frequency in the text; without a call the pending or the typed one.
    public func passCall(to: String, call: String? = nil) {
        let passed: String = call ?? NetMessages.defaultPassCall(pending: chat.passPending,
                                                                 typedCall: cluster.sources.typedCall())
        guard let message = NetMessages.passMessage(to: to, call: passed, peers: peers(), myFreqHz: ownFrequency(),
                                                    translator: language.translator) else { return }
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
            show(NetMessages.sentStack(call: call, to: to))
        case .failure(let error):
            show(NetMessages.failure("Partner", message: ErrorText.message(error)))
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

    /// The chat window is open: everything is read (the window calls it when it appears; a line arriving while it is
    /// open is read by `receive`).
    public func markChatRead() {
        chat.markRead()
    }
}
