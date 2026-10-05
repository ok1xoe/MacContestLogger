import Foundation
import Testing
@testable import MCLCore

/// Replays the sked, QTC, band notes and move rows of `ToolsProbe.java` over the Swift core.
@Suite struct ToolsEditParityTests {

    typealias P = ToolsParity

    // MARK: - skeds

    private struct SkedCase {
        let call: String
        let freq: Int
        let mode: String
        let time: String
        let note: String
    }

    private static let skedCases: [SkedCase] = [
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "2026-11-28 1430", note: "note"),
        SkedCase(call: "ok1abc ", freq: 7_025_000, mode: "SSB", time: "2026-11-28 1430", note: "  trimmed note  "),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "0930", note: ""),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "9:30", note: ""),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "930", note: ""),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "1:05", note: ""),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: " 0930 ", note: ""),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "2400", note: ""),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "1260", note: ""),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "abc", note: ""),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "", note: ""),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "\u{00A0}1430", note: ""),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "2026-02-30 1200", note: ""),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "2024-02-29 1200", note: "leap"),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "2026-11-28   1430", note: "spaces"),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "2026-11-28 14:30", note: "colon"),
        SkedCase(call: "OK1ABC", freq: 14_025_000, mode: "CW", time: "2026-13-01 1200", note: ""),
        SkedCase(call: "  ", freq: 14_025_000, mode: "CW", time: "0930", note: ""),
        SkedCase(call: "  ", freq: 14_025_000, mode: "CW", time: "bad", note: ""),
        SkedCase(call: "OK1ABC", freq: 0, mode: "CW", time: "0930", note: ""),
        SkedCase(call: "OK1ABC", freq: -5, mode: "CW", time: "bad", note: ""),
        SkedCase(call: "OK1ABC", freq: 14_025_500, mode: "RTTY", time: "2026-11-28 0000", note: "n"),
        SkedCase(call: "OK1ABC", freq: 14_025_050, mode: "CW", time: "2026-11-28 1430", note: ""),
        SkedCase(call: "OK1ABC", freq: 3_500_000, mode: "", time: "2026-11-28 1430", note: " "),
        SkedCase(call: "\u{00D6}K1\u{00C4}BC stra\u{00DF}e", freq: 14_025_000, mode: "CW", time: "2026-11-28 1430",
                 note: "x\u{00E9}"),
    ]

    private static func relative(_ time: String) -> Bool {
        let trimmed: String = JavaText.trim(time)
        let units: [UInt16] = Array(trimmed.utf16)
        let digits = units.filter { $0 != 0x3A }
        guard (3...4).contains(digits.count), digits.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return false }
        let colons: Int = units.count - digits.count
        return colons == 0 || (colons == 1 && units[units.count - 3] == 0x3A) || (colons == 1 && units.count >= 3
            && units[units.count - 3] == 0x3A)
    }

    @Test func skedAddMatchesJvm() {
        var out: [ToolsParity.Row] = []
        for c in Self.skedCases {
            let input: String = [P.esc(c.call), String(c.freq), P.esc(c.mode), P.esc(c.time), P.esc(c.note)]
                .joined(separator: "|")
            switch SkedEditing.add(call: c.call, freqHz: c.freq, mode: c.mode, timeText: c.time, note: c.note,
                                   now: P.t0Instant) {
            case .success(let entry):
                let atText: String = Self.relative(c.time)
                    ? "tod=" + String(entry.atUtc.dropFirst(11).prefix(5)) : entry.atUtc
                let fields: [String] = [P.esc(entry.call), String(entry.freqHz), P.esc(entry.mode), atText,
                                        P.esc(entry.note)]
                out.append((input, "true|" + P.esc(SkedEditing.addedText(entry)) + "|1|" + fields.joined(separator: ",")))
            case .failure(let error):
                out.append((input, "false|" + P.esc(error.text(P.cs)) + "|0|-"))
            }
        }
        out.append(("no-contest", "false|" + P.esc(SkedEditing.noActiveContestText(P.cs))))
        out.append(("not-in-database", "false|" + P.esc(SkedEditing.contestNotInDatabaseText(P.cs))))
        P.expect("skedAdd", out)
    }

    // MARK: - QTC

    private static func lines(_ texts: String...) -> [QtcPlanner.Line] {
        texts.map { QtcPlanner.parseLine($0)! }
    }

    private static func qtcRows(_ qtcs: [QtcRecord]) -> String {
        var out = ""
        for q in qtcs {
            let fields: [String] = [String(q.sent), P.esc(q.partnerCall), String(q.groupNr), String(q.groupSize),
                                    q.qsoTime, P.esc(q.qsoCall), String(q.qsoSerial), String(q.freqHz), P.esc(q.mode)]
            out += fields.joined(separator: ",") + ";"
        }
        return out
    }

    private struct QtcStep {
        let label: String
        let sent: Bool
        let partner: String
        let group: Int
        let lines: [QtcPlanner.Line]
        let rigMode: String?
    }

    @Test func qtcSessionMatchesJvm() throws {
        let definition = try SessionFixture.definition("@wae-cw.yaml")
        let config: ContestDefinition.Qtc = try #require(definition.scoring?.qtc)
        let steps: [QtcStep] = [
            QtcStep(label: "recv", sent: false, partner: " dl1abc ", group: 1,
                    lines: Self.lines("1202 g3abc 3", "1203 SP9XYZ 4"), rigMode: nil),
            QtcStep(label: "blank-partner", sent: false, partner: "  ", group: 1, lines: Self.lines("1202 G3ABC 3"),
                    rigMode: nil),
            QtcStep(label: "no-lines", sent: false, partner: "DL1ABC", group: 1, lines: [], rigMode: nil),
            QtcStep(label: "send-ssb", sent: true, partner: "DL1ABC", group: 1,
                    lines: Self.lines("1300 OK1AA 11", "1301 OK1BB 12", "1302 OK1CC 13"), rigMode: "SSB"),
            QtcStep(label: "send-more", sent: true, partner: "DL1ABC", group: 2,
                    lines: Self.lines("1310 OK1DD 14", "1311 OK1EE 15", "1312 OK1FF 16", "1313 OK1GG 17",
                                      "1314 OK1HH 18"), rigMode: nil),
            QtcStep(label: "limit-hit", sent: true, partner: "dl1abc", group: 3,
                    lines: Self.lines("1320 OK1II 19", "1321 OK1JJ 20", "1322 OK1KK 21"), rigMode: nil),
            QtcStep(label: "exact-limit", sent: true, partner: "DL1ABC", group: 3, lines: Self.lines("1320 OK1II 19"),
                    rigMode: nil),
            QtcStep(label: "over", sent: true, partner: "DL1ABC", group: 4, lines: Self.lines("1330 OK1LL 22"),
                    rigMode: nil),
            QtcStep(label: "other-partner", sent: true, partner: "OK2XYZ", group: 5, lines: Self.lines("1340 OK1MM 23"),
                    rigMode: nil),
            QtcStep(label: "recv-after", sent: false, partner: "OK2XYZ", group: 2, lines: Self.lines("1400 DL9ZZ 1"),
                    rigMode: nil),
        ]
        var qtcs: [QtcRecord] = []
        var saves: [ToolsParity.Row] = []
        var remaining: [ToolsParity.Row] = []
        var nextId: Int64 = 1
        for step in steps {
            var status = ""
            var ok = false
            if let failure = QtcSession.validate(partner: step.partner, lines: step.lines, qtcs: qtcs, config: config,
                                                 translate: P.cs) {
                status = failure
            } else {
                var made: [QtcRecord] = QtcSession.records(sent: step.sent, partner: step.partner, groupNr: step.group,
                    lines: step.lines, contestId: "wae-cw", now: P.t0, freqHz: 14_025_000, rigMode: step.rigMode)
                for index in made.indices {
                    made[index].id = nextId
                    nextId += 1
                }
                qtcs += made
                status = QtcSession.savedText(sent: step.sent, groupNr: step.group, count: step.lines.count,
                                              partner: step.partner, total: qtcs.count, translate: P.cs)
                ok = true
            }
            let next: Int = QtcSession.nextGroup(qtcs: qtcs)
            saves.append((step.label, "\(ok)|\(P.esc(status))|\(qtcs.count)|next=\(next)|" + Self.qtcRows(qtcs)))
            let left: Int = QtcPlanner.remainingFor(JavaText.trim(step.partner), qtcs, config.maxPerStationOrDefault)
            remaining.append((step.label, "\(left)|\(config.maxPerStationOrDefault)|\(config.groupSizeOrDefault)"))
        }
        // `qtcSave` rows are interleaved with `qtcRemaining`, then `qtcDelete`, `no-qtc` — compare per area.
        let javaSaves: [ToolsParity.Row] = ToolsParity.rows("qtcSave")
        let javaSteps: [ToolsParity.Row] = Array(javaSaves.prefix(steps.count))
        #expect(javaSteps.count == saves.count)
        for (s, j) in zip(saves, javaSteps) where s.input != j.input || s.result != j.result {
            Issue.record("qtcSave\nSwift: \(s.input) => \(s.result)\nJava:  \(j.input) => \(j.result)")
        }
        ToolsParity.expect("qtcRemaining", remaining)

        qtcs.removeFirst()
        let java = ToolsParity.rows("qtcDelete")
        #expect(java.count == 1)
        #expect(Self.qtcRows(qtcs) == java.first?.result)

        // A contest without QTC.
        let none: String? = QtcSession.validate(partner: "DL1ABC", lines: Self.lines("1202 G3ABC 3"), qtcs: [],
                                                config: nil, translate: P.cs)
        #expect(javaSaves.last.map { $0.result } == "false|" + P.esc(none))

        let rowTexts: [ToolsParity.Row] = qtcsBeforeDelete(steps: steps, config: config).map { ("true", QtcSession.rowText($0)) }
        ToolsParity.expect("qtcRow", rowTexts.map { ($0.input, P.esc($0.result).replacingOccurrences(of: "\\u2192", with: "→")
            .replacingOccurrences(of: "\\u2190", with: "←")) })
    }

    /// The records after the last save step (before the delete), as the probe lists them for `qtcRow`.
    private func qtcsBeforeDelete(steps: [QtcStep], config: ContestDefinition.Qtc) -> [QtcRecord] {
        var qtcs: [QtcRecord] = []
        for step in steps where QtcSession.validate(partner: step.partner, lines: step.lines, qtcs: qtcs, config: config,
                                                    translate: P.cs) == nil {
            qtcs += QtcSession.records(sent: step.sent, partner: step.partner, groupNr: step.group, lines: step.lines,
                                       contestId: "wae-cw", now: P.t0, freqHz: 14_025_000, rigMode: step.rigMode)
        }
        return qtcs
    }

    @Test func qtcParseMatchesJvm() {
        let texts: [String] = [
            "1234 DL1ABC 56", "1234 dl1abc 56\n123 G3ABC 7\n\n  \nbad line\n12345 TOO 1",
            "1234 DL1ABC 56\r\n1235 DL2ABC 57\r\n", "  \n\n", "", "999 AB 1\n1200 DL1ABC 123456\n1200 DL1ABC 12345",
            "1200\tDL1ABC\t5\r1201 OK1ABC 6\u{2028}", "1200 DL1ABC 5\n\u{00A0}\n1200 G3/DL1ABC 5",
            "\u{0661}\u{0662}\u{0663}\u{0664} DL1ABC 5",
        ]
        var out: [ToolsParity.Row] = []
        for text in texts {
            let parsed: QtcSession.Parsed = QtcSession.parseLines(text)
            let good: String = parsed.lines.map { "\($0.time)/\($0.call)/\($0.serial) " }.joined()
            out.append((P.esc(text), "n=\(parsed.entries.count) good=\(good)bad=\(P.esc(parsed.bad.joined(separator: " | "))) "
                + "canSave=\(parsed.canSave)"))
        }
        ToolsParity.expect("qtcParse", out)

        let groups: [String] = ["3/10", " 3 / 10 ", "12/1", "1000/1", "3", "", "3/100", "0/5", "003/05"]
        ToolsParity.expect("qtcGroup", groups.map { (P.esc($0), String(QtcSession.receivedGroupNr($0))) })
    }

    @Test func qtcTextsAreCzechOriginals() {
        #expect(QtcSession.seriesTitle(groupNr: 3, count: 2, translate: P.cs) == "Série 3/2:")
        #expect(QtcSession.cwSendText(groupNr: 2, lines: Self.lines("1202 G3ABC 3", "1203 SP9XYZ 4"))
            == "QTC 2/2 1202 G3ABC 3 1203 SP9XYZ 4")
        let bad = QtcSession.parseLines("bad\n1202 G3ABC 3")
        #expect(bad.badText(P.cs) == "Nečitelné řádky: bad")
        #expect(QtcSession.parseLines("1202 G3ABC 3").badText(P.cs) == nil)
    }

    // MARK: - band notes

    @Test func bandNotesMatchJvm() {
        let forms: [(String, String)] = [
            ("14025.5", "cw dx"), ("14025,5", " text "), ("20m", "band note"), (" 20M ", "x"), ("7050", ""),
            ("7050", "   "), ("abc", "x"), ("", "x"), ("99999", "x"), ("1e3", "x"), ("1810", "top band"),
            ("0x1p3", "x"), ("5d", "x"), ("NaN", "x"), ("Infinity", "x"), ("-7050", "x"), ("0", "x"), ("3.5.0", "x"),
            ("\u{00A0}7050", "x"), ("7050\u{00A0}", "x"), ("160M", "e\u{0301}"), ("80m", "x"), ("40M", "\u{00DC}ber"),
            (" 14,250.5 ", "x"), ("+7050", "x"), ("7_050", "x"), ("14 025", "x"), ("\u{0667}\u{0660}\u{0665}\u{0660}", "x"),
            ("14025.0 ", "tab\there"),
        ]
        var parsed: [ToolsParity.Row] = []
        var accepted: [BandNote] = []
        for (freq, text) in forms {
            let input: String = P.esc(freq) + "|" + P.esc(text)
            if let note = BandNotesEditing.parse(freq: freq, text: text) {
                parsed.append((input, "ok|\(P.esc(note.band))|\(P.doubleBits(note.freqKHz))|\(P.esc(note.text))"))
                accepted.append(note)
            } else {
                parsed.append((input, "bad"))
            }
        }
        ToolsParity.expect("noteParse", parsed)
        let sorted: [ToolsParity.Row] = BandNotesEditing.sorted(accepted).map {
            ("\(P.esc($0.band))|\(P.doubleBits($0.freqKHz))", P.esc(BandNotesEditing.rowText($0)))
        }
        ToolsParity.expect("noteSorted", sorted)
        let freqs: [Int64] = [0, 14_025_000, 7_074_500, 14_025_050, 1_999_999]
        ToolsParity.expect("noteFreqField", freqs.map { (String($0), BandNotesEditing.frequencyFieldText(tunedFreqHz: $0)) })
    }

    // MARK: - move

    @Test func moveRequestMatchesJvm() {
        struct Case {
            let call: String
            let mode: Mode?
            let band: String
            let cq: Int64
            let last: Int64
        }
        let cases: [Case] = [
            Case(call: "DL1ABC", mode: .cw, band: "40m", cq: 7_025_000, last: 0),
            Case(call: "DL1ABC", mode: .cw, band: "40m", cq: 0, last: 7_030_000),
            Case(call: "DL1ABC", mode: .cw, band: "40m", cq: 0, last: 0),
            Case(call: "DL1ABC", mode: .cw, band: "20M", cq: 0, last: 14_025_500),
            Case(call: "DL1ABC", mode: .cw, band: "20m", cq: 14_025_499, last: 0),
            Case(call: "DL1ABC", mode: .cw, band: "10m", cq: 28_025_050, last: 0),
            Case(call: "DL1ABC", mode: .cw, band: "160m", cq: 1_825_000, last: 1_830_000),
            Case(call: "DL1ABC", mode: .ssb, band: "40m", cq: 7_125_000, last: 0),
            Case(call: "DL1ABC", mode: .ssb, band: "40m", cq: 0, last: 7_140_050),
            Case(call: "DL1ABC", mode: .ssb, band: "40M", cq: 0, last: 0),
            Case(call: "DL1ABC", mode: .rtty, band: "15m", cq: 0, last: 21_080_000),
            Case(call: "DL1ABC", mode: .ft8, band: "15m", cq: 0, last: 0),
            Case(call: "DL1ABC", mode: nil, band: "15m", cq: 0, last: 21_025_000),
            Case(call: "DL1ABC", mode: .cw, band: "99m", cq: 7_025_000, last: 0),
            Case(call: "DL1ABC", mode: .cw, band: "", cq: 7_025_000, last: 0),
            Case(call: "DL1ABC", mode: .cw, band: "7", cq: 7_025_000, last: 0),
            Case(call: "", mode: .cw, band: "40m", cq: 7_025_000, last: 0),
            Case(call: "dl1abc/p", mode: .cw, band: "30m", cq: 0, last: 10_115_000),
            Case(call: "DL1ABC", mode: .cw, band: "40m", cq: 7_025_000, last: 7_030_000),
        ]
        var out: [ToolsParity.Row] = []
        for c in cases {
            let modeText: String = c.mode.map { $0.rawValue } ?? "null"
            let input: String = "\(P.esc(c.call))|\(modeText)|\(P.esc(c.band))|\(c.cq)|\(c.last)"
            let q: Qso = P.qso(c.call, "20m", c.mode, "599 14")
            let band: Band? = Band.from(adif: c.band)
            let hz: Int64? = band.flatMap { MoveRequest.frequencyHz(band: $0, cq: c.cq == 0 ? nil : c.cq,
                                                                    last: c.last == 0 ? nil : c.last) }
            let request = MoveRequest.request(qso: q, bandAdif: c.band, hz: hz, translate: P.cs)
            let moveHz: String = band == nil ? "-" : (hz.map { String($0) } ?? "null")
            let keyed: String = request?.cwText.map { $0 + " @60" } ?? ""
            out.append((input, "hz=\(moveHz)|keyed=\(P.esc(keyed))|status=\(P.esc(request?.status ?? ""))"))
        }
        P.expect("move", out)
    }

    @Test func moveCandidatesMatchJvm() throws {
        let env = try SpotAnalysisFixture.environment()
        let list: [Qso] = [
            P.qso("DL1ABC", "20m", .cw, "599 14"), P.qso("W1AW", "40m", .cw, "599 5"),
            P.qso("JA1XYZ", "15m", .cw, "599 25"), P.qso("LU1ABC", "20m", .cw, "599 13"),
            P.qso("DL1ABC", nil, .cw, "599 14"), P.qso("DL1ABC", "20m", .cw, "599 2147483648"),
            P.qso("DL1ABC", "20m", .cw, ""), P.qso("DL1ABC", "6m", .cw, "599 14"),
        ]
        func text(_ q: Qso) -> String {
            env.runtime.moveCandidates(q, at: SpotAnalysisFixture.at).map {
                let mults: String = $0.newMults.map { $0 ?? "null" }.joined(separator: ", ")
                return "\($0.band):[\(mults)]:\($0.points)"
            }.joined(separator: " ")
        }
        var out: [ToolsParity.Row] = list.indices.map { ("none|\($0)", text(list[$0])) }
        try env.activate("cq-ww-cw")
        try env.log("DL1ABC", "20m", "CW", ("rst", "599"), ("zone", "14"))
        try env.log("W1AW", "40m", "CW", ("rst", "599"), ("zone", "5"))
        try env.log("JA1XYZ", "15m", "CW", ("rst", "599"), ("zone", "25"))
        out += list.indices.map { ("cqww|\($0)", text(list[$0])) }
        env.runtime.deactivate()
        out.append(("deactivated", text(list[0])))
        ToolsParity.expect("moveCand", out)
    }
}
