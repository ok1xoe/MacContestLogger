import Foundation
import MCLCore

/// What the requests of a window plugin read from the app: closures over the live models, set when the app is wired
/// (empty in a model built alone).
@MainActor
public struct PluginHostContext {
    /// The active contest (id and name), `nil` id = none.
    public var contest: () -> (id: String?, name: String?) = { (nil, nil) }
    /// The open logbook.
    public var handle: () -> LogbookHandle? = { nil }
    /// A fresh session of the active contest's definition (for the score replay).
    public var freshSession: () -> ContestSession? = { nil }
    /// The contest's band order.
    public var bandOrder: () -> [String?] = { [] }
    /// The active entry window's radio, frequency, mode, and whether CAT is connected.
    public var rig: () -> PluginRigState? = { nil }
    /// The live spots.
    public var spots: () -> [DxSpot] = { [] }
    /// The acting requests (`entry`, `rig`, `spots`, `app.command`).
    public var actions = PluginHostActions()
    /// The app's own shortcut on a key, by its label (`nil` = none).
    public var shortcutLabel: (KeyCombo) -> String? = { _ in nil }

    public init() {}
}

/// `rig.state`: the active entry window, read only.
public struct PluginRigState: Equatable, Sendable {
    public var radio: Int
    public var freqHz: Int64
    public var mode: String?
    public var catConnected: Bool

    public init(radio: Int, freqHz: Int64, mode: String?, catConnected: Bool) {
        self.radio = radio
        self.freqHz = freqHz
        self.mode = mode
        self.catConnected = catConnected
    }
}

/// The requests of protocol 1 — all read only. A method a plugin may not call, an unknown one or bad parameters
/// give an error response; nothing here throws past the answer. Database work runs on the logbook handle's queue,
/// never on the main actor.
@MainActor
enum PluginRpc {

    struct Failure: Error, Equatable {
        let code: String
        let message: String
    }

    /// Methods and the permission each needs.
    static let methods: [String: String] = [
        "log.query": "read", "log.count": "read", "log.get": "read", "contest.active": "read",
        "contest.score": "read", "contest.multipliers": "read", "rig.state": "read", "spots.list": "read",
        "cat.send": "cat", "tx.ptt": "transmit",
    ]

    /// The most spots `spots.list` returns.
    static let maxSpots = 2_000

    /// Answers one request. `readProbe` is told, inside each database read, whether that read runs on the main
    /// thread (a test seam).
    static func answer(method: String, params: [String: PluginJSON], permissions: [String],
                       context: PluginHostContext,
                       readProbe: (@Sendable (Bool) -> Void)? = nil) async -> Result<PluginJSON, Failure> {
        guard let permission = methods[method] ?? actionMethods[method] else {
            return .failure(Failure(code: "unknown_method", message: "unknown method \(method)"))
        }
        guard permissions.contains(permission) else {
            return .failure(Failure(code: "permission", message: "\(method) needs the \(permission) permission"))
        }
        if method == "cat.send" {
            return await rawCat(params, actions: context.actions)
        }
        if method == "tx.ptt" {
            guard let on = params["on"]?.boolValue else {
                return .failure(Failure(code: "invalid_params", message: "tx.ptt needs on"))
            }
            if let refusal = await context.actions.ptt(on) {
                return .failure(Failure(code: "refused", message: refusal))
            }
            return .success(.object(["ok": .bool(true)]))
        }
        if actionMethods[method] != nil {
            return act(method: method, params: params, actions: context.actions)
        }
        switch method {
        case "log.query", "log.count":
            return await logQuery(params, countOnly: method == "log.count", context: context, readProbe: readProbe)
        case "log.get":
            return await logGet(params, context: context, readProbe: readProbe)
        case "contest.active":
            let contest = context.contest()
            guard let id = contest.id else { return .success(.null) }
            return .success(.object(["id": .string(id), "name": .optional(contest.name)]))
        case "contest.score":
            return await score(context: context, readProbe: readProbe)
        case "contest.multipliers":
            return await multipliers(context: context, readProbe: readProbe)
        case "rig.state":
            guard let rig = context.rig() else { return .success(.null) }
            let band: String? = Band.from(frequencyHz: Int(clamping: rig.freqHz))?.adif
            return .success(.object([
                "radio": .int(Int64(rig.radio)), "freqHz": .int(rig.freqHz), "band": .optional(band),
                "mode": .optional(rig.mode), "catConnected": .bool(rig.catConnected),
            ]))
        default:
            return spots(params, context: context)
        }
    }

    private static func logQuery(_ params: [String: PluginJSON], countOnly: Bool, context: PluginHostContext,
                                 readProbe: (@Sendable (Bool) -> Void)?) async -> Result<PluginJSON, Failure> {
        let query: PluginLogQuery
        do throws(PluginLogQuery.Invalid) {
            query = try PluginLogQuery.parse(params)
        } catch {
            return .failure(Failure(code: "invalid_params", message: error.message))
        }
        guard let handle = context.handle() else {
            return .failure(Failure(code: "unavailable", message: "no logbook is open"))
        }
        let activeId: String = context.contest().id ?? ""
        do {
            let json: String = try await handle.run { access in
                readProbe?(Thread.isMainThread)
                let qsos: [Qso]
                switch query.scope {
                case .active: qsos = try access.repository.findAll(contestId: activeId)
                case .none: qsos = try access.repository.findAll(contestId: "")
                case .all: qsos = try access.repository.findAll()
                }
                let (page, total) = query.apply(qsos)
                if countOnly {
                    return PluginJSON.object(["count": .int(Int64(total))]).serialized()
                }
                let list: String = "[" + page.map(PluginEventJson.qsoLogged).joined(separator: ",") + "]"
                return PluginJSON.object(["qsos": .raw(list), "total": .int(Int64(total))]).serialized()
            }
            return .success(.raw(json))
        } catch {
            return .failure(Failure(code: "failed", message: "\(error)"))
        }
    }

    private static func logGet(_ params: [String: PluginJSON], context: PluginHostContext,
                               readProbe: (@Sendable (Bool) -> Void)?) async -> Result<PluginJSON, Failure> {
        guard let uuid = params["uuid"]?.stringValue, !uuid.isEmpty else {
            return .failure(Failure(code: "invalid_params", message: "log.get needs a uuid"))
        }
        guard let handle = context.handle() else {
            return .failure(Failure(code: "unavailable", message: "no logbook is open"))
        }
        do {
            let json: String? = try await handle.run { access in
                readProbe?(Thread.isMainThread)
                guard let qso = try access.repository.findByUuid(uuid), !qso.deleted else { return nil }
                return PluginEventJson.qsoLogged(qso)
            }
            return .success(json.map { .raw($0) } ?? .null)
        } catch {
            return .failure(Failure(code: "failed", message: "\(error)"))
        }
    }

    private static func score(context: PluginHostContext,
                              readProbe: (@Sendable (Bool) -> Void)?) async -> Result<PluginJSON, Failure> {
        guard let id = context.contest().id, let fresh = context.freshSession() else {
            return .success(.null)
        }
        guard let handle = context.handle() else {
            return .failure(Failure(code: "unavailable", message: "no logbook is open"))
        }
        let order: [String?] = context.bandOrder()
        do {
            let json: String? = try await handle.run { access in
                readProbe?(Thread.isMainThread)
                let qsos: [Qso] = try access.repository.findAll(contestId: id)
                guard let breakdown = try? ScoreBreakdown.compute(fresh, qsos) else { return nil }
                return scoreJson(contestId: id, breakdown: breakdown, order: order).serialized()
            }
            guard let json else {
                return .failure(Failure(code: "failed", message: "the score cannot be computed"))
            }
            return .success(.raw(json))
        } catch {
            return .failure(Failure(code: "failed", message: "\(error)"))
        }
    }

    /// A raw CAT command: checked by `PluginCatPolicy`, sent on the active rig's lane, answered with its reply.
    private static func rawCat(_ params: [String: PluginJSON],
                               actions: PluginHostActions) async -> Result<PluginJSON, Failure> {
        guard let command = params["command"]?.stringValue else {
            return .failure(Failure(code: "invalid_params", message: "cat.send needs command"))
        }
        if let refusal = PluginCatPolicy.refusal(command, context: actions.catContext()) {
            return .failure(Failure(code: "refused", message: refusal))
        }
        let result: Result<RigRawReply, CatRawError> = await withCheckedContinuation { continuation in
            actions.rawCat(command) { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success(let reply):
            return .success(.object(["lines": .array(reply.lines.map { .string($0) }), "code": .int(Int64(reply.code))]))
        case .failure(let error):
            return .failure(Failure(code: "refused", message: error.message))
        }
    }

    /// The worked multipliers of the active contest by binding (a replay of its log, as the score is computed).
    private static func multipliers(context: PluginHostContext,
                                    readProbe: (@Sendable (Bool) -> Void)?) async -> Result<PluginJSON, Failure> {
        guard let id = context.contest().id, let fresh = context.freshSession() else {
            return .success(.null)
        }
        guard let handle = context.handle() else {
            return .failure(Failure(code: "unavailable", message: "no logbook is open"))
        }
        do {
            let json: String = try await handle.run { access in
                readProbe?(Thread.isMainThread)
                let qsos: [Qso] = try access.repository.findAll(contestId: id)
                let outcome = ContestReplay.replay(fresh, qsos)
                return multipliersJson(contestId: id, session: outcome.session).serialized()
            }
            return .success(.raw(json))
        } catch {
            return .failure(Failure(code: "failed", message: "\(error)"))
        }
    }

    nonisolated static func multipliersJson(contestId: String, session: ContestSession) -> PluginJSON {
        var list: [PluginJSON] = []
        for case let binding? in session.definition.multipliers ?? [] {
            let keys: [String] = session.tracker.keysForBinding(binding.id).compactMap { $0 }
            let label: String? = binding.label.flatMap { $0.isEmpty ? nil : $0 } ?? binding.id
            list.append(.object([
                "id": .optional(binding.id), "label": .optional(label), "worked": .int(Int64(keys.count)),
                "keys": .array(keys.map { .string($0) }), "needed": .null,
            ]))
        }
        return .object(["contestId": .string(contestId), "multipliers": .array(list)])
    }

    nonisolated static func scoreJson(contestId: String, breakdown: ScoreBreakdown, order: [String?]) -> PluginJSON {
        func cell(_ cell: ScoreBreakdown.Cell) -> [String: PluginJSON] {
            ["qsos": .int(Int64(cell.qsos)), "dupes": .int(Int64(cell.dupes)), "points": .int(cell.points),
             "mults": .int(Int64(cell.multTotal))]
        }
        let bands: [PluginJSON] = breakdown.bands(order).map { band in
            var fields: [String: PluginJSON] = cell(breakdown.band(band))
            fields["band"] = .string(band)
            return .object(fields)
        }
        let modes: [PluginJSON] = breakdown.modes.map { mode in
            var fields: [String: PluginJSON] = cell(breakdown.mode(mode))
            fields["mode"] = .string(mode)
            return .object(fields)
        }
        let score: ScoreState = breakdown.score
        return .object([
            "contestId": .string(contestId), "qsos": .int(Int64(score.qsoCount)), "dupes": .int(Int64(breakdown.total.dupes)),
            "qsoPoints": .int(score.qsoPoints), "mults": .int(Int64(score.multTotal)),
            "bonusPoints": .int(score.bonusPoints), "qtcPoints": .int(score.qtcPoints), "total": .int(score.total),
            "bands": .array(bands), "modes": .array(modes),
        ])
    }

    private static func spots(_ params: [String: PluginJSON], context: PluginHostContext) -> Result<PluginJSON, Failure> {
        let band: String? = params["band"]?.stringValue
        var list: [PluginJSON] = []
        for spot in context.spots().reversed() {
            let spotBand: String? = Band.from(frequencyHz: spot.freqHz)?.adif
            if let band, spotBand?.lowercased() != band.lowercased() {
                continue
            }
            list.append(.object([
                "dxCall": .string(spot.dxCall), "freqHz": .int(Int64(spot.freqHz)), "band": .optional(spotBand),
                "spotter": .string(spot.spotter), "comment": .string(spot.comment),
            ]))
            if list.count >= maxSpots {
                break
            }
        }
        return .success(.object(["spots": .array(list)]))
    }
}
