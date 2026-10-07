import Foundation
import Testing
@testable import MCLCore

/// Swift side of the Java parity suite (maintainer-only probe, fixture `d`): replays the input rows of `ui-d-java.json.gz` against
/// the Settings core:
///
/// - `cfg.APPLY` — `ConfigurerDraft(config:…)` of the source configuration, the edits of the row applied to the
///   draft's fields and rows, `applied(to: target, now:)`; the result encoded as `ProfileMerge.fields(of:)` and
///   canonicalized as `prof.MERGE`, the leaves that differ from the source. The `c/NN` rows decode every pool
///   configuration and pin its canonical form by SHA-256;
/// - `cfg.DIFFERS` — the eight change predicates of the same edited drafts against the target, as bits;
/// - `cfg.TABS` — `MenuConfigStore.parse` + `ConfigurerTabSpecs.build(menu:)`, `ConfigurerTab.byKey`;
/// - `cfg.ROWS` — `ConfigurerRows.numStr`, `BandSegmentDraft.toSegment`, `DigiChannelDraft.toChannel`,
///   `TransverterDraft.toEntry`, `AntennaDraft.toEntry`, `BandPlanOverlap.overlaps`, `GridLatLon.of`.
///
/// The generator runs with `user.home` in a temporary directory and writes it as `<dir>`; the default contest-data
/// directory the draft falls back to is therefore `<dir>/Library/Application Support/MacContestLogger/contest-data`
/// here. New blacklist entries get a fixed instant, written as `<now>` (Java: the instant of `applyTo`).
enum UiParityDSections {

    typealias Entry = JavaYamlParityTests.ReferenceFile
    typealias Rows = [(String, [String])]
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture
    typealias Draft = ConfigurerDraft

    static let names: [String] = ["cfg.APPLY", "cfg.DIFFERS", "cfg.TABS", "cfg.ROWS"]

    /// `AppPaths.defaultContestDataDir()` under the generator's temporary home.
    static let defaultContestDataDir = "<dir>/Library/Application Support/MacContestLogger/contest-data"

    /// The instant new blacklist entries get (any instant: it is written as `<now>`).
    static let now: JavaInstant = JavaInstant.ofEpochSecond(1_790_985_600, 123_456_000)!

    // MARK: - replay

    final class Ctx {
        var pool: [Int: AppConfig] = [:]
    }

    static func replay(_ java: Entry) throws -> Entry {
        let ctx = Ctx()
        var lines: [String] = []
        lines.reserveCapacity(java.lines.count)
        for line in java.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count >= 2, fields[1] == "in" else { continue }
            lines.append(line)
            let inputs: [String] = Array(fields.dropFirst(2))
            do {
                for (outPath, out) in try compute(java.relative, fields[0], inputs, ctx) {
                    lines.append(F.line(outPath, "out", out))
                }
            } catch {
                lines.append(F.line(fields[0], "out", ["SWIFT ERROR", String(describing: error)]))
            }
        }
        let sum: String = F.checksum(definition: nil, registry: "", lines: lines)
        return Entry(relative: java.relative, sha256: sum, lines: lines)
    }

    static func replayAll(_ reference: [Entry]) async throws -> [Entry] {
        try await withThrowingTaskGroup(of: (Int, Entry).self) { group in
            for (index, entry) in reference.enumerated() {
                group.addTask {
                    let replayed = try await JavaNetParityFixture.onGateThread(entry.relative) {
                        try replay(entry)
                    }
                    return (index, replayed)
                }
            }
            var results = [Entry?](repeating: nil, count: reference.count)
            for try await (index, entry) in group {
                results[index] = entry
            }
            return results.compactMap { $0 }
        }
    }

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if path.hasPrefix("c/"), name == "cfg.APPLY" || name == "cfg.DIFFERS" {
            return try poolRow(path, f, ctx)
        }
        switch name {
        case "cfg.APPLY": return try applyRow(path, f, ctx)
        case "cfg.DIFFERS": return try differsRow(path, f, ctx)
        case "cfg.TABS": return try tabsRow(path, f)
        case "cfg.ROWS": return try rowsRow(path, f)
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    static func text(_ field: String) -> String {
        X.text(field) ?? ""
    }

    // MARK: - configurations

    /// `c/NN`: a configuration as Jackson wrote it, decoded as `ConfigStore.load` does; out = the SHA-256 of its
    /// canonical form.
    static func poolRow(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        guard let index = Int(path.dropFirst(2)), f.count == 1 else { throw X.Malformed(text: path) }
        let config: AppConfig = try JSONDecoder().decode(AppConfig.self, from: Data(text(f[0]).utf8))
        ctx.pool[index] = config
        let canonical: String = UiParityCSections.canonical(.object(try UiParityCSections.javaFields(of: config)))
        return [(path, [JavaYamlParityTests.sha256Hex(Data(canonical.utf8))])]
    }

    static func config(_ field: String, _ ctx: Ctx) throws -> AppConfig {
        guard let index = Int(field), let config = ctx.pool[index] else { throw X.Malformed(text: "pool \(field)") }
        return config
    }

    // MARK: - draft edits

    nonisolated(unsafe) static let textFields: [String: WritableKeyPath<Draft, String>] = [
        "address1": \.address1, "address2": \.address2, "antHeight": \.antHeight, "antenna": \.antenna,
        "arrlSection": \.arrlSection, "asl": \.asl, "auReceiveBind": \.auReceiveBind,
        "autoBackupDir": \.autoBackupDir, "autoBackupKeep": \.autoBackupKeep,
        "autoBackupMinutes": \.autoBackupMinutes, "bcAppInfoTargets": \.bcAppInfoTargets,
        "bcContactsTargets": \.bcContactsTargets, "bcRadioTargets": \.bcRadioTargets,
        "bcScoreTargets": \.bcScoreTargets, "brokerHost": \.brokerHost, "call": \.call,
        "callHistoryFile": \.callHistoryFile, "city": \.city, "clApiKey": \.clApiKey, "clCallsign": \.clCallsign,
        "clEmail": \.clEmail, "clPassword": \.clPassword, "club": \.club, "clusterPort": \.clusterPort,
        "contestDataDir": \.contestDataDir, "country": \.country, "cqZone": \.cqZone, "cwPitch": \.cwPitch,
        "cwPort": \.cwPort, "cwSpeed": \.cwSpeed, "cwSpeedStep": \.cwSpeedStep, "dataMode": \.dataMode,
        "device": \.device, "email": \.email, "fldigiHost": \.fldigiHost, "fldigiPort": \.fldigiPort,
        "footswitchAction": \.footswitchAction, "footswitchPin": \.footswitchPin, "footswitchPort": \.footswitchPort,
        "grid": \.grid, "hamQthPassword": \.hamQthPassword, "hamQthUsername": \.hamQthUsername, "host": \.host,
        "ituZone": \.ituZone, "language": \.language, "license": \.license, "mapScheme": \.mapScheme,
        "minSkimmers": \.minSkimmers, "modeAlways": \.modeAlways, "modeRule": \.modeRule, "name": \.name,
        "nrReceiveBind": \.nrReceiveBind, "ntpServer": \.ntpServer, "operator": \.`operator`,
        "otrspPort": \.otrspPort, "password": \.password, "power": \.power, "qrzPassword": \.qrzPassword,
        "qrzUsername": \.qrzUsername, "radioMode": \.radioMode, "repeatSeconds": \.repeatSeconds,
        "rig2Host": \.rig2Host, "rig2Port": \.rig2Port, "rigModelLabel": \.rigModelLabel, "rigPort": \.rigPort,
        "rotatorHost": \.rotatorHost, "rotatorPort": \.rotatorPort, "rotorUdpHost": \.rotorUdpHost,
        "rotorUdpName": \.rotorUdpName, "rotorUdpPort": \.rotorUdpPort, "roverQth": \.roverQth, "rxAudio": \.rxAudio,
        "scpFile": \.scpFile, "selfSpotThresholdHz": \.selfSpotThresholdHz, "spotBufferMinutes": \.spotBufferMinutes,
        "srMinutes": \.srMinutes, "srUrl": \.srUrl, "stateRegion": \.stateRegion, "stationId": \.stationId,
        "stationTxRx": \.stationTxRx, "themeAccent": \.themeAccent, "themeMode": \.themeMode, "ttsVoice": \.ttsVoice,
        "tuneStepCw": \.tuneStepCw, "tuneStepSsb": \.tuneStepSsb, "username": \.username, "vkInput": \.vkInput,
        "vkLettersPath": \.vkLettersPath, "vkMaxRecord": \.vkMaxRecord, "vkOutput": \.vkOutput,
        "vkPttDelay": \.vkPttDelay, "vkWavDir": \.vkWavDir, "wheelStepHz": \.wheelStepHz,
        "wheelStepShiftHz": \.wheelStepShiftHz, "wxReceiveBind": \.wxReceiveBind, "wxSendTargets": \.wxSendTargets,
        "zip": \.zip,
    ]

    nonisolated(unsafe) static let boolFields: [String: WritableKeyPath<Draft, Bool>] = [
        "antennaViaRig": \.antennaViaRig, "auReceiveEnabled": \.auReceiveEnabled, "autoReload": \.autoReload,
        "autoSplit": \.autoSplit, "bcAppInfoEnabled": \.bcAppInfoEnabled, "bcContactsEnabled": \.bcContactsEnabled,
        "bcRadioEnabled": \.bcRadioEnabled, "bcScoreEnabled": \.bcScoreEnabled, "beepOnDupe": \.beepOnDupe,
        "clEnabled": \.clEnabled, "clusterEnabled": \.clusterEnabled, "cwCutNumbers": \.cwCutNumbers,
        "cwLeadingZeros": \.cwLeadingZeros, "esmEnabled": \.esmEnabled, "esmSpCallOnce": \.esmSpCallOnce,
        "esmWorkDupes": \.esmWorkDupes, "hamQthEnabled": \.hamQthEnabled, "mapPolitical": \.mapPolitical,
        "nrReceiveEnabled": \.nrReceiveEnabled, "ntpCorrect": \.ntpCorrect, "qrzEnabled": \.qrzEnabled,
        "ritClearAfterLog": \.ritClearAfterLog, "rttyAfsk": \.rttyAfsk, "runAutoSwitch": \.runAutoSwitch,
        "runOnCqFrequency": \.runOnCqFrequency, "serialServer": \.serialServer, "shareSpots": \.shareSpots,
        "showBandPlan": \.showBandPlan, "srBreakdown": \.srBreakdown, "srEnabled": \.srEnabled, "tls": \.tls,
        "vkPttViaCat": \.vkPttViaCat, "wxReceiveEnabled": \.wxReceiveEnabled, "wxSendEnabled": \.wxSendEnabled,
    ]

    nonisolated(unsafe) static let intFields: [String: WritableKeyPath<Draft, Int>] = [
        "baud": \.baud, "dataBits": \.dataBits, "rigModel": \.rigModel, "stopBits": \.stopBits,
    ]

    typealias EnumSetter = @Sendable (inout Draft, String) throws -> Void

    /// Enum fields: the constant as Jackson writes it, decoded by the configuration's own `Decodable`.
    static let enumFields: [String: EnumSetter] = [
        "rigMode": { $0.rigMode = try decoded($1) },
        "parity": { $0.parity = try decoded($1) },
        "flow": { $0.flow = try decoded($1) },
        "dtr": { $0.dtr = try decoded($1) },
        "rts": { $0.rts = try decoded($1) },
        "interlock": { $0.interlock = try decoded($1) },
        "stationType": { $0.stationType = try decoded($1) },
        "ruleEnforcement": { $0.ruleEnforcement = try decoded($1) },
        "cwMethod": { $0.cwMethod = try decoded($1) },
        "cwCutStyle": { $0.cwCutStyle = try decoded($1) },
        "digiEngine": { $0.digiEngine = try decoded($1) },
    ]

    static func decoded<T: Decodable>(_ name: String) throws -> T {
        let data: Data = try JSONEncoder().encode([name])
        let values: [T] = try JSONDecoder().decode([T].self, from: data)
        guard let value = values.first else { throw X.Malformed(text: name) }
        return value
    }

    nonisolated(unsafe) static let functionKeyLists: [String: WritableKeyPath<Draft, [FunctionKeyDraft]>] = [
        "cwRun": \.cwRun, "cwSp": \.cwSp, "vkRun": \.vkRun, "vkSp": \.vkSp, "digiRun": \.digiRun, "digiSp": \.digiSp,
    ]

    nonisolated(unsafe) static let textLists: [String: WritableKeyPath<Draft, [String]>] = [
        "blacklistedCalls": \.blacklistedCalls, "blacklistedSpotters": \.blacklistedSpotters,
        "hamQthCallModes": \.hamQthCallModes, "hamQthFetchFields": \.hamQthFetchFields,
        "qrzCallModes": \.qrzCallModes, "qrzFetchFields": \.qrzFetchFields,
    ]

    /// One edit (`SettingsSections.Op`): kind, target, index, sub-field, value.
    static func edit(_ draft: inout Draft, _ op: ArraySlice<String>) throws {
        let fields = Array(op)
        guard fields.count == 5 else { throw X.Malformed(text: "edit \(fields)") }
        let kind = fields[0]
        let target = fields[1]
        let index: Int = Int(fields[2]) ?? -1
        let sub: String = text(fields[3])
        let value: String = text(fields[4])
        switch kind {
        case "S":
            guard let key = textFields[target] else { throw X.Malformed(text: "text field \(target)") }
            draft[keyPath: key] = value
        case "B":
            guard let key = boolFields[target] else { throw X.Malformed(text: "switch \(target)") }
            draft[keyPath: key] = value == "1"
        case "I":
            guard let key = intFields[target], let number = Int(value) else { throw X.Malformed(text: "int \(target)") }
            draft[keyPath: key] = number
        case "E":
            guard let setter = enumFields[target] else { throw X.Malformed(text: "enum \(target)") }
            try setter(&draft, value)
        case "RA":
            try addRow(&draft, target)
        case "RR":
            try removeRow(&draft, target, index)
        case "RB":
            try setRowSwitch(&draft, target, index, value == "1")
        case "RS":
            try setRowText(&draft, target, index, sub, value)
        case "LA", "LR", "LS":
            guard let key = textLists[target] else { throw X.Malformed(text: "list \(target)") }
            if kind == "LA" {
                draft[keyPath: key].append(value)
            } else if kind == "LR" {
                draft[keyPath: key].remove(at: index)
            } else {
                draft[keyPath: key][index] = value
            }
        case "KP":
            draft.keyOverrides[sub] = value
        case "KR":
            draft.keyOverrides.removeValue(forKey: sub)
        default:
            throw X.Malformed(text: "edit kind \(kind)")
        }
    }

    static func addRow(_ draft: inout Draft, _ list: String) throws {
        switch list {
        case "dxFavorites": draft.addDxFavorite()
        case "antennas": draft.antennas.append(AntennaDraft(AntennaEntry()))
        case "transverters": draft.transverters.append(TransverterDraft(TransverterEntry()))
        default: throw X.Malformed(text: "add row \(list)")
        }
    }

    static func removeRow(_ draft: inout Draft, _ list: String, _ index: Int) throws {
        switch list {
        case "dxFavorites": draft.dxFavorites.remove(at: index)
        case "antennas": draft.antennas.remove(at: index)
        case "transverters": draft.transverters.remove(at: index)
        default: throw X.Malformed(text: "remove row \(list)")
        }
    }

    static func setRowSwitch(_ draft: inout Draft, _ list: String, _ index: Int, _ value: Bool) throws {
        switch list {
        case "dxFavorites": draft.dxFavorites[index].isParallel = value
        case "transverters": draft.transverters[index].enabled = value
        default: throw X.Malformed(text: "row switch \(list)")
        }
    }

    static func setRowText(_ draft: inout Draft, _ list: String, _ index: Int, _ sub: String, _ value: String) throws {
        if let key = functionKeyLists[list] {
            switch sub {
            case "label": draft[keyPath: key][index].label = value
            case "text": draft[keyPath: key][index].text = value
            default: throw X.Malformed(text: "\(list).\(sub)")
            }
            return
        }
        switch (list, sub) {
        case ("dxFavorites", "name"): draft.dxFavorites[index].name = value
        case ("dxFavorites", "host"): draft.dxFavorites[index].host = value
        case ("dxFavorites", "port"): draft.dxFavorites[index].port = value
        case ("dxFavorites", "login"): draft.dxFavorites[index].login = value
        case ("dxFavorites", "password"): draft.dxFavorites[index].password = value
        case ("antennas", "code"): draft.antennas[index].code = value
        case ("antennas", "name"): draft.antennas[index].name = value
        case ("antennas", "bands"): draft.antennas[index].bands = value
        case ("antennas", "sector"): draft.antennas[index].sector = value
        case ("transverters", "name"): draft.transverters[index].name = value
        case ("transverters", "ifLow"): draft.transverters[index].ifLow = value
        case ("transverters", "ifHigh"): draft.transverters[index].ifHigh = value
        case ("transverters", "offset"): draft.transverters[index].offset = value
        default: throw X.Malformed(text: "\(list).\(sub)")
        }
    }

    /// A case row: source, target, number of edits, edits (5 fields each) → the edited draft and the target.
    static func draft(_ f: [String], _ ctx: Ctx) throws -> (Draft, AppConfig, AppConfig) {
        guard f.count >= 3, let count = Int(f[2]), f.count == 3 + 5 * count else { throw X.Malformed(text: "\(f)") }
        let source: AppConfig = try config(f[0], ctx)
        let target: AppConfig = try config(f[1], ctx)
        var draft = Draft(
            config: source, bandSegments: [], digi: DigiFreqFile.Table(channels: []),
            defaultContestDataDir: defaultContestDataDir)
        for index in 0..<count {
            let start: Int = 3 + 5 * index
            try edit(&draft, f[start..<(start + 5)])
        }
        return (draft, source, target)
    }

    // MARK: - cfg.APPLY

    static func applyRow(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let (draft, source, target) = try draft(f, ctx)
        let result: AppConfig = draft.applied(to: target, now: now)
        let mine: [String: String] = leaves(stampNow(.object(try ProfileMerge.fields(of: result))))
        let theirs: [String: String] = leaves(.object(try ProfileMerge.fields(of: source)))
        let paths: [String] = Set(mine.keys).union(theirs.keys).sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        var changed: Rows = []
        for leaf in paths where mine[leaf] != theirs[leaf] {
            changed.append((path + leaf, [F.tx(mine[leaf] ?? "<absent>")]))
        }
        return [(path, [String(changed.count)])] + changed
    }

    /// Blacklist entries stamped with `now` → `<now>`.
    static func stampNow(_ json: ProfileJson) -> ProfileJson {
        guard case .object(var root) = json, case .object(var dx)? = root["dxCluster"] else { return json }
        let stamp: String = now.toString()
        for list in ["callBlacklist", "spotterBlacklist"] {
            guard case .array(let entries)? = dx[list] else { continue }
            dx[list] = .array(entries.map { entry in
                guard case .object(var fields) = entry, fields["addedAtUtc"] == .string(stamp) else { return entry }
                fields["addedAtUtc"] = .string("<now>")
                return .object(fields)
            })
        }
        root["dxCluster"] = .object(dx)
        return .object(root)
    }

    /// The leaves of the canonical form (`SettingsSections.leaves`).
    static func leaves(_ json: ProfileJson) -> [String: String] {
        var out: [String: String] = [:]
        leaves(json, "", &out)
        return out
    }

    static func leaves(_ json: ProfileJson, _ path: String, _ out: inout [String: String]) {
        switch json {
        case .object(let fields):
            let keys: [String] = fields.keys.filter { fields[$0] != .null }
            if keys.isEmpty { out[path] = "{}" }
            for key in keys {
                leaves(fields[key] ?? .null, path + "/" + F.tx(key), &out)
            }
        case .array(let items):
            if items.isEmpty { out[path] = "[]" }
            for (index, item) in items.enumerated() {
                leaves(item, path + "/" + String(index), &out)
            }
        default:
            out[path] = UiParityCSections.canonical(json)
        }
    }

    // MARK: - cfg.DIFFERS

    static func differsRow(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let (draft, _, target) = try draft(f, ctx)
        let bits: [Bool] = [
            draft.rigDiffers(target.rig), draft.clusterDiffers(target.cluster),
            draft.scoringStationDiffers(target.station),
            draft.contestDirDiffers(target, defaultDir: defaultContestDataDir),
            draft.broadcastDiffers(target.broadcast), draft.wsjtxDiffers(target.wsjtx),
            draft.n1mmDiffers(target.n1mmRecv), draft.adifUdpDiffers(target.adifUdp),
        ]
        return [(path, [bits.map(X.b).joined()])]
    }

    // MARK: - cfg.TABS

    static func tabsRow(_ path: String, _ f: [String]) throws -> Rows {
        guard f.count == 1 else { throw X.Malformed(text: path) }
        if path.hasPrefix("k/") {
            guard let tab = ConfigurerTab.byKey(text(f[0])), tab != .plugins else { return [(path, ["~", "~"])] }
            return [(path, [tab.key, F.tx(tab.titleKey)])]
        }
        let menu: MenuConfig = MenuConfigStore.parse(Data(text(f[0]).utf8))
        // The Plugins tab exists only in the Swift version (window plugins); the Java measurement never had it.
        let specs: [ConfigurerTabSpec] = ConfigurerTabSpecs.build(menu: menu).filter { $0.tab != .plugins }
        var rows: Rows = [(path, [String(specs.count)])]
        for (index, spec) in specs.enumerated() {
            let state: String = spec.state.rawValue.uppercased()
            rows.append((path + "/" + F.pad(index, 2), [spec.tab.key, F.tx(spec.labelKey), state]))
        }
        return rows
    }

    // MARK: - cfg.ROWS

    static func bits(_ value: Double?) -> String {
        guard let value else { return "~" }
        return String(value.bitPattern, radix: 16)
    }

    static func rowsRow(_ path: String, _ f: [String]) throws -> Rows {
        switch path.split(separator: "/").first ?? "" {
        case "n":
            guard let raw = UInt64(f[0], radix: 16) else { throw X.Malformed(text: path) }
            return [(path, [F.tx(ConfigurerRows.numStr(Double(bitPattern: raw)))])]
        case "s":
            var row = BandSegmentDraft(region: text(f[0]), mode: text(f[1]), fromKhz: 0, toKhz: 0)
            row.fromKhz = text(f[2])
            row.toKhz = text(f[3])
            guard let segment = row.toSegment() else { return [(path, [bits(row.fromVal()), bits(row.toVal()), "~", "~", "~", "~"])] }
            return [(path, [bits(row.fromVal()), bits(row.toVal()), F.tx(segment.region), F.tx(segment.mode),
                            bits(segment.fromKhz), bits(segment.toKhz)])]
        case "dc":
            var row = DigiChannelDraft(mode: "X", fromKhz: 0, toKhz: 0)
            row.mode = text(f[0])
            row.fromKhz = text(f[1])
            row.toKhz = text(f[2])
            guard let channel = row.toChannel() else { return [(path, ["~"])] }
            return [(path, [F.tx(channel.mode), bits(channel.fromKhz), bits(channel.toKhz)])]
        case "t":
            return [(path, transverter(f))]
        case "a":
            var row = AntennaDraft(AntennaEntry())
            row.code = text(f[0])
            row.name = text(f[1])
            row.bands = text(f[2])
            row.sector = text(f[3])
            let entry: AntennaEntry = row.toEntry()
            return [(path, [String(entry.code), F.tx(entry.name), F.tx(entry.bands), F.tx(entry.sector)])]
        case "o":
            return [(path, [try overlapBits(f)])]
        case "g":
            guard let latLon = GridLatLon.of(text(f[0])) else { return [(path, ["~"])] }
            return [(path, [F.tx(latLon.latitude), F.tx(latLon.longitude)])]
        default:
            throw X.Malformed(text: "unknown row \(path)")
        }
    }

    static func transverter(_ f: [String]) -> [String] {
        var row = TransverterDraft(TransverterEntry())
        row.name = text(f[0])
        row.ifLow = text(f[1])
        row.ifHigh = text(f[2])
        row.offset = text(f[3])
        row.enabled = f[4] == "1"
        guard let entry = row.toEntry() else { return ["~"] }
        return [F.tx(entry.name), String(entry.ifLowKHz), String(entry.ifHighKHz), String(entry.offsetKHz),
                X.b(entry.enabled)]
    }

    static func overlapBits(_ f: [String]) throws -> String {
        let count: Int = try X.int(f[0])
        guard f.count == 1 + 3 * count else { throw X.Malformed(text: "\(f)") }
        var rows: [BandSegmentDraft] = []
        for index in 0..<count {
            var row = BandSegmentDraft(region: text(f[1 + 3 * index]), mode: "CW", fromKhz: 0, toKhz: 0)
            row.fromKhz = text(f[2 + 3 * index])
            row.toKhz = text(f[3 + 3 * index])
            rows.append(row)
        }
        return rows.indices.map { X.b(BandPlanOverlap.overlaps(rows, $0)) }.joined()
    }
}
