import Foundation
@testable import MCLCore

/// Export inputs — **the same** as in the maintainer-only probe,
/// from which the Java result `ExportsMeasured.swift` comes. A change of input here = a change in the probe and a new
/// generation of the reference. A Java `null` in text fields is `""` here.
enum ExportsFixture {

    /// 2026-11-28T12:00:00Z
    static let t0 = Date(timeIntervalSince1970: 1_795_867_200)
    /// 2026-08-01T14:00:00Z
    static let e0 = Date(timeIntervalSince1970: 1_785_592_800)

    static func minute(_ m: Int) -> Date {
        t0.addingTimeInterval(TimeInterval(60 * m))
    }

    static func qso(_ time: Date?, _ call: String, _ hz: Int, _ mode: Mode?) -> Qso {
        var q = Qso()
        q.timestampUtc = time
        q.call = call
        q.freqHz = hz
        q.mode = mode
        return q
    }

    // MARK: - LogExports

    /// Java `LogExportsTest.log`.
    static func testLog() -> [Qso] {
        var a = qso(minute(1), "W1AW", 14_025_000, .cw)
        a.comment = "tnx, \"73\""
        let b = qso(minute(0), "DL1ABC", 7_010_000, .cw)
        let c = qso(minute(2), "G3AB", 14_200_000, .ssb)
        return [a, b, c]
    }

    /// An edge log: 50 Hz, quotes/CR/LF/commas, non-ASCII, without time, deleted, the same time.
    static func edgeLog(withUntimed: Bool) -> [Qso] {
        var out: [Qso] = []
        var a = qso(minute(2), "w1aw", 14_025_050, .cw)
        a.rstSent = "599"
        a.rstRcvd = "599"
        a.serialSent = 1
        a.serialRcvd = 15
        a.exchangeSent = "15"
        a.exchangeRcvd = "05"
        a.dxccName = "United States"
        a.continent = "NA"
        a.operator = "OK1XOE"
        a.comment = "a,b"
        out.append(a)
        var b = qso(minute(0), " ok1žá ", 7_000_250, .ssb)
        b.comment = "\"x\""
        b.exchangeRcvd = "ěščř"
        b.runMode = .searchAndPounce
        b.xqso = true
        b.dxccName = "Czech Republic"
        b.continent = "EU"
        b.operator = "Žofie 😀"
        out.append(b)
        if withUntimed {
            var c = qso(nil, "G3AB", 3_500_000, .cw)
            c.comment = "line1\r\nline2"
            out.append(c)
        }
        var d = qso(minute(2), "DL1ABC", 0, nil)
        d.comment = "cr\ronly"
        d.dxccName = "Germany"
        d.continent = "EU"
        out.append(d)
        var e = qso(minute(1), "DELETED", 14_000_000, .cw)
        e.deleted = true
        out.append(e)
        var f = qso(minute(3), "SP9XYZ", 14_025_150, .ft8)
        f.comment = "\"\u{0301} 73 😀"
        f.operator = "Žofie 😀"
        f.serialRcvd = -7
        f.dxccName = "Poland"
        f.continent = "EU"
        out.append(f)
        var g = qso(minute(1), "OK2ABC", 1_845_000, .cw)
        g.rstSent = "5nn"
        g.dxccName = "Czech Republic"
        g.continent = "EU"
        g.operator = "OK1XOE"
        out.append(g)
        var h = qso(Date(timeIntervalSince1970: 1_795_910_700), "JA1ABC", 21_000_000, .ssb)
        h.dxccName = "Japan"
        h.continent = "AS"
        h.operator = "  "
        h.runMode = .searchAndPounce
        out.append(h)
        return out
    }

    /// A pivot in the probe's text shape: `R <row> <sum>: <column>=<count>…`, `C …`, `T …`.
    static func pivotText(_ p: LogStatistics.Pivot) -> String {
        var out = ""
        for row in p.rows {
            out += "R " + row + " " + String(p.rowTotal(row) ?? -1) + ":"
            for col in p.cols {
                out += " " + col + "=" + String(p.count(row, col))
            }
            out += "\n"
        }
        for col in p.cols {
            out += "C " + col + " " + String(p.colTotal(col) ?? -1) + "\n"
        }
        return out + "T " + String(p.total) + "\n"
    }

    // MARK: - EDI

    static func edi(_ minute: Int, _ call: String, _ mode: Mode?, _ exch: String, _ nrSent: Int?) -> Qso {
        var q = Qso()
        q.timestampUtc = minute < 0 ? nil : e0.addingTimeInterval(TimeInterval(60 * minute))
        q.call = call
        q.freqHz = 144_300_000
        q.mode = mode
        q.rstSent = "59"
        q.rstRcvd = "59"
        q.serialSent = nrSent
        q.exchangeRcvd = exch
        return q
    }

    /// Java `EdiExporterTest.reg1testHeaderAndRecords`.
    static func ediTestLog() -> [Qso] {
        let rows: [(Int, String, String, Int)] = [
            (0, "DL1ABC", "59 5 JO62QM", 1), (5, "OK2XX", "59 12 JN89AA", 2), (9, "DL1ABC", "59 5 JO62QM", 3),
        ]
        return rows.map { row in
            var q = edi(row.0, row.1, .ssb, row.2, row.3)
            q.dxccName = row.1.hasPrefix("DL") ? "Germany" : "Czech Republic"
            return q
        }
    }

    static func ediEdgeLog() -> [Qso] {
        var out: [Qso] = []
        var a = edi(0, "DL1ABC", .ssb, "59 5 jo62qm", 1)
        a.dxccName = "Germany"
        out.append(a)
        var b = edi(1, "OK1KHL", .cw, "599 7 JO70FC", 2)
        b.rstSent = " 599 "
        b.rstRcvd = "599\t"
        b.dxccName = "Czech Republic"
        out.append(b)
        var c = edi(2, "OK2XX", .fm, "59 12345 XX00", 3)
        c.serialRcvd = 42
        out.append(c)
        var d = edi(3, "dl1abc", .ssb, "59 6 JO62QM", 4)
        d.dxccName = "Germany"
        out.append(d)
        var f = edi(4, "S51A", nil, "59 0012 JN76TO", nil)
        f.xqso = true
        f.dxccName = "Slovenia"
        out.append(f)
        var g = edi(5, "OE3XYZ", .am, "59 abc JN88", 5)
        g.dxccName = "Austria"
        out.append(g)
        var h = edi(6, "9A1A", .ft8, "jn75", 6)
        h.dxccName = "Croatia"
        out.append(h)
        var i = edi(7, "HA1A", .rtty, "59 3 JN87AB extra JN97CD", 7)
        i.dxccName = "Hungary"
        out.append(i)
        var j = edi(8, "YU1A", .ssb, "59 8 kn04aa", 8)
        j.dxccName = "Serbia"
        out.append(j)
        var k = edi(9, "OK1AAA", .ssb, "59 1 JN79AA", 9)
        k.freqHz = 432_100_000
        k.dxccName = "Czech Republic"
        out.append(k)
        var l = edi(10, "OK1DEL", .ssb, "59 1 JO80AA", 10)
        l.deleted = true
        out.append(l)
        out.append(edi(-1, "OK1BBB", .ssb, "59 1 JO80AA", 11))
        var n = edi(11, "SP2B", .cw, "59 10 JO94AA", 12)
        n.serialRcvd = -5
        n.dxccName = "Poland"
        out.append(n)
        var o = edi(11, "SP1A", .cw, "59 9 JO93AA", 13)
        o.dxccName = "Poland"
        out.append(o)
        return out
    }

    static func iaruVhf() throws -> ContestDefinition {
        let defs = try ContestCatalog.fromDir(SessionFixture.contestData().appendingPathComponent("contests"))
        guard let def = defs.first(where: { $0.id == "iaru-r1-vhf" }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return def
    }

    /// `def.exchange().received()` (a definition has no `null` items).
    static func received(_ def: ContestDefinition) -> [ContestDefinition.ExchangeField] {
        (def.exchange?.received ?? []).compactMap { $0 }
    }

    // MARK: - paginate

    static func pages(_ lines: [String], _ header: Int, _ perPage: Int) -> String {
        var out = ""
        for page in LogPrinter.paginate(lines, headerLines: header, linesPerPage: perPage) {
            out += page.joined(separator: "|") + "\n"
        }
        return out
    }

    // MARK: - Comparison and input guards

    /// UTF-8 bytes — comparison with Java by bytes, not by Swift `String ==` (which is canonical:
    /// `Å` U+00C5 = `A` + U+030A).
    static func bytes(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    /// Text split after every `\n` (the line end stays) — the shape of the `ExportsMeasured` fields.
    static func lines(_ text: String) -> [[UInt8]] {
        var out: [[UInt8]] = []
        var current: [UInt8] = []
        for byte in text.utf8 {
            current.append(byte)
            if byte == 0x0A {
                out.append(current)
                current = []
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// The canonical row of an input QSO as `ProbeExports.inputLine` (Java `null` = `""`).
    static func inputLine(_ q: Qso) -> String {
        let millis: String = q.timestampUtc.map { String(Int64(($0.timeIntervalSince1970 * 1000).rounded())) } ?? ""
        let fields: [String] = [
            millis, q.call, String(q.freqHz), q.band?.adif ?? "", q.mode?.rawValue ?? "", q.rstSent, q.rstRcvd,
            q.serialSent.map { String($0) } ?? "", q.serialRcvd.map { String($0) } ?? "", q.exchangeSent,
            q.exchangeRcvd, q.dxccName, q.continent, q.operator, q.comment, q.runMode.rawValue,
            String(q.xqso), String(q.deleted),
        ]
        return fields.joined(separator: "\t") + "\n"
    }
}
