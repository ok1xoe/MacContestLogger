import Foundation

/// One line of the chat window (`AppState.ChatLine`): own and received messages, PASS and other message types as
/// system lines.
public struct ChatLine: Sendable, Equatable {
    /// UTC `HHmm`.
    public let time: String
    public let from: String
    public let to: String
    public let text: String
    public let own: Bool

    public init(time: String, from: String, to: String, text: String, own: Bool) {
        self.time = time
        self.from = from
        self.to = to
        self.text = text
        self.own = own
    }
}

/// What a received message asks the app to do besides changing the `NetMessages` state.
public enum NetEffect: Sendable, Equatable {
    /// The status line text.
    case status(EntryStatus)
    /// Put the spot into the band map's buffer (a PASS with a known frequency).
    case addSpot(DxSpot)
}

/// Where a call to pass goes (`startPass`): `.direct` with exactly one online peer, otherwise the user chooses in the
/// network status window; `.noNet` when the network log is not connected.
public enum PassTarget: Sendable, Equatable {
    case direct(StationNetwork.Peer)
    case choose
    case noNet
}

/// The outcome of Ctrl+Alt+P (`startPass`).
public enum PassStart: Sendable, Equatable {
    /// Nothing to pass or no network: only the status line.
    case rejected(EntryStatus)
    /// Pass the call to this station at once.
    case direct(to: String, call: String)
    /// Remember the call as `passPending`, open the network status window and show the status.
    case choose(call: String, status: EntryStatus)
}

/// A PASS to send (`passCall`): the arguments of `StationNetwork.send`.
public struct PassMessage: Sendable, Equatable {
    public let to: String
    public let call: String
    /// `tr("u mě %.1f")` with the own frequency, or `""` when it is not known.
    public let note: String
    /// The frequency of the target station (it is on its own band), 0 for an unknown station.
    public let freqHz: Int
    public let mode: String
}

/// What to do with a chat text typed by the operator (`sendChat`).
public enum ChatPlan: Sendable, Equatable {
    case rejected(EntryStatus)
    /// A blank text: nothing happens.
    case ignore
    /// Send this (Kotlin-trimmed) text.
    case send(text: String)
}

/// What to do with a call for the partner's stack (`stackCall`).
public enum StackPlan: Sendable, Equatable {
    case rejected(EntryStatus)
    case ignore
    /// Send this (trimmed, uppercased) call to `to`.
    case send(to: String, call: String)
}

/// The multi-op messages (chat, PASS, call stack) of v1.1.1 `AppState` (`ui/AppState.kt:2955-3108`) as a value:
/// the chat lines with the cap of 500, the unread counter, the stack of calls from the partner with the cap of 10, the
/// call waiting to be passed. Pure logic: no network and no system clock (the caller hands in `now`).
///
/// Kotlin quirks kept: the unread counter counts CHAT and PASS but not other types; a PASS without a call and with a
/// frequency makes Kotlin throw before anything changes (here: no state change, no effect); a CAT state with
/// frequency 0 wins over the tuned frequency (`?:` only skips a missing state); a stack entry is not trimmed (only
/// uppercased); the status of a duplicate or blank STACK call is still shown.
public struct NetMessages: Sendable, Equatable {

    public static let chatCap = 500
    public static let stackCap = 10

    public private(set) var lines: [ChatLine] = []
    /// Unread messages — the open chat window resets it (`markRead`).
    public private(set) var unread: Int = 0
    /// Calls from the partner waiting for the runner, oldest first.
    public private(set) var stack: [String] = []
    /// A call prepared for passing; the network status window offers a "pass" button per station.
    public var passPending: String = ""

    public init() {}

    // MARK: - receiving

    /// `onNetMessage` + `onNetMessageExtra`.
    /// - Parameters:
    ///   - catFreqHz: the frequency of the active rig, `nil` when it has no state
    ///   - tunedHz: the tuned frequency (`tunedFreqHz`), the fallback without CAT
    public mutating func receive(_ w: NetMessageWire, catFreqHz: Int?, tunedHz: Int, now: JavaInstant) -> [NetEffect] {
        let from: String = Self.sender(w)
        let to: String = w.toStation ?? ""
        let time: String = Self.chatTime(w.timestampUtc, now: now)
        switch w.type {
        case NetMessageWire.chat:
            let text: String = w.text ?? ""
            addLine(ChatLine(time: time, from: from, to: to, text: text, own: false))
            unread += 1
            let verbatim: String = "Chat " + NetTexts.text(w.fromStation) + ": " + NetTexts.text(w.text)
            return [.status(.verbatim(verbatim))]
        case NetMessageWire.stack:
            return receiveStack(w)
        case NetMessageWire.pass:
            return receivePass(w, from: from, to: to, time: time, catFreqHz: catFreqHz, tunedHz: tunedHz)
        default:
            let type: String = NetTexts.text(w.type)
            let call: String = NetTexts.text(w.call)
            let text: String = NetTexts.text(w.text)
            let line: String = KotlinText.trim("[" + type + "] " + call + " " + text)
            addLine(ChatLine(time: time, from: from, to: to, text: line, own: false))
            return []
        }
    }

    private mutating func receiveStack(_ w: NetMessageWire) -> [NetEffect] {
        let call: String = JavaText.toUpperCase(w.call ?? "")
        let known: Bool = stack.contains(where: { JavaText.equals($0, call) })
        if !KotlinText.isBlank(call) && !known {
            stack.append(call)
            if stack.count > Self.stackCap {
                stack.removeFirst(stack.count - Self.stackCap)
            }
        }
        let status: EntryStatus = .tr(NetTexts.stackFromKey, .string(w.fromStation), .string(call))
        return [.status(status)]
    }

    private mutating func receivePass(_ w: NetMessageWire, from: String, to: String, time: String,
                                      catFreqHz: Int?, tunedHz: Int) -> [NetEffect] {
        let freq: Int = w.freqHz > 0 ? w.freqHz : (catFreqHz ?? tunedHz)
        let khz: String = JavaFormat.format("%.1f", .double(Double(freq) / 1000))
        var effects: [NetEffect] = []
        if freq > 0 {
            // Kotlin hands the possibly missing call to the spot buffer, which throws: the whole message is lost.
            guard let call = w.call else { return [] }
            let comment: String = KotlinText.trim("pass " + (w.text ?? ""))
            let spot = DxSpot(spotter: "PASS-" + NetTexts.text(w.fromStation), freqHz: freq, dxCall: call,
                              comment: comment)
            effects.append(.addSpot(spot))
        }
        let call: String = NetTexts.text(w.call)
        let text: String = KotlinText.trim("PASS " + call + " → " + khz + " " + (w.text ?? ""))
        addLine(ChatLine(time: time, from: from, to: to, text: text, own: false))
        unread += 1
        let status: EntryStatus = .tr(NetTexts.passFromKey, .string(w.fromStation), .string(w.call), .string(khz))
        effects.append(.status(status))
        return effects
    }

    /// `fromStation` plus ` (operator)` for a non-blank operator.
    static func sender(_ w: NetMessageWire) -> String {
        var from: String = NetTexts.text(w.fromStation)
        if let op = w.fromOperator, !KotlinText.isBlank(op) {
            from += " (" + op + ")"
        }
        return from
    }

    private mutating func addLine(_ line: ChatLine) {
        lines.append(line)
        if lines.count > Self.chatCap {
            lines.removeFirst(lines.count - Self.chatCap)
        }
    }

    /// `chatTime`: UTC `HHmm` of the message time; an unparseable or missing time falls back to `now`.
    public static func chatTime(_ iso: String?, now: JavaInstant) -> String {
        let instant: JavaInstant = iso.flatMap { JavaInstant.parseIsoInstant($0) } ?? now
        let secondOfDay: Int64 = ((instant.epochSecond % 86_400) + 86_400) % 86_400
        let hour = Int(secondOfDay / 3_600)
        let minute = Int((secondOfDay % 3_600) / 60)
        return String(format: "%02d%02d", hour, minute)
    }

    // MARK: - own messages (after a successful send)

    /// The own chat line after `sendChat` succeeded.
    public mutating func sentChat(_ m: NetMessageWire, now: JavaInstant) {
        let time: String = Self.chatTime(m.timestampUtc, now: now)
        addLine(ChatLine(time: time, from: m.fromStation ?? "", to: m.toStation ?? "", text: m.text ?? "", own: true))
    }

    /// The own line after `passCall` succeeded: clears the pending call, returns the status.
    public mutating func sentPass(_ m: NetMessageWire, to: String, call: String, now: JavaInstant) -> EntryStatus {
        let time: String = Self.chatTime(m.timestampUtc, now: now)
        addLine(ChatLine(time: time, from: m.fromStation ?? "", to: to, text: "PASS " + call, own: true))
        passPending = ""
        return .tr(NetTexts.passSentKey, .string(call), .string(to))
    }

    /// The status after `stackCall` succeeded.
    public static func sentStack(call: String, to: String) -> EntryStatus {
        .tr(NetTexts.stackSentKey, .string(call), .string(to))
    }

    /// `"Chat: …"`, `"Pass: …"`, `"Partner: …"` after a failed send (`it.message`, not translated).
    public static func failure(_ prefix: String, message: String?) -> EntryStatus {
        .verbatim(prefix + ": " + NetTexts.text(message))
    }

    // MARK: - stack

    public static let stackEmptyStatus: EntryStatus = .tr(NetTexts.stackEmptyKey)

    /// `popStackedCall`: the oldest call (it goes to the call field), `nil` for an empty stack (show
    /// `stackEmptyStatus`).
    public mutating func popStack() -> String? {
        stack.isEmpty ? nil : stack.removeFirst()
    }

    /// The chat window is open: everything is read.
    public mutating func markRead() {
        unread = 0
    }

    // MARK: - sending side

    /// `sendChat`: not connected → status, blank text → nothing, else the Kotlin-trimmed text.
    public static func planChat(connected: Bool, text: String) -> ChatPlan {
        if !connected {
            return .rejected(.tr(NetTexts.chatNotConnectedKey))
        }
        if KotlinText.isBlank(text) {
            return .ignore
        }
        return .send(text: KotlinText.trim(text))
    }

    /// `passTarget` of `startPass`: `nil` peers = not connected; exactly one online peer = directly.
    public static func passTarget(peers: [StationNetwork.Peer]?) -> PassTarget {
        guard let peers else { return .noNet }
        let online: [StationNetwork.Peer] = peers.filter { $0.online }
        if online.count == 1 {
            return .direct(online[0])
        }
        return .choose
    }

    /// Ctrl+Alt+P: the call in the field (trimmed, uppercased), then the network and the number of online peers.
    public static func startPass(typedCall: String, peers: [StationNetwork.Peer]?) -> PassStart {
        let call: String = JavaText.toUpperCase(KotlinText.trim(typedCall))
        if call.isEmpty {
            return .rejected(.tr(NetTexts.passNeedCallKey))
        }
        switch passTarget(peers: peers) {
        case .noNet:
            return .rejected(.tr(NetTexts.passNotConnectedKey))
        case .direct(let peer):
            return .direct(to: peer.status.stationId ?? "", call: call)
        case .choose:
            return .choose(call: call, status: .tr(NetTexts.passChooseKey, .string(call)))
        }
    }

    /// The call a pass defaults to (`passCall` without an explicit call): the pending call, else the typed one,
    /// trimmed and uppercased.
    public static func defaultPassCall(pending: String, typedCall: String) -> String {
        let base: String = KotlinText.isBlank(pending) ? typedCall : pending
        return JavaText.toUpperCase(KotlinText.trim(base))
    }

    /// `passNote`: `tr("u mě %.1f")` with the own frequency in kHz (US decimals), `""` for a frequency not above 0.
    public static func passNote(myFreqHz: Int, translator: Translator) -> String {
        if myFreqHz <= 0 {
            return ""
        }
        return translator.translate(NetTexts.passNoteKey, [.double(Double(myFreqHz) / 1000)])
    }

    /// `passCall`: `nil` when the network is not connected (`peers == nil`) or the call is blank, else the message with
    /// the frequency and mode of the target station (0 and `""` for an unknown one).
    public static func passMessage(to: String, call: String, peers: [StationNetwork.Peer]?, myFreqHz: Int,
                                   translator: Translator) -> PassMessage? {
        guard let peers else { return nil }
        if KotlinText.isBlank(call) {
            return nil
        }
        let peer: StationNetwork.Peer? = peers.first { JavaText.equals(to, $0.status.stationId) }
        return PassMessage(to: to, call: call, note: passNote(myFreqHz: myFreqHz, translator: translator),
                           freqHz: peer?.status.freqHz ?? 0, mode: peer?.status.mode ?? "")
    }

    /// `stackCall`: not connected → status; a blank call or target → nothing; else the call trimmed and uppercased.
    public static func planStack(connected: Bool, to: String, call: String) -> StackPlan {
        if !connected {
            return .rejected(.tr(NetTexts.partnerNotConnectedKey))
        }
        let upper: String = JavaText.toUpperCase(KotlinText.trim(call))
        if KotlinText.isBlank(upper) || KotlinText.isBlank(to) {
            return .ignore
        }
        return .send(to: to, call: upper)
    }
}
