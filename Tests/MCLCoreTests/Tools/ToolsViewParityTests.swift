import Foundation
import Testing
@testable import MCLCore

/// Replays the simulator, map, propagation, multiplier grid and watch rows of `ToolsProbe.java` over the Swift core.
@Suite struct ToolsViewParityTests {

    typealias P = ToolsParity

    // MARK: - simulator

    private static func transmissions(_ replies: [SimulatorSession.Reply]) -> String {
        replies.map { reply in
            let t = reply.transmission
            let fields: [String] = [P.esc(t.from.call), P.esc(t.text), String(t.delayMs), String(t.from.wpm),
                                    String(t.from.pitchOffsetHz), P.doubleBits(reply.amplitude)]
            return fields.joined(separator: "/")
        }.joined(separator: " ")
    }

    private static func check(_ c: PileupSimulator.Check) -> String {
        SimulatorSession.checkText(c, translate: P.cs)
    }

    @Test func simulatorSessionMatchesJvm() {
        var settingsRows: [ToolsParity.Row] = []
        let settings: [[Int32]] = [[3, 22, 32, 300], [0, 5, 3, -4], [9, 40, 20, 5000], [1, 10, 10, 0], [6, 100, 100, 99999]]
        for s in settings {
            let x = PileupSimulator.Settings(activity: s[0], minWpm: s[1], maxWpm: s[2], pitchSpreadHz: s[3])
            settingsRows.append(("[\(s[0]), \(s[1]), \(s[2]), \(s[3])]", "\(x.activity),\(x.minWpm),\(x.maxWpm),\(x.pitchSpreadHz)"))
        }
        P.expect("simSettings", settingsRows)

        let scp: [String] = ["OK1ABC", "DL1XYZ", "W1AW", "JA1QQQ", "G3ABC", "SP9XYZ", "OK2BBB"]
        let sent: [String] = ["CQ TEST OK1XOE", "OK1XOE", "?", "OK1ABC", "OK1ABC", "TU OK1XOE", "CQ TEST", "OK1?", "AGN",
                              "TU", "CQ", "W1?", "DL1XY", "NR?"]
        var sentRows: [ToolsParity.Row] = []
        var loggedRows: [ToolsParity.Row] = []
        for pool in 0..<2 {
            for seed: Int64 in [1, 42, 20_261_004] {
                let random = JavaPileupRandom(seed: seed)
                let database: ScpDatabase = pool == 0 ? ScpDatabase.of(scp) : ScpDatabase.empty()
                let session = SimulatorSession(settings: PileupSimulator.Settings(activity: 3, minWpm: 22, maxWpm: 32,
                                                                                  pitchSpreadHz: 300),
                                               scp: database, random: random)
                let tag: String = (pool == 0 ? "scp" : "empty") + "|\(seed)"
                for (step, text) in sent.enumerated() {
                    sentRows.append(("\(tag)|\(step)|\(P.esc(text))", Self.transmissions(session.onSent(text))))
                    var call: String?
                    var exch = ""
                    switch step {
                    case 2:
                        call = "NOONE"
                        exch = "5NN 1"
                    case 4:
                        call = session.current?.call ?? "NOONE"
                        exch = session.current?.exchange ?? "5NN 1"
                    case 5:
                        call = "OK1ABC"
                        exch = "5NN 99999"
                    case 9:
                        call = "OK1AB"
                        exch = "5NN 1"
                    case 11:
                        let first = session.callers.first
                        call = first?.call ?? "W1AW"
                        exch = "599 " + String(first?.serial ?? 1)
                    default:
                        break
                    }
                    if let call, let chk = session.onLogged(call: call, exchangeRcvd: exch, serialRcvd: nil) {
                        let detail: String = [chk.loggedCall, chk.expectedCall, chk.expectedExchange].joined(separator: "/")
                        loggedRows.append(("\(tag)|\(step)", "\(P.esc(Self.check(chk)))|qsos=\(session.qsos)|errors=\(session.errors)|"
                            + P.esc(detail)))
                    }
                }
                if let last = session.onLogged(call: "ZZ9ZZ", exchangeRcvd: "5NN 1", serialRcvd: nil) {
                    loggedRows.append(("\(tag)|end", "\(P.esc(Self.check(last)))|qsos=\(session.qsos)|errors=\(session.errors)"))
                }
                loggedRows.append(("\(tag)|callers", String(session.callers.count)))
            }
        }
        P.expect("simSent", sentRows)
        P.expect("simLogged", loggedRows)
    }

    @Test func simulatorTextsAndFormMatchJvm() {
        let startScp: String = SimulatorSession.startText(scpSize: 7, translate: P.cs)
        let startEmpty: String = SimulatorSession.startText(scpSize: 0, translate: P.cs)
        P.expect("simText", [("start-scp", startScp), ("start-empty", startEmpty)]
            + [Float(0.0), 0.15, 0.6, 0.2999, 0.57, 0.29, 0.07].map { level in
                ("noise|\(P.javaFloat(level))", SimulatorSession.noiseText(level))
            })

        let forms: [[String]] = [["22", "32", "300"], ["", "", ""], ["x", "7", "9999"],
                                 ["\u{0662}\u{0665}", "\u{0663}\u{0660}", "\u{0660}\u{0663}\u{0660}\u{0660}"],
                                 ["+5", "-3", "99999"], ["2147483648", "2147483647", "0"], ["007", "", "12"]]
        P.expect("simForm", forms.map { f in
            let s = SimulatorSession.settings(activity: 3, minWpm: f[0], maxWpm: f[1], spread: f[2])
            return (P.esc(f.joined(separator: "|")), "\(s.activity),\(s.minWpm),\(s.maxWpm),\(s.pitchSpreadHz)")
        })
        let digits: [String] = ["12a3", "\u{0662}\u{0665}x", "12345", "", "0\u{0663}"]
        P.expect("simDigits", digits.map { (P.esc($0), P.esc(SimulatorSession.digits($0, limit: 2))) })
    }

    // MARK: - map

    @Test func mapBasicsMatchJvm() {
        let points: [(Double, Double)] = [
            (0, 0), (15, 50), (-180, -90), (179.999, 89.999), (180, 90), (-180.0001, 0), (540, 10), (-540, -10),
            (19.999, 9.999), (20, 10), (-0.0, 0.0), (359.5, 0), (.nan, 0), (0, .nan), (0, 100), (0, -100),
            (1e300, 1e300), (-1e-12, -1e-12), (-160, -80), (137.5, 35.5), (-97, 37), (.infinity, 0),
        ]
        P.expect("fieldAt", points.map { (p: (Double, Double)) in
            ("\(P.javaDouble(p.0))|\(P.javaDouble(p.1))", WorldMapModel.fieldAt(lon: p.0, lat: p.1) ?? "null")
        })
        let cells: [MultCell] = [.empty, .worked, .spotted, .spottedDbl]
        P.expect("rank", cells.map { ($0.rawValue, String(WorldMapModel.rank($0))) })

        var px: [ToolsParity.Row] = []
        for center in [0.0, 15, -170, 179.5, 200] {
            let model = WorldMapModel(centerLon: center)
            for lon in [-180.0, -165, 0, 15, 180, 195, 540, -0.0001] {
                px.append(("\(P.javaDouble(center))|900|\(P.javaDouble(lon))", P.bits(model.px(lon: lon, width: 900))))
            }
        }
        P.expect("px", px)
        P.expect("py", [90.0, 50, 0, -75, -90, 12.345].map {
            ("520|\(P.javaDouble($0))", P.bits(WorldMapModel.py(lat: $0, height: 520)))
        })

        let positions: [[String]] = [["50.1", "14.4", "JN79"], ["", "", "JN79"], ["x", "14.4", "JN79"],
                                     ["50", "", "JN99ab"], ["", "", ""], [" 50 ", "14", "JN79"], ["91", "181", "JN79"],
                                     ["NaN", "1", "JN79"], ["1e1", "2e0", ""]]
        P.expect("station", positions.map { p in
            let position = WorldMapModel.stationPosition(latitude: p[0], longitude: p[1], gridSquare: p[2])
            return (P.esc(p.joined(separator: "|")),
                    position.map { "\(P.javaDouble($0.lat)),\(P.javaDouble($0.lon))" } ?? "null")
        })
    }

    @Test func dxccDotsMatchJvm() {
        let lookup = SpotAnalysisFixture.dxcc()
        var qsos: [Qso] = [P.qso("DL1ABC", "20m", .cw, "")]
        var stored: Qso = P.qso("W1AW", "20m", .cw, "")
        stored.dxccEntity = 339
        qsos.append(stored)
        var deleted: Qso = P.qso("OK1XOE", "20m", .cw, "")
        deleted.deleted = true
        qsos.append(deleted)
        qsos.append(P.qso("ZZ9ZZ", "20m", .cw, ""))
        qsos.append(P.qso("VE3ABC", "20m", .cw, ""))
        let spots: [DxSpot] = [DxSpot(spotter: "X", freqHz: 14_025_000, dxCall: "LU1ABC", comment: ""),
                               DxSpot(spotter: "X", freqHz: 14_025_000, dxCall: "DL2XYZ", comment: ""),
                               DxSpot(spotter: "X", freqHz: 14_025_000, dxCall: "ZZ9ZZ", comment: "")]
        let variants: [([Qso], [DxSpot])] = [(qsos, spots), ([], spots), (Array(qsos.prefix(1)), [])]
        var out: [ToolsParity.Row] = []
        for (index, variant) in variants.enumerated() {
            let dots = WorldMapModel.dxccDots(qsos: variant.0, spots: variant.1, lookup: lookup)
            let text: String = dots.map { dot in
                let name: String = dot.state == .worked ? "worked" : (dot.state == .spotted ? "spotted" : "none")
                return "\(P.javaDouble(dot.lat)),\(P.javaDouble(dot.lon)),\(name)"
            }.joined(separator: " ")
            out.append((String(index), text))
        }
        P.expect("dxccDots", out)
        #expect(WorldMapModel.dxccDots(qsos: qsos, spots: spots, lookup: nil).isEmpty)
    }

    @Test func geometryMatchesJvm() throws {
        let geo = WorldMapGeo.fromData(Data(ToolsJava.miniGeojson.utf8))
        let java = P.rows("geoRings")
        #expect(java.first?.result == "\(geo.rings.count)|[" + geo.ringGroups.map { String($0) }.joined(separator: ", ") + "]")
        var rings: [ToolsParity.Row] = []
        for center in [15.0, -170.0, 0.0] {
            let model = WorldMapModel(centerLon: center)
            for (index, ring) in geo.rings.enumerated() {
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
                rings.append(("\(P.javaDouble(center))|\(index)", text.trimmingCharacters(in: .whitespaces)))
            }
        }
        P.expect("geoRing", rings)
    }

    @Test func terminatorAndMarkersMatchJvm() {
        let times: [Int64] = [1_791_028_800_000, 1_782_010_800_000, 1_797_892_200_000, 1_773_964_800_000]
        var night: [ToolsParity.Row] = []
        var sun: [ToolsParity.Row] = []
        for t in times {
            for center in [15.0, -170.0] {
                let model = WorldMapModel(centerLon: center)
                let columns = model.terminatorColumns(width: 90, height: 52, epochMillis: t)
                let text: String = columns.map { "\($0.x):\(P.bits($0.y0)):\(P.bits($0.y1))" }.joined(separator: " ")
                night.append(("\(t)|\(P.javaDouble(center))", text))
                let marker = model.sunMarker(width: 90, height: 52, epochMillis: t)
                sun.append(("\(t)|\(P.javaDouble(center))", marker.map { "\(P.bits($0.x)).\(P.bits($0.y))" } ?? "none"))
            }
        }
        P.expect("night", night)
        P.expect("sun", sun)
    }

    @Test func fieldsLinesAndClicksMatchJvm() {
        let fields: [String: MultCell] = ["JN": .worked, "FN": .spotted, "PM": .spottedDbl, "AA": .worked, "RR": .spotted,
                                          "KK": .empty]
        var rects: [ToolsParity.Row] = []
        var lines: [ToolsParity.Row] = []
        var labels: [ToolsParity.Row] = []
        for center in [15.0, -170.0] {
            let model = WorldMapModel(centerLon: center)
            let rectText: String = model.fieldRects(fieldStates: fields, width: 900, height: 520).map {
                "\($0.key)=\($0.cell.rawValue)@\(P.bits($0.x)).\(P.bits($0.y)).\(P.bits($0.width)).\(P.bits($0.height))"
            }.joined(separator: " ")
            rects.append((P.javaDouble(center), rectText))
            let vertical = model.verticalGridLines(width: 900).map { P.bits($0) }
            let horizontal = model.horizontalGridLines(height: 520).map { P.bits($0) }
            lines.append((P.javaDouble(center), (vertical + horizontal).joined(separator: " ")))
            let labelText: String = model.fieldLabels(fieldStates: fields, width: 900, height: 520).map {
                "\($0.key)@\(P.bits($0.x)).\(P.bits($0.y))"
            }.joined(separator: " ")
            labels.append((P.javaDouble(center), labelText))
        }
        P.expect("fieldRects", rects)
        P.expect("gridLines", lines)
        P.expect("fieldLabels", labels)

        let model = WorldMapModel(centerLon: 15)
        let taps: [(Float, Float)] = [(0, 0), (450, 260), (899, 519), (123.4, 56.7)]
        P.expect("tap", taps.map { t in
            let c = model.coordinates(x: t.0, y: t.1, width: 900, height: 520)
            return ("\(P.javaFloat(t.0))|\(P.javaFloat(t.1))", "\(P.doubleBits(c.lon))|\(P.doubleBits(c.lat))")
        })
        let spots: [DxSpot] = [DxSpot(spotter: "X", freqHz: 14_025_000, dxCall: "DL1ABC", comment: ""),
                               DxSpot(spotter: "X", freqHz: 14_030_000, dxCall: "W1AW", comment: ""),
                               DxSpot(spotter: "X", freqHz: 14_035_000, dxCall: "K2ZZ", comment: ""),
                               DxSpot(spotter: "X", freqHz: 14_040_000, dxCall: "OK1X", comment: "")]
        let grids: [String: String] = ["DL1ABC": "JO31", "W1AW": "fn31", "K2ZZ": "F", "OK1X": "JN"]
        let clicks: [(Double, Double)] = [(10, 50), (-72, 41), (-70, 40), (15, 49), (100, 10), (.nan, 1)]
        P.expect("click", clicks.map { c in
            let field: String? = WorldMapModel.fieldAt(lon: c.0, lat: c.1)
            let found = WorldMapModel.tap(lon: c.0, lat: c.1, spots: spots, hasLookup: true) { grids[$0] }
            return ("\(P.javaDouble(c.0))|\(P.javaDouble(c.1))", "\(field ?? "null")|\(found?.dxCall ?? "-")")
        })
        #expect(WorldMapModel.tap(lon: 10, lat: 50, spots: spots, hasLookup: false) { grids[$0] } == nil)
    }

    @Test func mapPaletteMatchesJvm() {
        P.expect("scheme", MapPalette.schemes.map { s in
            let values: [UInt32] = [s.oceanLight, s.landLight, s.coastLight, s.oceanDark, s.landDark, s.coastDark]
            return (s.key, values.map { String(format: "%08x", $0) }.joined(separator: " "))
        })
        let keys: [String] = ["green", "gray", "sepia", "slate", "nonsense", "", "GREEN"]
        P.expect("schemeByKey", keys.map { (P.esc($0), MapPalette.scheme(key: $0).key) })
        let groups: [Int] = [0, 1, 13, 14, 15, 27, 28, 100, -1, -14, -15, Int(Int32.max), Int(Int32.min)]
        P.expect("political", groups.map { g in
            let light = String(format: "%08x", MapPalette.politicalColor(group: g, dark: false))
            let dark = String(format: "%08x", MapPalette.politicalColor(group: g, dark: true))
            return (String(g), light + " " + dark)
        })
    }

    @Test func schemeKeysMatchTheConfigDefault() {
        #expect(MapPalette.scheme(key: MapConfig.defaultScheme).key == MapConfig.defaultScheme)
        #expect(MapPalette.schemes.map(\.key).contains(MapConfig.defaultScheme))
    }

    // MARK: - propagation

    private static func propagationText(_ view: PropagationRows.View) -> String {
        switch view {
        case .message(let text):
            return "msg:" + text
        case .table(let table):
            var out: String = P.esc(table.title) + "|hour=\(table.nowHour)|"
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

    @Test func propagationMatchesJvm() {
        let lookup = SpotAnalysisFixture.dxcc()
        let cases: [[String]] = [
            ["DL1ABC", "", "120", "JN79"], ["", "W1AW", "150", "JN79"], ["", "", "120", "JN79"], ["JA1XYZ", "", "", "JN79"],
            ["LU1ABC", "", "70", "JN79"], ["VE3ABC", "", "120", "JN79"], ["DL1ABC", "", "120", ""],
            ["  w1aw  ", "", "300", "JN79"], ["ZZ9ZZ", "", "120", "JN79"], ["OK1ABC", "", "999", "FN31"],
            ["JA1XYZ", "", "0", "PM95"], ["DL1ABC", "", "63", "JN79"], ["DL1ABC", "", "64", "JN79"],
            ["\u{00A0}", "K1ABC", "100", "JN79"], ["DL1ABC", "", "1e2", "JN79"], ["DL1ABC", "", " 100", "JN79"],
            ["DL1ABC", "", "NaN", "JN79"], ["DL1ABC", "", "Infinity", "JN79"], ["DL1ABC", "", "9999999999", "JN79"],
        ]
        P.expect("propagation", cases.map { c in
            let view = PropagationRows.view(target: c[0], typedCall: c[1], sfiText: c[2], myGrid: c[3], lookup: lookup,
                                            now: P.t0, translate: P.cs)
            return (P.esc(c.joined(separator: "|")), Self.propagationText(view))
        })
        let filters: [String] = ["120", "1a2b3c4", "\u{0663}\u{0664}\u{0665}", "", "99999", "12 3"]
        P.expect("sfiFilter", filters.map { (P.esc($0), P.esc(PropagationRows.filterSfi($0))) })
    }

    // MARK: - multiplier grid

    @Test func gridTitlesColorsAndMetricsMatchJvm() {
        let kinds: [String] = ["dxcc", "grid", "itu", "cq", "districts", "other", "sections", "zones", "", "DXCC"]
        P.expect("kindTitle", kinds.map { (P.esc($0), P.esc(MultGridLayout.title(kind: $0, translate: P.cs))) })
        P.expect("cellColor", [MultCell.empty, .worked, .spotted, .spottedDbl].map { cell in
            (cell.rawValue, MultGridLayout.color(cell).map { String(format: "%08x", $0) } ?? "null")
        })
        let fonts: [Int] = [0, 1, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 30, 48, 100, -3]
        P.expect("gridMetrics", fonts.map { font in
            let m = MultGridLayout.Metrics(fontSp: font)
            let parts: [String] = [String(m.fontSp), String(m.bandFontSp), P.bits(m.cell), P.bits(m.prefixW),
                                   P.bits(m.square), P.bits(m.colGap), P.bits(m.prefixGap), P.bits(m.rowH), P.bits(m.headerH)]
            return (String(font), parts.joined(separator: " "))
        })
    }

    @Test func gridFlowMatchesJvm() {
        let flows: [(Float, Float)] = [(620, 14), (620, 10), (100, 14), (10, 14), (0, 14), (-50, 14), (1e9, 14), (500.5, 12),
                                       (.nan, 14)]
        var out: [ToolsParity.Row] = []
        for (height, font) in flows {
            let m = MultGridLayout.Metrics(fontSp: Int(font))
            let per: Int = MultGridLayout.rowsPerColumn(height: height, rowHeight: m.rowH, headerHeight: m.headerH)
            for n in [0, 1, 5, 17, 18, 100] {
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
                out.append(("\(P.javaFloat(height))|\(P.javaFloat(font))|\(n)",
                            "\(per)|\(columns.count)|" + text.trimmingCharacters(in: .whitespaces)))
            }
        }
        P.expect("gridFlow", out)
    }

    @Test func gridFilterMatchesJvm() {
        let specs: [(String, String, String, [Band: MultCell])] = [
            ("A", "", "EU", [.m20: .worked]), ("B", "pfx", "AS", [:]), ("C", "  ", "NA", [.m40: .spotted, .m80: .spottedDbl]),
            ("D", "d", "", [.m10: .spotted]), ("E", "e", "  ", [:]), ("F", "f", "OC", [.m160: .empty, .m15: .worked]),
            ("G", "g", "SA", [.m20: .empty]), ("H", "h", "AF", [.m20: .worked]),
        ]
        let rows: [MultGridRow] = specs.map { spec in
            var cells: [String: MultCell] = [:]
            for (band, cell) in spec.3 { cells[band.adif] = cell }
            return MultGridRow(key: spec.0, label: spec.0, prefix: spec.1, continent: spec.2, cells: cells)
        }
        let selections: [(String, Set<String>)] = [
            ("[AF, AS, EU, NA, OC, SA]", Set(MultGridLayout.continents)), ("[EU, NA]", ["EU", "NA"]), ("[]", []),
            ("[OC]", ["OC"]),
        ]
        P.expect("gridFilter", selections.map { selection in
            (selection.0, MultGridLayout.filter(rows: rows, continents: selection.1).map(\.key).joined(separator: " "))
        })
        #expect(MultGridLayout.toggleAll(Set(MultGridLayout.continents)).isEmpty)
        #expect(MultGridLayout.toggleAll(["EU"]) == Set(MultGridLayout.continents))
        #expect(MultGridLayout.toggle("EU", in: ["EU", "NA"]) == ["NA"])
        #expect(MultGridLayout.toggle("EU", in: ["NA"]) == ["EU", "NA"])
        #expect(MultGridLayout.label(rows[2]) == "C")
        #expect(MultGridLayout.label(rows[1]) == "pfx")
        #expect(MultGridLayout.hasContinents(rows))
        #expect(MultGridLayout.bandHeaders.joined(separator: ",") == ToolsParity.rows("gridHeaders").first?.result)
    }

    // MARK: - watches

    @Test func skedWatchMatchesJvm() {
        let now: JavaInstant = P.t0Instant
        func at(_ seconds: Int64) -> String { now.plus(seconds: seconds)!.toString() }
        let due = SkedEntry(call: "K1AAA", freqHz: 14_025_000, mode: "CW", atUtc: at(30), note: "first")
        let late = SkedEntry(call: "K2BBB", freqHz: 7_025_000, mode: "SSB", atUtc: at(-200), note: "")
        let future = SkedEntry(call: "K3CCC", freqHz: 7_025_000, mode: "SSB", atUtc: at(600), note: "later")
        let past = SkedEntry(call: "K4DDD", freqHz: 7_025_000, mode: "SSB", atUtc: at(-900), note: "gone")
        let bad = SkedEntry(call: "K5EEE", freqHz: 7_025_000, mode: "SSB", atUtc: "garbage", note: "bad")
        let blank = SkedEntry(call: "K6FFF", freqHz: 21_025_050, mode: "CW", atUtc: at(10), note: "   ")
        var same = SkedEntry(call: "K7GGG", freqHz: 28_025_000, mode: "CW", atUtc: at(20), note: "same id")
        same.id = due.id
        let skeds: [SkedEntry] = [due, late, future, past, bad, blank, same]
        func normalize(_ text: String) -> String {
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
        var watch = SkedWatch()
        let first: [String] = watch.due(skeds: skeds, now: now)
        var rows: [ToolsParity.Row] = first.map { ("tick1", P.esc(normalize($0))) }
        rows.append(("status", P.esc(normalize(SkedWatch.statusLine(first.last ?? "")))))
        rows.append(("tick2-new", String(watch.due(skeds: skeds, now: now).count)))
        rows.append(("revision", String(first.count)))
        let java = P.rows("skedWatch")
        #expect(java.count == rows.count)
        for (s, j) in zip(rows, java) where s.input != j.input || s.result != j.result {
            Issue.record("skedWatch\nSwift: \(s.input) => \(s.result)\nJava:  \(j.input) => \(j.result)")
        }
        #expect(watch.reminded.count == 3)
    }

    @Test func tourWatchMatchesJvm() throws {
        let a = try Tour(startMinute: 0, durationMinutes: 100_000_000)
        let b = try Tour(startMinute: 0, durationMinutes: 20_000_000)
        let c = try Tour(startMinute: 90, durationMinutes: 14_000_000)
        func run(_ tours: [Tour?], active: Bool) -> [String] {
            var watch = TourWatch()
            return tours.compactMap { watch.tick(tour: $0, now: P.t0, active: active, translate: P.cs) }
        }
        let changed: [String] = run([a, b, c, c], active: true)
        #expect(run([b, b, b, b], active: true).isEmpty)
        #expect(run([a, b, b, b], active: false).isEmpty)
        #expect(run([a, nil, b, b], active: true).isEmpty)
        var rows: [ToolsParity.Row] = changed.map { ("changed", P.esc($0)) }
        rows.append(("changed-status", P.esc(TourWatch.statusLine(changed.last ?? ""))))
        rows.append(("changed-count", String(changed.count)))
        rows += [("steady-status", ""), ("steady-count", "0"), ("inactive-status", ""), ("inactive-count", "0"),
                 ("dropped-status", ""), ("dropped-count", "0")]
        rows.append(("sessions", "[\(a.session(at: P.t0)), \(b.session(at: P.t0)), \(c.session(at: P.t0))]"))
        P.expect("tourWatch", rows)
    }
}
