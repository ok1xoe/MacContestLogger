import Foundation
import MCLCore

/// What the acting requests of a window plugin (`entry`, `rig`, `spots`, `app.command`) do in the app: closures over
/// the same model calls the user's actions use, set when the app is wired. Nothing here keys a transmitter: the rig
/// is tuned through the entry window (CAT frequency, mode, split, RIT, VFO), spots go through the spot actions, and
/// text commands pass `PluginCommandPolicy`.
@MainActor
public struct PluginHostActions {
    public struct EntryState: Equatable, Sendable {
        public var call: String
        public var exchange: [(String, String)]
        public var freqHz: Int64
        public var mode: String?
        public var radio: Int

        public init(call: String, exchange: [(String, String)], freqHz: Int64, mode: String?, radio: Int) {
            self.call = call
            self.exchange = exchange
            self.freqHz = freqHz
            self.mode = mode
            self.radio = radio
        }

        public static func == (lhs: EntryState, rhs: EntryState) -> Bool {
            lhs.call == rhs.call && lhs.exchange.map { $0.0 + "=" + $0.1 } == rhs.exchange.map { $0.0 + "=" + $0.1 }
                && lhs.freqHz == rhs.freqHz && lhs.mode == rhs.mode && lhs.radio == rhs.radio
        }
    }

    // entry
    public var entryState: () -> EntryState? = { nil }
    /// Types a call; `nil` = done, else why not (a text that is a command is refused).
    public var setCall: (String) -> String? = { _ in "no entry window" }
    /// Sets exchange fields by id; returns the ids the contest does not have.
    public var setExchange: ([String: String]) -> [String] = { values in Array(values.keys) }
    public var wipe: () -> Void = {}
    /// Logs the QSO in the entry window as Enter would without ESM (never transmits); `nil` = submitted, else why
    /// not.
    public var log: () -> String? = { "no entry window" }
    public var status: (String) -> Void = { _ in }

    // rig
    /// QSY to a frequency (Hz), optionally with a mode; `nil` = done, else why not.
    public var qsy: (Int64, Mode?) -> String? = { _, _ in "no entry window" }
    public var setMode: (Mode) -> String? = { _ in "no entry window" }
    /// Split on with the transmit frequency, or off (`nil`).
    public var split: (Int64?) -> String? = { _ in "no entry window" }
    public var rit: (Int32) -> String? = { _ in "no entry window" }
    public var swapVfo: () -> String? = { "no entry window" }
    /// Makes radio / VFO 0 or 1 the active one.
    public var focusRadio: (Int) -> String? = { _ in "no entry window" }

    // spots
    public var addSpot: (DxSpot) -> Void = { _ in }
    /// Removes every spot of the call (optionally onto the blacklist); `false` = none found.
    public var removeSpot: (String, Bool) -> Bool = { _, _ in false }
    public var mark: (Int64) -> Void = { _ in }
    public var blacklist: (String) -> Void = { _ in }
    /// Sends a spot to the cluster (Spot It with a comment); `nil` = sent, else why not.
    public var sendSpot: (String, Int64, String) -> String? = { _, _, _ in "not connected" }
    public var stationCall: () -> String = { "" }

    // commands
    /// Runs a call-field text command; `nil` = run, else why not.
    public var command: (String) -> String? = { _ in "no entry window" }

    // cat
    /// A raw CAT command on the active rig (already checked by `PluginCatPolicy`).
    public var rawCat: (String, @escaping @MainActor @Sendable (Result<RigRawReply, CatRawError>) -> Void) -> Void = {
        _, then in then(.failure(CatRawError(message: "no rig")))
    }

    // transmit — the same paths as the F-keys, Esc and the footswitch PTT
    /// CW text through the keyer (CW mode only; the macros of the F-key messages apply).
    public var sendCw: (String) -> String? = { _ in "no keyer" }
    /// F-key `index` (0…11) of the active entry window, as pressing it (`opposite` = the other message set).
    public var functionKey: (Int, Bool) -> String? = { _, _ in "no entry window" }
    /// The voice message of F-key `index` (phone modes only).
    public var voice: (Int) -> String? = { _ in "no entry window" }
    /// Esc: stops every transmission (also a plugin's PTT); `true` = something was stopped.
    public var stop: () -> Bool = { false }
    /// The PTT of the active rig.
    public var ptt: (Bool) -> String? = { _ in "no rig" }
    /// Whether the keyer is sending now (the transmit indicator).
    public var isSending: () -> Bool = { false }

    public init() {}
}

extension PluginRpc {

    /// A callsign as plugins may type or spot it: letters, digits and `/`, 3–20 characters.
    nonisolated static func isCallsign(_ text: String) -> Bool {
        (1...20).contains(text.count) && text.unicodeScalars.allSatisfy { scalar in
            (scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)) || scalar == "/"
        } && text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    /// A free text without control characters (no line ends, no escapes), at most `limit` characters.
    nonisolated static func isPlainText(_ text: String, limit: Int) -> Bool {
        text.count <= limit && !text.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    /// The acting methods and the permission each needs.
    static let actionMethods: [String: String] = [
        "entry.getCall": "entry", "entry.setCall": "entry", "entry.setExchange": "entry", "entry.wipe": "entry",
        "entry.log": "entry", "entry.status": "entry",
        "rig.qsy": "rig", "rig.setMode": "rig", "rig.split": "rig", "rig.rit": "rig", "rig.swap": "rig",
        "rig.focusedRadio": "rig",
        "spots.add": "spots", "spots.remove": "spots", "spots.mark": "spots", "spots.blacklist": "spots",
        "spots.send": "spots.send",
        "app.command": "app.command",
        "tx.sendCw": "transmit", "tx.fkey": "transmit", "tx.voice": "transmit", "tx.stop": "transmit",
        "tx.ptt": "transmit",
    ]

    static func act(method: String, params: [String: PluginJSON],
                    actions: PluginHostActions) -> Result<PluginJSON, Failure> {
        func done(_ refusal: String?) -> Result<PluginJSON, Failure> {
            refusal.map { .failure(Failure(code: "refused", message: $0)) } ?? .success(.object(["ok": .bool(true)]))
        }
        func text(_ key: String) -> String? {
            params[key]?.stringValue
        }
        func invalid(_ message: String) -> Result<PluginJSON, Failure> {
            .failure(Failure(code: "invalid_params", message: message))
        }
        switch method {
        case "entry.getCall":
            guard let state = actions.entryState() else { return done("no entry window") }
            var exchange: [String: PluginJSON] = [:]
            for (key, value) in state.exchange {
                exchange[key] = .string(value)
            }
            return .success(.object([
                "call": .string(state.call), "exchange": .object(exchange), "freqHz": .int(state.freqHz),
                "mode": .optional(state.mode), "radio": .int(Int64(state.radio)),
            ]))
        case "entry.setCall":
            guard let call = text("call") else { return invalid("entry.setCall needs call") }
            guard call.isEmpty || isCallsign(call) else {
                return invalid("entry.setCall takes a callsign (letters, digits, /)")
            }
            return done(actions.setCall(call.uppercased()))
        case "entry.setExchange":
            guard let fields = params["fields"]?.objectValue else { return invalid("entry.setExchange needs fields") }
            var values: [String: String] = [:]
            for (key, value) in fields {
                guard let string = value.stringValue, isPlainText(string, limit: 32) else {
                    return invalid("exchange values must be texts of at most 32 characters without control characters")
                }
                values[key] = string
            }
            let unknown: [String] = actions.setExchange(values)
            return .success(.object(["ok": .bool(true), "unknown": .array(unknown.sorted().map { .string($0) })]))
        case "entry.wipe":
            actions.wipe()
            return done(nil)
        case "entry.log":
            return done(actions.log())
        case "entry.status":
            guard let message = text("text"), isPlainText(message, limit: 200) else {
                return invalid("entry.status needs a text of at most 200 characters without control characters")
            }
            actions.status(message)
            return done(nil)
        case "rig.qsy":
            guard let hz = params["freqHz"]?.intValue, hz > 0, Band.from(frequencyHz: Int(clamping: hz)) != nil else {
                return invalid("rig.qsy needs freqHz inside an amateur band")
            }
            var mode: Mode?
            if let name = text("mode") {
                guard let parsed = Mode(rawValue: name.uppercased()) else { return invalid("unknown mode \(name)") }
                mode = parsed
            }
            return done(actions.qsy(hz, mode))
        case "rig.setMode":
            guard let name = text("mode"), let mode = Mode(rawValue: name.uppercased()) else {
                return invalid("rig.setMode needs a known mode")
            }
            return done(actions.setMode(mode))
        case "rig.split":
            if params["off"]?.boolValue == true {
                return done(actions.split(nil))
            }
            guard let hz = params["txFreqHz"]?.intValue, hz > 0, Band.from(frequencyHz: Int(clamping: hz)) != nil else {
                return invalid("rig.split needs txFreqHz inside an amateur band, or off: true")
            }
            return done(actions.split(hz))
        case "rig.rit":
            guard let hz = params["offsetHz"]?.intValue, abs(hz) <= 99_999 else {
                return invalid("rig.rit needs offsetHz within ±99999")
            }
            return done(actions.rit(Int32(hz)))
        case "rig.swap":
            return done(actions.swapVfo())
        case "rig.focusedRadio":
            guard let radio = params["radio"]?.intValue, radio == 0 || radio == 1 else {
                return invalid("rig.focusedRadio needs radio 0 or 1")
            }
            return done(actions.focusRadio(Int(radio)))
        case "spots.add":
            guard let call = text("call"), isCallsign(call), let hz = params["freqHz"]?.intValue, hz > 0,
                  isPlainText(text("comment") ?? "", limit: 60) else {
                return invalid("spots.add needs a callsign, freqHz and a comment of at most 60 plain characters")
            }
            let spot = DxSpot(spotter: actions.stationCall(), freqHz: Int(clamping: hz), dxCall: call.uppercased(),
                              comment: text("comment") ?? "", selfSpotted: true)
            actions.addSpot(spot)
            return done(nil)
        case "spots.remove":
            guard let call = text("call"), isCallsign(call) else { return invalid("spots.remove needs a callsign") }
            let found: Bool = actions.removeSpot(call.uppercased(), params["blacklist"]?.boolValue ?? false)
            return .success(.object(["removed": .bool(found)]))
        case "spots.mark":
            guard let hz = params["freqHz"]?.intValue, hz > 0 else { return invalid("spots.mark needs freqHz") }
            actions.mark(hz)
            return done(nil)
        case "spots.blacklist":
            guard let call = text("call"), isCallsign(call) else { return invalid("spots.blacklist needs a callsign") }
            actions.blacklist(call.uppercased())
            return done(nil)
        case "spots.send":
            // Never a line end or another control character: the text goes to the cluster as one command line.
            guard let call = text("call"), isCallsign(call), let hz = params["freqHz"]?.intValue,
                  Band.from(frequencyHz: Int(clamping: hz)) != nil, isPlainText(text("comment") ?? "", limit: 60) else {
                return invalid("spots.send needs a callsign, freqHz inside a band and a comment of at most 60 plain characters")
            }
            return done(actions.sendSpot(call.uppercased(), hz, text("comment") ?? ""))
        case "tx.sendCw":
            guard let message = text("text"), !message.isEmpty, isPlainText(message, limit: 200) else {
                return invalid("tx.sendCw needs a text of at most 200 plain characters")
            }
            return done(actions.sendCw(message))
        case "tx.fkey":
            guard let index = params["key"]?.intValue, (1...12).contains(index) else {
                return invalid("tx.fkey needs key 1…12")
            }
            return done(actions.functionKey(Int(index) - 1, params["opposite"]?.boolValue ?? false))
        case "tx.voice":
            guard let index = params["key"]?.intValue, (1...12).contains(index) else {
                return invalid("tx.voice needs key 1…12")
            }
            return done(actions.voice(Int(index) - 1))
        case "tx.stop":
            return .success(.object(["stopped": .bool(actions.stop())]))
        case "tx.ptt":
            guard let on = params["on"]?.boolValue else { return invalid("tx.ptt needs on") }
            return done(actions.ptt(on))
        default:
            guard let command = text("text"), !command.isEmpty, isPlainText(command, limit: 80) else {
                return invalid("app.command needs a text of at most 80 plain characters")
            }
            return done(actions.command(command))
        }
    }
}
