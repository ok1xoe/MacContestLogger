import Foundation
import Testing
@testable import MCLCore

/// The `decode` and `decodecap` rows of `IntegrationsProbe.java` (`AppState.onWsjtxDecode` of the Kotlin v1.1.1 over
/// synthetic decodes) replayed through `WsjtxDecodes`, and the texts and filters of `WsjtxDecodesWindow` from its source.
@Suite struct WsjtxDecodesTests {

    typealias F = IntegrationsFixture

    static func decode(timeMs: Int32, snr: Int32, delta: Int32, message: String) -> WsjtxMessages.Decode {
        WsjtxMessages.Decode(id: "WSJT-X", isNew: true, timeMs: timeMs, snr: snr, deltaTime: 0.2, deltaFrequency: delta,
                             mode: "~", message: message, lowConfidence: false, offAir: false)
    }

    static func status(_ dial: Int64, _ mode: String?, txEnabled: Bool = false, transmitting: Bool = false)
        -> WsjtxMessages.Status {
        WsjtxMessages.Status(id: "WSJT-X", dialFrequencyHz: dial, mode: mode, dxCall: nil, report: nil, txMode: nil,
                             txEnabled: txEnabled, transmitting: transmitting)
    }

    /// The probe's statuses.
    static let statuses: [WsjtxMessages.Status?] = [
        nil, status(0, "FT8"), status(14_074_000, "FT8", txEnabled: true, transmitting: true), status(14_074_000, nil),
        status(21_074_000, "FT4"), status(14_025_000, "CW"), status(21_025_000, "CW"),
    ]

    static let messages: [String] = [
        "CQ DL1AE JO31", "CQ DX JA1QQQ PM95", "OK1XOE DL1AE -12", "DL1AE OK1XOE R-05", "CQ W1AW FN31", "CQ K2ABC FN42",
        "CQ TEST VE3XYZ FN03", "<DL9ABC> OK1XOE RR73", "73", "", "CQ", "CQ NA 3Z1ABC",
    ]

    /// The probe's `rowText`: freq, dupe, mults, caller, target, cq, grid.
    static func rowText(_ row: WsjtxDecodes.Row) -> String {
        [String(row.freqHz), String(row.dupe), String(row.newMultCount), F.escape(row.parsed.caller),
         F.escape(row.parsed.target), String(row.parsed.cq), F.escape(row.parsed.grid)].joined(separator: " ")
    }

    /// Context of one probe contest: the runtime, its analyzer and the worked-call set of the dupe check.
    static func context(_ contest: String?) throws -> (SpotAnalyzer, Set<String>) {
        let runtime = try F.runtime(contest: contest)
        var worked: Set<String> = []
        if let contest {
            let digital: Bool = contest == "ww-digi"
            let exchange: JavaLinkedMap<String> = digital
                ? JavaLinkedMap([("grid", "JO31")])
                : JavaLinkedMap([("rst", "599"), ("zone", "14")])
            try runtime.log(call: "DL1AE", band: "20m", mode: digital ? "FT8" : "CW", exchange: exchange)
            worked.insert("DL1AE|20m")
        }
        return (try F.analyzer(runtime), worked)
    }

    @Test func decodeRowsMatchJvm() throws {
        let from = try F.loopback(2237)
        let rows = F.rows("decode")
        #expect(rows.count == 252)
        for contest in [nil, "ww-digi", "cq-ww-cw"] as [String?] {
            let tag: String = contest ?? "none"
            let (analyzer, worked) = try Self.context(contest)
            var list = WsjtxDecodes()
            var index = 0
            var expected = rows.filter { $0[1] == tag }.makeIterator()
            for (statusIndex, status) in Self.statuses.enumerated() {
                for message in Self.messages {
                    let before = list.rows.count
                    list.add(Self.decode(timeMs: Int32(43_200_000 + index * 15_000), snr: Int32(-12 + index % 7),
                                         delta: Int32(1000 + index), message: message),
                             from: from, status: status, analyzer: analyzer,
                             isDupe: { call, band in
                                 band.map { worked.contains(JavaText.toUpperCase(JavaText.trim(call)) + "|" + $0.adif) } ?? false
                             })
                    let swift: [String] = [String(statusIndex), F.escape(message), String(1000 + index),
                                           String(list.rows.count - before), Self.rowText(list.rows[0])]
                    guard let java = expected.next() else {
                        Issue.record("no JVM row for \(tag) \(statusIndex) \(message)")
                        return
                    }
                    if swift != Array(java[2...]) {
                        Issue.record("\(tag)\nSwift: \(swift)\nJava:  \(Array(java[2...]))")
                    }
                    index += 1
                }
            }
            #expect(expected.next() == nil)
        }
    }

    @Test func listIsNewestFirstAndCappedAt300() throws {
        let from = try F.loopback(2237)
        var list = WsjtxDecodes()
        let javaRows = F.rows("decodecap")
        #expect(javaRows.count == 9)
        let tags = ["none", "ww-digi", "cq-ww-cw"]
        for tag in tags {
            list = WsjtxDecodes()
            let (analyzer, _) = try Self.context(tag == "none" ? nil : tag)
            for i in 0..<305 {
                list.add(Self.decode(timeMs: 0, snr: Int32(i), delta: Int32(i), message: "CQ DL\(i)A JO31"), from: from,
                         status: Self.status(14_074_000, "FT8"), analyzer: analyzer, isDupe: { _, _ in false })
                if [299, 300, 304].contains(i) {
                    let swift: [String] = [String(i), String(list.rows.count), String(list.rows[0].decode.deltaFrequency),
                                           String(list.rows[list.rows.count - 1].decode.deltaFrequency)]
                    let java = javaRows.first { $0[1] == tag && $0[2] == String(i) }.map { Array($0[2...]) }
                    #expect(swift == java, "\(tag) \(i)")
                }
            }
        }
        #expect(WsjtxDecodes.maxRows == 300)
    }

    @Test func clearEmptiesTheList() throws {
        var list = WsjtxDecodes()
        list.add(Self.decode(timeMs: 0, snr: 0, delta: 0, message: "CQ DL1AE JO31"), from: try F.loopback(2237),
                 status: nil, analyzer: nil, isDupe: { _, _ in false })
        #expect(list.rows.count == 1)
        list.clear()
        #expect(list.rows.isEmpty)
    }

    /// An unknown dial gives frequency 0 and skips the classification even for a worked call; the dupe check then
    /// is not asked at all.
    @Test func unknownDialSkipsTheClassification() throws {
        var list = WsjtxDecodes()
        var asked = 0
        list.add(Self.decode(timeMs: 0, snr: 0, delta: 5, message: "CQ DL1AE JO31"), from: try F.loopback(2237),
                 status: Self.status(0, "FT8"), analyzer: nil, isDupe: { _, _ in asked += 1; return true })
        #expect(list.rows[0].freqHz == 0)
        #expect(!list.rows[0].dupe)
        #expect(asked == 0)
        list.add(Self.decode(timeMs: 0, snr: 0, delta: 5, message: "CQ DL1AE JO31"), from: try F.loopback(2237),
                 status: Self.status(14_074_000, "FT8"), analyzer: nil, isDupe: { _, _ in asked += 1; return true })
        #expect(list.rows[0].freqHz == 14_074_005)
        #expect(list.rows[0].dupe)
        #expect(asked == 1)
    }

    // MARK: - window texts and filters (WsjtxDecodesWindow.kt, from the source)

    static func row(_ message: String, dupe: Bool, mults: Int, timeMs: Int32 = 0, snr: Int32 = 0, delta: Int32 = 0)
        throws -> WsjtxDecodes.Row {
        WsjtxDecodes.Row(decode: decode(timeMs: timeMs, snr: snr, delta: delta, message: message),
                         from: try F.loopback(2237), parsed: Ft8Message.parse(message), freqHz: 14_074_000, dupe: dupe,
                         newMultCount: mults)
    }

    @Test func rowTextFormatsTimeSnrOffsetAndLabel() throws {
        let t = WsjtxDecodes.rowText(try Self.row("CQ DL1AE JO31", dupe: false, mults: 0, timeMs: 43_200_000 + 15_000 * 3,
                                                  snr: -12, delta: 1500))
        #expect(t == WsjtxDecodes.RowText(time: "120045", snr: "-12", deltaFrequency: "1500", message: "CQ DL1AE JO31",
                                          label: ""))
        #expect(WsjtxDecodes.rowText(try Self.row("X", dupe: false, mults: 0, snr: 5)).snr == " +5")
        #expect(WsjtxDecodes.rowText(try Self.row("X", dupe: false, mults: 0, snr: 0)).snr == " +0")
        #expect(WsjtxDecodes.rowText(try Self.row("X", dupe: false, mults: 0, snr: 123)).snr == "+123")
        #expect(WsjtxDecodes.rowText(try Self.row("X", dupe: false, mults: 0, timeMs: 3_661_000)).time == "010101")
        #expect(WsjtxDecodes.rowText(try Self.row("X", dupe: false, mults: 0, timeMs: 86_399_999)).time == "235959")
        #expect(WsjtxDecodes.rowText(try Self.row("X", dupe: false, mults: 0, delta: -20)).deltaFrequency == "-20")
        #expect(WsjtxDecodes.rowText(try Self.row("X", dupe: true, mults: 3)).label == "dupe")
        #expect(WsjtxDecodes.rowText(try Self.row("X", dupe: false, mults: 3)).label == "3× mult")
        #expect(WsjtxDecodes.rowText(try Self.row("X", dupe: false, mults: 2)).label == "2× mult")
        #expect(WsjtxDecodes.rowText(try Self.row("X", dupe: false, mults: 1)).label == "mult")
        #expect(WsjtxDecodes.rowText(try Self.row("X", dupe: false, mults: 0)).label == "")
    }

    @Test func nilMessageShowsEmpty() throws {
        var d = Self.decode(timeMs: 0, snr: 0, delta: 0, message: "")
        d.message = nil
        let row = WsjtxDecodes.Row(decode: d, from: try F.loopback(2237), parsed: Ft8Message.parse(nil), freqHz: 0,
                                   dupe: false, newMultCount: 0)
        #expect(WsjtxDecodes.rowText(row).message == "")
    }

    @Test func filtersCombine() throws {
        let rows: [(String, Bool, Int)] = [
            ("CQ DL1AE JO31", false, 0), ("CQ DL2AE JO31", true, 0), ("OK1XOE DL3AE -12", false, 1),
            ("CQ DL4AE JO31", false, 2), ("OK1XOE DL5AE -12", true, 1),
        ]
        let made: [WsjtxDecodes.Row] = try rows.map { try Self.row($0.0, dupe: $0.1, mults: $0.2) }
        let list = WsjtxDecodes(rows: made)
        func callers(_ rows: [WsjtxDecodes.Row]) -> [String] { rows.map { $0.parsed.caller } }
        #expect(callers(list.filtered(onlyCq: false, hideDupe: false, onlyMult: false))
            == ["DL1AE", "DL2AE", "DL3AE", "DL4AE", "DL5AE"])
        #expect(callers(list.filtered(onlyCq: true, hideDupe: false, onlyMult: false)) == ["DL1AE", "DL2AE", "DL4AE"])
        #expect(callers(list.filtered(onlyCq: false, hideDupe: true, onlyMult: false)) == ["DL1AE", "DL3AE", "DL4AE"])
        #expect(callers(list.filtered(onlyCq: false, hideDupe: false, onlyMult: true))
            == ["DL3AE", "DL4AE", "DL5AE"])
        #expect(callers(list.filtered(onlyCq: true, hideDupe: true, onlyMult: true)) == ["DL4AE"])
    }

    @Test func statusTextFormatsDialAndTransmit() {
        #expect(WsjtxDecodes.statusText(status: nil).czech == "Čekám na WSJT-X (Nastavení → WSJT-X → příjem)…")
        #expect(WsjtxDecodes.statusText(status: Self.status(14_074_000, "FT8")).czech == "FT8  14074.000 kHz")
        #expect(WsjtxDecodes.statusText(status: Self.status(14_074_000, "FT8", transmitting: true)).czech
            == "FT8  14074.000 kHz  · vysílá")
        #expect(WsjtxDecodes.statusText(status: Self.status(7_074_500, nil)).czech == "  7074.500 kHz")
        #expect(WsjtxDecodes.statusText(status: Self.status(0, "FT4")).czech == "FT4  0.000 kHz")
        // txEnabled alone does not add the marker.
        #expect(WsjtxDecodes.statusText(status: Self.status(14_074_000, "FT8", txEnabled: true)).czech == "FT8  14074.000 kHz")
    }
}
