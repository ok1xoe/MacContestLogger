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
    public var setCall: (String) -> Void = { _ in }
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

    public init() {}
}

extension PluginRpc {

    /// The acting methods and the permission each needs.
    static let actionMethods: [String: String] = [
        "entry.getCall": "entry", "entry.setCall": "entry", "entry.setExchange": "entry", "entry.wipe": "entry",
        "entry.log": "entry", "entry.status": "entry",
        "rig.qsy": "rig", "rig.setMode": "rig", "rig.split": "rig", "rig.rit": "rig", "rig.swap": "rig",
        "rig.focusedRadio": "rig",
        "spots.add": "spots", "spots.remove": "spots", "spots.mark": "spots", "spots.blacklist": "spots",
        "spots.send": "spots.send",
        "app.command": "app.command",
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
            actions.setCall(String(call.prefix(64)))
            return done(nil)
        case "entry.setExchange":
            guard let fields = params["fields"]?.objectValue else { return invalid("entry.setExchange needs fields") }
            var values: [String: String] = [:]
            for (key, value) in fields {
                guard let string = value.stringValue else { return invalid("exchange values must be texts") }
                values[key] = String(string.prefix(64))
            }
            let unknown: [String] = actions.setExchange(values)
            return .success(.object(["ok": .bool(true), "unknown": .array(unknown.sorted().map { .string($0) })]))
        case "entry.wipe":
            actions.wipe()
            return done(nil)
        case "entry.log":
            return done(actions.log())
        case "entry.status":
            guard let message = text("text") else { return invalid("entry.status needs text") }
            actions.status(String(message.prefix(200)))
            return done(nil)
        case "rig.qsy":
            guard let hz = params["freqHz"]?.intValue, hz > 0 else { return invalid("rig.qsy needs freqHz > 0") }
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
            guard let hz = params["txFreqHz"]?.intValue, hz > 0 else {
                return invalid("rig.split needs txFreqHz > 0 or off: true")
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
            guard let call = text("call"), !call.isEmpty, let hz = params["freqHz"]?.intValue, hz > 0 else {
                return invalid("spots.add needs call and freqHz")
            }
            let spot = DxSpot(spotter: actions.stationCall(), freqHz: Int(clamping: hz),
                              dxCall: String(call.uppercased().prefix(20)),
                              comment: String((text("comment") ?? "").prefix(60)), selfSpotted: true)
            actions.addSpot(spot)
            return done(nil)
        case "spots.remove":
            guard let call = text("call"), !call.isEmpty else { return invalid("spots.remove needs call") }
            let found: Bool = actions.removeSpot(call.uppercased(), params["blacklist"]?.boolValue ?? false)
            return .success(.object(["removed": .bool(found)]))
        case "spots.mark":
            guard let hz = params["freqHz"]?.intValue, hz > 0 else { return invalid("spots.mark needs freqHz") }
            actions.mark(hz)
            return done(nil)
        case "spots.blacklist":
            guard let call = text("call"), !call.isEmpty else { return invalid("spots.blacklist needs call") }
            actions.blacklist(call.uppercased())
            return done(nil)
        case "spots.send":
            guard let call = text("call"), !call.isEmpty, let hz = params["freqHz"]?.intValue, hz > 0 else {
                return invalid("spots.send needs call and freqHz")
            }
            return done(actions.sendSpot(call.uppercased(), hz, String((text("comment") ?? "").prefix(60))))
        default:
            guard let command = text("text"), !command.isEmpty else { return invalid("app.command needs text") }
            return done(actions.command(command))
        }
    }
}
