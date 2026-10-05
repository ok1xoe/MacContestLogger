import Foundation
import Testing
@testable import MCLCore

/// The tool sections of the Java parity suite (`UiParityHSections`): sked and TOUR watches, QTC series, band notes, move
/// multipliers, the map, propagation and multiplier grid, and the pileup simulator. The text of an input row is the
/// scenario (a script row sets a state up, a step row asks for one result).
extension UiParityHSections {

    static func double(_ text: String) throws -> Double {
        try JavaNetParityValues.double(text)
    }

    static func float(_ text: String) throws -> Float {
        guard let value = Float(text) else { throw X.Malformed(text: text) }
        return value
    }

    // MARK: - sked.WATCH

    private static func relativeTime(_ time: String) -> Bool {
        let trimmed: String = JavaText.trim(time)
        let units: [UInt16] = Array(trimmed.utf16)
        let digits = units.filter { $0 != 0x3A }
        guard (3...4).contains(digits.count), digits.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return false }
        let colons: Int = units.count - digits.count
        return colons == 0 || (colons == 1 && units[units.count - 3] == 0x3A) || (colons == 1 && units.count >= 3
            && units[units.count - 3] == 0x3A)
    }

    /// The `HHmm` of a sked clock text is not part of the comparison (it depends on the clock): `v 1234 UTC` →
    /// `v <hhmm> UTC`.
    private static func normalizedClock(_ text: String) -> String {
        var out = ""
        let units: [Character] = Array(text)
        var i = 0
        while i < units.count {
            if i + 12 < units.count, units[i] == "v", units[i + 1] == " ",
               units[(i + 2)..<(i + 6)].allSatisfy(\.isNumber), String(units[(i + 6)..<(i + 11)]) == " UTC " {
                out += "v <hhmm> UTC "
                i += 11
            } else {
                out.append(units[i])
                i += 1
            }
        }
        return out
    }

    static func sked(_ area: String, _ input: String, _ ctx: Ctx) throws -> String {
        let now: JavaInstant = P.t0Instant
        switch area {
        case "skedAdd":
            if input == "no-contest" { return "false|" + SkedEditing.noActiveContestText(P.cs) }
            if input == "not-in-database" { return "false|" + SkedEditing.contestNotInDatabaseText(P.cs) }
            let f: [String] = parts(input)
            let call: String = try field(f, 0)
            let freq: Int = try X.int(try field(f, 1))
            let mode: String = try field(f, 2)
            let time: String = try field(f, 3)
            let note: String = try field(f, 4)
            switch SkedEditing.add(call: call, freqHz: freq, mode: mode, timeText: time, note: note, now: now) {
            case .success(let entry):
                let atText: String = relativeTime(time) ? "tod=" + String(entry.atUtc.dropFirst(11).prefix(5)) : entry.atUtc
                let fields: [String] = [entry.call, String(entry.freqHz), entry.mode, atText, entry.note]
                return "true|" + SkedEditing.addedText(entry) + "|1|" + fields.joined(separator: ",")
            case .failure(let error):
                return "false|" + error.text(P.cs) + "|0|-"
            }
        case "skedWatch":
            if input.hasPrefix("script|") {
                try runSkedScript(String(input.dropFirst("script|".count)), now, ctx)
                return "ok"
            }
            if input.hasPrefix("tick1#") {
                let index: Int = try X.int(String(input.dropFirst("tick1#".count)))
                guard ctx.skedFirst.indices.contains(index) else { throw X.Malformed(text: input) }
                return normalizedClock(ctx.skedFirst[index])
            }
            switch input {
            case "status": return normalizedClock(ctx.skedStatus)
            case "tick2-new": return String(ctx.skedSecond)
            case "revision": return String(ctx.skedFirst.count)
            default: throw X.Malformed(text: input)
            }
        case "tourWatch":
            if input.hasPrefix("script|") {
                try runTourScript(String(input.dropFirst("script|".count)), ctx)
                return "ok"
            }
            if input == "sessions" { return ctx.tourSessions }
            if input.hasSuffix("-status") {
                let name: String = String(input.dropLast("-status".count))
                guard let messages = ctx.tourMessages[name] else { throw X.Malformed(text: input) }
                return messages.last.map { TourWatch.statusLine($0) } ?? ""
            }
            if input.hasSuffix("-count") {
                let name: String = String(input.dropLast("-count".count))
                guard let messages = ctx.tourMessages[name] else { throw X.Malformed(text: input) }
                return String(messages.count)
            }
            let p: [String] = parts(input, "#")
            guard p.count == 2, let messages = ctx.tourMessages[p[0]], let index = Int(p[1]),
                  messages.indices.contains(index) else { throw X.Malformed(text: input) }
            return messages[index]
        default:
            throw X.Malformed(text: "area \(area)")
        }
    }

    /// `call,freq,mode,seconds|text,note,sameIdAsTheFirst;…` — two ticks of the sked loop 15 s apart.
    private static func runSkedScript(_ spec: String, _ now: JavaInstant, _ ctx: Ctx) throws {
        var skeds: [SkedEntry] = []
        for item in spec.split(separator: ";", omittingEmptySubsequences: false) {
            let f: [String] = item.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let at: String
            if let seconds = Int64(f[3]), let moved = now.plus(seconds: seconds) {
                at = moved.toString()
            } else {
                at = f[3]
            }
            var entry = SkedEntry(call: f[0], freqHz: try X.int(f[1]), mode: f[2], atUtc: at, note: f[4])
            if f[5] == "1", let first = skeds.first { entry.id = first.id }
            skeds.append(entry)
        }
        var watch = SkedWatch()
        let first: [String] = watch.due(skeds: skeds, now: now)
        ctx.skedFirst = first
        ctx.skedStatus = SkedWatch.statusLine(first.last ?? "")
        ctx.skedSecond = watch.due(skeds: skeds, now: now).count
    }

    /// `A=start/duration,…;name=A,B,…;…` — one tour per name at each tick (`-` = none; `name*` = no active contest).
    private static func runTourScript(_ spec: String, _ ctx: Ctx) throws {
        let sections: [String] = parts(spec, ";")
        var tours: [String: Tour] = [:]
        for item in sections[0].split(separator: ",") {
            let pair = item.split(separator: "=").map(String.init)
            let numbers = pair[1].split(separator: "/").map { Int64($0) }
            guard numbers.count == 2, let start = numbers[0], let duration = numbers[1] else {
                throw X.Malformed(text: String(item))
            }
            tours[pair[0]] = try Tour(startMinute: Int(start), durationMinutes: Int(duration))
        }
        for rig in sections.dropFirst() {
            let pair = rig.split(separator: "=").map(String.init)
            var name: String = pair[0]
            var active = true
            if name.hasSuffix("*") {
                name.removeLast()
                active = false
            }
            var watch = TourWatch()
            var messages: [String] = []
            for tick in pair[1].split(separator: ",") {
                let tour: Tour? = tick == "-" ? nil : tours[String(tick)]
                if let text = watch.tick(tour: tour, now: P.t0, active: active, translate: P.cs) {
                    messages.append(text)
                }
            }
            ctx.tourMessages[name] = messages
        }
        let sessions: [String] = ["A", "B", "C"].map { String(tours[$0]?.session(at: P.t0) ?? 0) }
        ctx.tourSessions = "[" + sessions.joined(separator: ", ") + "]"
    }

    // MARK: - qtc.SESSION

    private static func qtcRows(_ qtcs: [QtcRecord]) -> String {
        var out = ""
        for q in qtcs {
            let fields: [String] = [String(q.sent), q.partnerCall, String(q.groupNr), String(q.groupSize), q.qsoTime,
                                    q.qsoCall, String(q.qsoSerial), String(q.freqHz), q.mode ?? "<null>"]
            out += fields.joined(separator: ",") + ";"
        }
        return out
    }

    private static func planLines(_ text: String) throws -> [QtcPlanner.Line] {
        try text.split(separator: ";", omittingEmptySubsequences: true).map { item in
            guard let line = QtcPlanner.parseLine(String(item)) else { throw X.Malformed(text: String(item)) }
            return line
        }
    }

    static func qtc(_ area: String, _ input: String, _ ctx: Ctx) throws -> String {
        let environment: Environment = ctx.environment
        switch area {
        case "qtcSave":
            let f: [String] = parts(input)
            let contest: String = try field(f, 0)
            let sent: Bool = try field(f, 2) == "true"
            let partner: String = try field(f, 3)
            let group: Int = try X.int(try field(f, 4))
            let lines: [QtcPlanner.Line] = try planLines(try field(f, 5))
            let rigMode: String? = try field(f, 6) == "-" ? nil : try field(f, 6)
            let config: ContestDefinition.Qtc? = try environment.base.contest(id: contest).scoring?.qtc
            var state: QtcState = ctx.qtcStates[contest] ?? QtcState()
            if let failure = QtcSession.validate(partner: partner, lines: lines, qtcs: state.records, config: config,
                                                 translate: P.cs) {
                if config == nil { return "false|" + failure }
                return "false|" + failure + "|" + String(state.records.count) + "|next="
                    + String(QtcSession.nextGroup(qtcs: state.records)) + "|" + qtcRows(state.records)
            }
            var made: [QtcRecord] = QtcSession.records(sent: sent, partner: partner, groupNr: group, lines: lines,
                                                       contestId: contest, now: P.t0, freqHz: 14_025_000, rigMode: rigMode)
            for index in made.indices {
                made[index].id = state.nextId
                state.nextId += 1
            }
            state.records += made
            ctx.qtcStates[contest] = state
            let status: String = QtcSession.savedText(sent: sent, groupNr: group, count: lines.count, partner: partner,
                                                      total: state.records.count, translate: P.cs)
            return "true|" + status + "|" + String(state.records.count) + "|next="
                + String(QtcSession.nextGroup(qtcs: state.records)) + "|" + qtcRows(state.records)
        case "qtcRemaining":
            let f: [String] = parts(input)
            let config = try #require(try environment.base.contest(id: "wae-cw").scoring?.qtc)
            let records: [QtcRecord] = ctx.qtcStates["wae-cw"]?.records ?? []
            let left: Int = QtcPlanner.remainingFor(JavaText.trim(try field(f, 1)), records, config.maxPerStationOrDefault)
            return "\(left)|\(config.maxPerStationOrDefault)|\(config.groupSizeOrDefault)"
        case "qtcDelete":
            var state: QtcState = ctx.qtcStates["wae-cw"] ?? QtcState()
            guard !state.records.isEmpty else { throw X.Malformed(text: "nothing to delete") }
            state.records.removeFirst()
            ctx.qtcStates["wae-cw"] = state
            return qtcRows(state.records)
        case "qtcRow":
            let f: [String] = parts(input, ",")
            let record = QtcRecord(contestId: "wae-cw", sent: try field(f, 0) == "true", partnerCall: try field(f, 1),
                                   groupNr: try X.int(try field(f, 2)), groupSize: try X.int(try field(f, 3)),
                                   qsoTime: try field(f, 4), qsoCall: try field(f, 5), qsoSerial: try X.int(try field(f, 6)),
                                   at: P.t0, freqHz: try X.int64(try field(f, 7)), mode: try field(f, 8))
            return QtcSession.rowText(record)
        case "qtcParse":
            let parsed: QtcSession.Parsed = QtcSession.parseLines(input)
            let good: String = parsed.lines.map { "\($0.time)/\($0.call)/\($0.serial) " }.joined()
            return "n=\(parsed.entries.count) good=\(good)bad=\(parsed.bad.joined(separator: " | ")) canSave=\(parsed.canSave)"
        case "qtcGroup":
            return String(QtcSession.receivedGroupNr(input))
        case "noteParse":
            let f: [String] = parts(input)
            guard let note = BandNotesEditing.parse(freq: try field(f, 0), text: try field(f, 1)) else { return "bad" }
            return "ok|\(note.band)|\(P.doubleBits(note.freqKHz))|\(note.text)"
        case "noteSorted":
            let f: [String] = parts(input)
            let bits: Int64 = try X.int64(try field(f, 1))
            let note = BandNote(band: try field(f, 0), freqKHz: Double(bitPattern: UInt64(bitPattern: bits)),
                                text: try field(f, 2))
            return BandNotesEditing.rowText(note)
        case "noteFreqField":
            return BandNotesEditing.frequencyFieldText(tunedFreqHz: try X.int64(input))
        case "move":
            let f: [String] = parts(input)
            let call: String = try field(f, 0)
            let mode: Mode? = try field(f, 1) == "null" ? nil : Mode(rawValue: try field(f, 1))
            let bandText: String = try field(f, 2)
            let cq: Int64 = try X.int64(try field(f, 3))
            let last: Int64 = try X.int64(try field(f, 4))
            let q: Qso = P.qso(call, "20m", mode, "599 14")
            let band: Band? = Band.from(adif: bandText)
            let hz: Int64? = band.flatMap { MoveRequest.frequencyHz(band: $0, cq: cq == 0 ? nil : cq,
                                                                    last: last == 0 ? nil : last) }
            let request = MoveRequest.request(qso: q, bandAdif: bandText, hz: hz, translate: P.cs)
            let moveHz: String = band == nil ? "-" : (hz.map { String($0) } ?? "null")
            let keyed: String = request?.cwText.map { $0 + " @60" } ?? ""
            return "hz=\(moveHz)|keyed=\(keyed)|status=\(request?.status ?? "")"
        case "moveCand":
            return try moveCandidates(input, ctx)
        default:
            throw X.Malformed(text: "area \(area)")
        }
    }

    private static func candidateText(_ env: SpotAnalysisFixture.Environment, _ q: Qso) -> String {
        env.runtime.moveCandidates(q, at: SpotAnalysisFixture.at).map {
            let mults: String = $0.newMults.map { $0 ?? "null" }.joined(separator: ", ")
            return "\($0.band):[\(mults)]:\($0.points)"
        }.joined(separator: " ")
    }

    /// `none|call|band|mode|exchange`, `setup|contest|call band mode exchange;…`, `cqww|…`, `deactivate`,
    /// `deactivated|…`.
    private static func moveCandidates(_ input: String, _ ctx: Ctx) throws -> String {
        let f: [String] = parts(input)
        if ctx.moveEnv == nil { ctx.moveEnv = try SpotAnalysisFixture.environment() }
        let env: SpotAnalysisFixture.Environment = try #require(ctx.moveEnv)
        switch try field(f, 0) {
        case "setup":
            try env.activate(try field(f, 1))
            for item in try field(f, 2).split(separator: ";") {
                let g: [String] = item.split(separator: " ", maxSplits: 3).map(String.init)
                let exchange: [String] = g[3].split(separator: " ").map(String.init)
                try env.log(g[0], g[1], g[2], ("rst", exchange[0]), ("zone", exchange[1]))
            }
            return "ok"
        case "deactivate":
            env.runtime.deactivate()
            return "ok"
        default:
            let band: String? = try field(f, 2) == "~" ? nil : try field(f, 2)
            let q: Qso = P.qso(try field(f, 1), band, Mode(rawValue: try field(f, 3)), try field(f, 4))
            return candidateText(env, q)
        }
    }

    // MARK: - map.WORLD

    private static func fieldSpec(_ text: String) throws -> [String: MultCell] {
        var out: [String: MultCell] = [:]
        for item in text.split(separator: ",") {
            let pair = item.split(separator: "=").map(String.init)
            guard let cell = MultCell(rawValue: pair[1]) else { throw X.Malformed(text: String(item)) }
            out[pair[0]] = cell
        }
        return out
    }

    private static func propagationText(_ view: PropagationRows.View) -> String {
        switch view {
        case .message(let text):
            return "msg:" + text
        case .table(let table):
            var out: String = table.title + "|hour=\(table.nowHour)|"
            for row in table.rows {
                out += row.band.adif + "="
                for level in row.levels {
                    switch level {
                    case .open: out += "O"
                    case .marginal: out += "M"
                    case .closed: out += "C"
                    }
                }
                out += " "
            }
            return out.trimmingCharacters(in: .whitespaces)
        }
    }

    static func world(_ area: String, _ input: String, _ ctx: Ctx) throws -> String {
        let corpus: Corpus = ctx.environment.corpus
        let f: [String] = parts(input)
        switch area {
        case "fieldAt":
            return WorldMapModel.fieldAt(lon: try double(try field(f, 0)), lat: try double(try field(f, 1))) ?? "null"
        case "rank":
            guard let cell = MultCell(rawValue: input) else { throw X.Malformed(text: input) }
            return String(WorldMapModel.rank(cell))
        case "px":
            let model = WorldMapModel(centerLon: try double(try field(f, 0)))
            return P.bits(model.px(lon: try double(try field(f, 2)), width: try float(try field(f, 1))))
        case "py":
            return P.bits(WorldMapModel.py(lat: try double(try field(f, 1)), height: try float(try field(f, 0))))
        case "dxccDots":
            return try dxccDots(input)
        case "station":
            let position = WorldMapModel.stationPosition(latitude: try field(f, 0), longitude: try field(f, 1),
                                                         gridSquare: try field(f, 2))
            return position.map { "\(P.javaDouble($0.lat)),\(P.javaDouble($0.lon))" } ?? "null"
        case "geoRings":
            let geo = WorldMapGeo.fromData(Data(corpus.geo.utf8))
            return "\(geo.rings.count)|[" + geo.ringGroups.map { String($0) }.joined(separator: ", ") + "]"
        case "geoRing":
            let geo = WorldMapGeo.fromData(Data(corpus.geo.utf8))
            let model = WorldMapModel(centerLon: try double(try field(f, 0)))
            let index: Int = try X.int(try field(f, 1))
            guard geo.rings.indices.contains(index) else { throw X.Malformed(text: input) }
            return geoRing(model, geo.rings[index])
        case "night", "sun":
            let t: Int64 = try X.int64(try field(f, 0))
            let model = WorldMapModel(centerLon: try double(try field(f, 1)))
            if area == "sun" {
                let marker = model.sunMarker(width: 90, height: 52, epochMillis: t)
                return marker.map { "\(P.bits($0.x)).\(P.bits($0.y))" } ?? "none"
            }
            let columns = model.terminatorColumns(width: 90, height: 52, epochMillis: t)
            return columns.map { "\($0.x):\(P.bits($0.y0)):\(P.bits($0.y1))" }.joined(separator: " ")
        case "fieldRects":
            let model = WorldMapModel(centerLon: try double(try field(f, 0)))
            let fields: [String: MultCell] = try fieldSpec(try field(f, 1))
            return model.fieldRects(fieldStates: fields, width: 900, height: 520).map {
                "\($0.key)=\($0.cell.rawValue)@\(P.bits($0.x)).\(P.bits($0.y)).\(P.bits($0.width)).\(P.bits($0.height))"
            }.joined(separator: " ")
        case "gridLines":
            let model = WorldMapModel(centerLon: try double(input))
            let vertical = model.verticalGridLines(width: 900).map { P.bits($0) }
            let horizontal = model.horizontalGridLines(height: 520).map { P.bits($0) }
            return (vertical + horizontal).joined(separator: " ")
        case "fieldLabels":
            let model = WorldMapModel(centerLon: try double(try field(f, 0)))
            let fields: [String: MultCell] = try fieldSpec(try field(f, 1))
            return model.fieldLabels(fieldStates: fields, width: 900, height: 520).map {
                "\($0.key)@\(P.bits($0.x)).\(P.bits($0.y))"
            }.joined(separator: " ")
        case "tap":
            let model = WorldMapModel(centerLon: 15)
            let c = model.coordinates(x: try float(try field(f, 0)), y: try float(try field(f, 1)), width: 900, height: 520)
            return "\(P.doubleBits(c.lon))|\(P.doubleBits(c.lat))"
        case "click":
            return try click(f)
        case "scheme":
            guard let s = MapPalette.schemes.first(where: { $0.key == input }) else { throw X.Malformed(text: input) }
            let values: [UInt32] = [s.oceanLight, s.landLight, s.coastLight, s.oceanDark, s.landDark, s.coastDark]
            return values.map { String(format: "%08x", $0) }.joined(separator: " ")
        case "schemeByKey":
            return MapPalette.scheme(key: input).key
        case "political":
            let group: Int = try X.int(input)
            let light = String(format: "%08x", MapPalette.politicalColor(group: group, dark: false))
            let dark = String(format: "%08x", MapPalette.politicalColor(group: group, dark: true))
            return light + " " + dark
        case "propagation":
            let view = PropagationRows.view(target: try field(f, 0), typedCall: try field(f, 1), sfiText: try field(f, 2),
                                            myGrid: try field(f, 3), lookup: SpotAnalysisFixture.dxcc(), now: P.t0,
                                            translate: P.cs)
            return propagationText(view)
        case "sfiFilter":
            return PropagationRows.filterSfi(input)
        default:
            return try grid(area, input, f, ctx)
        }
    }

    private static func geoRing(_ model: WorldMapModel, _ ring: [Float]) -> String {
        var text = ""
        switch WorldMapModel.classify(ring: ring) {
        case .antarctic:
            text = "antarctic:"
            for s in model.antarcticSegments(ring: ring, width: 900, height: 520) {
                text += "\(P.bits(s.x0)).\(P.bits(s.y0)).\(P.bits(s.x1)).\(P.bits(s.y1)) "
            }
        case .archipelago:
            text = "archipelago:"
            for d in model.archipelagoDots(ring: ring, width: 900, height: 520) {
                text += "\(P.bits(d.x)).\(P.bits(d.y)) "
            }
        case .land:
            text = "land:"
            for v in model.landPath(ring: ring, width: 900, height: 520) {
                text += "\(v.move ? "M" : "L")\(P.bits(v.x)).\(P.bits(v.y)) "
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// `q=<call>,<entity or ->,<deleted 0/1>;… s=<call>;…`
    private static func dxccDots(_ input: String) throws -> String {
        guard let split = input.range(of: " s=") else { throw X.Malformed(text: input) }
        let qsoText: String = String(input[input.index(input.startIndex, offsetBy: 2)..<split.lowerBound])
        let spotText: String = String(input[split.upperBound...])
        var qsos: [Qso] = []
        for item in qsoText.split(separator: ";") {
            let g: [String] = item.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            var q: Qso = P.qso(g[0], "20m", .cw, "")
            if g[1] != "-" { q.dxccEntity = try X.int(g[1]) }
            q.deleted = g[2] == "1"
            qsos.append(q)
        }
        let spots: [DxSpot] = spotText.split(separator: ";").map {
            DxSpot(spotter: "X", freqHz: 14_025_000, dxCall: String($0), comment: "")
        }
        let dots = WorldMapModel.dxccDots(qsos: qsos, spots: spots, lookup: SpotAnalysisFixture.dxcc())
        return dots.map { dot in
            let name: String = dot.state == .worked ? "worked" : (dot.state == .spotted ? "spotted" : "none")
            return "\(P.javaDouble(dot.lat)),\(P.javaDouble(dot.lon)),\(name)"
        }.joined(separator: " ")
    }

    /// `lon|lat|CALL:grid;…` — the spots in this order, the grids as the lookup knows them.
    private static func click(_ f: [String]) throws -> String {
        let lon: Double = try double(try field(f, 0))
        let lat: Double = try double(try field(f, 1))
        var spots: [DxSpot] = []
        var grids: [String: String] = [:]
        for (index, item) in (try field(f, 2)).split(separator: ";").enumerated() {
            let pair = item.split(separator: ":").map(String.init)
            spots.append(DxSpot(spotter: "X", freqHz: 14_025_000 + 5_000 * index, dxCall: pair[0], comment: ""))
            grids[pair[0]] = pair[1]
        }
        let field: String? = WorldMapModel.fieldAt(lon: lon, lat: lat)
        let found = WorldMapModel.tap(lon: lon, lat: lat, spots: spots, hasLookup: true) { grids[$0] }
        return "\(field ?? "null")|\(found?.dxCall ?? "-")"
    }

    private static func selection(_ text: String) -> Set<String> {
        Set(text.dropFirst().dropLast().split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
    }

    private static func grid(_ area: String, _ input: String, _ f: [String], _ ctx: Ctx) throws -> String {
        switch area {
        case "kindTitle":
            return MultGridLayout.title(kind: input, translate: P.cs)
        case "cellColor":
            guard let cell = MultCell(rawValue: input) else { throw X.Malformed(text: input) }
            return MultGridLayout.color(cell).map { String(format: "%08x", $0) } ?? "null"
        case "gridMetrics":
            let m = MultGridLayout.Metrics(fontSp: try X.int(input))
            let parts: [String] = [String(m.fontSp), String(m.bandFontSp), P.bits(m.cell), P.bits(m.prefixW),
                                   P.bits(m.square), P.bits(m.colGap), P.bits(m.prefixGap), P.bits(m.rowH), P.bits(m.headerH)]
            return parts.joined(separator: " ")
        case "gridFlow":
            let height: Float = try float(try field(f, 0))
            let font: Float = try float(try field(f, 1))
            let n: Int = try X.int(try field(f, 2))
            let m = MultGridLayout.Metrics(fontSp: Int(font))
            let per: Int = MultGridLayout.rowsPerColumn(height: height, rowHeight: m.rowH, headerHeight: m.headerH)
            let rows: [MultGridRow] = (0..<n).map {
                MultGridRow(key: "K\($0)", label: "", prefix: "", continent: "", cells: [:])
            }
            let columns = MultGridLayout.columns(rows: rows, height: height, metrics: m)
            var text = ""
            var from = 0
            for (index, column) in columns.enumerated() {
                defer { from += column.count }
                if columns.count > 8 && index >= 3 && index < columns.count - 2 { continue }
                text += "\(from)-\(from + column.count) "
            }
            return "\(per)|\(columns.count)|" + text.trimmingCharacters(in: .whitespaces)
        case "gridFilter":
            if try field(f, 0) == "rows" {
                // `key/prefix/continent/<band>=<cell>,…;…`
                ctx.gridRows = try (try field(f, 1)).split(separator: ";", omittingEmptySubsequences: true).map { item in
                    let g: [String] = item.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                    var cells: [String: MultCell] = [:]
                    for cell in g[3].split(separator: ",") {
                        let pair = cell.split(separator: "=").map(String.init)
                        guard let value = MultCell(rawValue: pair[1]) else { throw X.Malformed(text: String(cell)) }
                        cells[pair[0] + "m"] = value
                    }
                    return MultGridRow(key: g[0], label: g[0], prefix: g[1], continent: g[2], cells: cells)
                }
                return "ok"
            }
            return MultGridLayout.filter(rows: ctx.gridRows, continents: selection(input)).map(\.key).joined(separator: " ")
        case "gridToggle":
            return String(MultGridLayout.toggleAll(Set(MultGridLayout.continents)).isEmpty)
        case "gridLabel":
            return MultGridLayout.label(MultGridRow(key: "KEY", label: "KEY", prefix: "  ", continent: "", cells: [:]))
        case "gridHeaders":
            return MultGridLayout.bandHeaders.joined(separator: ",")
        default:
            throw X.Malformed(text: "area \(area)")
        }
    }

    // MARK: - sim.SESSION

    private static func transmissions(_ replies: [SimulatorSession.Reply]) -> String {
        replies.map { reply in
            let t = reply.transmission
            let fields: [String] = [t.from.call, t.text, String(t.delayMs), String(t.from.wpm), String(t.from.pitchOffsetHz),
                                    P.doubleBits(reply.amplitude)]
            return fields.joined(separator: "/")
        }.joined(separator: " ")
    }

    static func sim(_ area: String, _ input: String, _ ctx: Ctx) throws -> String {
        let f: [String] = parts(input)
        switch area {
        case "simSettings":
            let numbers: [Int32] = try input.dropFirst().dropLast().split(separator: ",").map {
                try X.int32($0.trimmingCharacters(in: .whitespaces))
            }
            let x = PileupSimulator.Settings(activity: numbers[0], minWpm: numbers[1], maxWpm: numbers[2],
                                             pitchSpreadHz: numbers[3])
            return "\(x.activity),\(x.minWpm),\(x.maxWpm),\(x.pitchSpreadHz)"
        case "simSent":
            if try field(f, 0) == "new" {
                // `new|<pool>|<seed>|<callsigns or ->|activity,minWpm,maxWpm,spread`
                let s: [Int32] = try (try field(f, 4)).split(separator: ",").map { try X.int32(String($0)) }
                let calls: [String] = try field(f, 3) == "-" ? [] : (try field(f, 3)).split(separator: ",").map(String.init)
                let database: ScpDatabase = calls.isEmpty ? ScpDatabase.empty() : ScpDatabase.of(calls)
                ctx.sessions[try field(f, 1) + "|" + (try field(f, 2))] = SimulatorSession(
                    settings: PileupSimulator.Settings(activity: s[0], minWpm: s[1], maxWpm: s[2], pitchSpreadHz: s[3]),
                    scp: database, random: JavaPileupRandom(seed: try X.int64(try field(f, 2))))
                return "ok"
            }
            guard let session = ctx.sessions[try field(f, 0) + "|" + (try field(f, 1))] else {
                throw X.Malformed(text: input)
            }
            return transmissions(session.onSent(try field(f, 3)))
        case "simLogged":
            guard let session = ctx.sessions[try field(f, 0) + "|" + (try field(f, 1))] else {
                throw X.Malformed(text: input)
            }
            if try field(f, 2) == "callers" { return String(session.callers.count) }
            guard let chk = session.onLogged(call: try field(f, 3), exchangeRcvd: try field(f, 4), serialRcvd: nil) else {
                throw X.Malformed(text: "no check for \(input)")
            }
            let text: String = SimulatorSession.checkText(chk, translate: P.cs)
            let counters: String = "|qsos=\(session.qsos)|errors=\(session.errors)"
            if try field(f, 2) == "end" { return text + counters }
            return text + counters + "|" + [chk.loggedCall, chk.expectedCall, chk.expectedExchange].joined(separator: "/")
        case "simText":
            if try field(f, 0) == "start" {
                return SimulatorSession.startText(scpSize: try X.int(try field(f, 1)), translate: P.cs)
            }
            return SimulatorSession.noiseText(try float(try field(f, 1)))
        case "simForm":
            let s = SimulatorSession.settings(activity: 3, minWpm: try field(f, 0), maxWpm: try field(f, 1),
                                              spread: try field(f, 2))
            return "\(s.activity),\(s.minWpm),\(s.maxWpm),\(s.pitchSpreadHz)"
        case "simDigits":
            return SimulatorSession.digits(input, limit: 2)
        default:
            throw X.Malformed(text: "area \(area)")
        }
    }
}
