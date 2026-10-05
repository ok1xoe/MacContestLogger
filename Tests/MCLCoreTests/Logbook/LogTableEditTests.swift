import Foundation
import Testing
@testable import MCLCore

/// `LogTableEdit` and `BulkAction` against the Kotlin log table (`ui/LogTable.kt`, v1.1.1). The edit rows are
/// a maintainer-only probe: the real private `applyEdit` called on the JVM over the QSO of
/// `base()`; the bulk texts and statuses are read from the source (`LT:376-413`, `AppState.bulkUpdate`).
@Suite struct LogTableEditTests {

    struct Row: Sendable {
        let column: LogTableEdit.Column
        let input: String
        let time: String
        let call: String
        let rstSent: String
        let rstRcvd: String
        let serialSent: Int?
        let serialRcvd: Int?
        let exchange: String
        let note: String

        init(_ column: LogTableEdit.Column, _ input: String, _ time: String, _ call: String, _ rstSent: String,
             _ rstRcvd: String, _ serialSent: Int?, _ serialRcvd: Int?, _ exchange: String, _ note: String) {
            self.column = column
            self.input = input
            self.time = time
            self.call = call
            self.rstSent = rstSent
            self.rstRcvd = rstRcvd
            self.serialSent = serialSent
            self.serialRcvd = serialRcvd
            self.exchange = exchange
            self.note = note
        }
    }

    /// The QSO the probe edits (`LogEditProbe.base()`).
    static func base() -> Qso {
        var q = Qso()
        q.id = 7
        q.timestampUtc = Date(timeIntervalSince1970: 1_790_944_496) // 2026-10-02 12:34:56Z
        q.call = "OK1ABC"
        q.freqHz = 14_025_000
        q.mode = .cw
        q.rstSent = "599"
        q.rstRcvd = "579"
        q.serialSent = 12
        q.serialRcvd = 34
        q.exchangeRcvd = "15"
        q.comment = "note"
        return q
    }

    static let rows: [Row] = [
        timeRows, callRows, rstSentRows, rstRcvdRows, serialSentRows, serialRcvdRows, exchangeRows, noteRows,
    ].flatMap { $0 }

    static let timeRows: [Row] = [
        Row(.time, "2026-10-02 13:00:00", "2026-10-02 13:00:00", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, " 2026-10-02 13:00:00 ", "2026-10-02 13:00:00", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "\u{00A0}2026-10-02 13:00:00\u{00A0}", "2026-10-02 13:00:00", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "\u{0001}2026-10-02 13:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "\u{0009}2026-10-02 13:00:00\u{000A}", "2026-10-02 13:00:00", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-02-30 10:00:00", "2026-02-28 10:00:00", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-02-29 10:00:00", "2026-02-28 10:00:00", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2024-02-30 10:00:00", "2024-02-29 10:00:00", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-04-31 23:59:59", "2026-04-30 23:59:59", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-10-02 24:00:00", "2026-10-03 00:00:00", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-10-02 24:00:01", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-12-31 24:00:00", "2027-01-01 00:00:00", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-10-02 23:60:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-10-02 23:59:60", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-1-02 13:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-10-2 13:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-10-02 1:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-10-02T13:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-10-02  13:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "02026-10-02 13:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "+12026-10-02 13:00:00", "+12026-10-02 13:00:00", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "12026-10-02 13:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "0000-01-01 00:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "0001-01-01 00:00:00", "0001-01-01 00:00:00", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "-0001-01-01 00:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-13-01 00:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-00-10 00:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-10-00 00:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-10-32 00:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "   ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "garbage", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "2026-10-02 13:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "\u{0662}\u{0660}\u{0662}\u{0666}-10-02 13:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "+999999999-12-31 23:59:59", "+999999999-12-31 23:59:59", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.time, "+999999999-12-31 24:00:00", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
    ]

    static let callRows: [Row] = [
        Row(.call, "", "2026-10-02 12:34:56", "", "599", "579", 12, 34, "15", "note"),
        Row(.call, " ", "2026-10-02 12:34:56", "", "599", "579", 12, 34, "15", "note"),
        Row(.call, "\u{00A0}", "2026-10-02 12:34:56", "\u{00A0}", "599", "579", 12, 34, "15", "note"),
        Row(.call, "ok1xyz", "2026-10-02 12:34:56", "OK1XYZ", "599", "579", 12, 34, "15", "note"),
        Row(.call, " ok1xyz ", "2026-10-02 12:34:56", "OK1XYZ", "599", "579", 12, 34, "15", "note"),
        Row(.call, "\u{00A0}ok1xyz\u{00A0}", "2026-10-02 12:34:56", "\u{00A0}OK1XYZ\u{00A0}", "599", "579", 12, 34, "15", "note"),
        Row(.call, "\u{0001}ok1xyz", "2026-10-02 12:34:56", "OK1XYZ", "599", "579", 12, 34, "15", "note"),
        Row(.call, "59", "2026-10-02 12:34:56", "59", "599", "579", 12, 34, "15", "note"),
        Row(.call, " 59 ", "2026-10-02 12:34:56", "59", "599", "579", 12, 34, "15", "note"),
        Row(.call, "\u{0009}59\u{0009}", "2026-10-02 12:34:56", "59", "599", "579", 12, 34, "15", "note"),
        Row(.call, "12", "2026-10-02 12:34:56", "12", "599", "579", 12, 34, "15", "note"),
        Row(.call, " 12 ", "2026-10-02 12:34:56", "12", "599", "579", 12, 34, "15", "note"),
        Row(.call, "+12", "2026-10-02 12:34:56", "+12", "599", "579", 12, 34, "15", "note"),
        Row(.call, "-3", "2026-10-02 12:34:56", "-3", "599", "579", 12, 34, "15", "note"),
        Row(.call, "0012", "2026-10-02 12:34:56", "0012", "599", "579", 12, 34, "15", "note"),
        Row(.call, "\u{0661}\u{0662}", "2026-10-02 12:34:56", "\u{0661}\u{0662}", "599", "579", 12, 34, "15", "note"),
        Row(.call, "2147483647", "2026-10-02 12:34:56", "2147483647", "599", "579", 12, 34, "15", "note"),
        Row(.call, "2147483648", "2026-10-02 12:34:56", "2147483648", "599", "579", 12, 34, "15", "note"),
        Row(.call, "1 2", "2026-10-02 12:34:56", "1 2", "599", "579", 12, 34, "15", "note"),
        Row(.call, "12a", "2026-10-02 12:34:56", "12A", "599", "579", 12, 34, "15", "note"),
        Row(.call, "abc", "2026-10-02 12:34:56", "ABC", "599", "579", 12, 34, "15", "note"),
        Row(.call, "stra\u{00DF}e", "2026-10-02 12:34:56", "STRASSE", "599", "579", 12, 34, "15", "note"),
        Row(.call, "\u{01C6}x", "2026-10-02 12:34:56", "\u{01C4}X", "599", "579", 12, 34, "15", "note"),
        Row(.call, "i1", "2026-10-02 12:34:56", "I1", "599", "579", 12, 34, "15", "note"),
        Row(.call, "15 dl", "2026-10-02 12:34:56", "15 DL", "599", "579", 12, 34, "15", "note"),
        Row(.call, "\u{2007}x\u{2007}", "2026-10-02 12:34:56", "\u{2007}X\u{2007}", "599", "579", 12, 34, "15", "note"),
        Row(.call, "\u{3000}x\u{3000}", "2026-10-02 12:34:56", "\u{3000}X\u{3000}", "599", "579", 12, 34, "15", "note"),
    ]

    static let rstSentRows: [Row] = [
        Row(.rstSent, "", "2026-10-02 12:34:56", "OK1ABC", "", "579", 12, 34, "15", "note"),
        Row(.rstSent, " ", "2026-10-02 12:34:56", "OK1ABC", "", "579", 12, 34, "15", "note"),
        Row(.rstSent, "\u{00A0}", "2026-10-02 12:34:56", "OK1ABC", "", "579", 12, 34, "15", "note"),
        Row(.rstSent, "ok1xyz", "2026-10-02 12:34:56", "OK1ABC", "ok1xyz", "579", 12, 34, "15", "note"),
        Row(.rstSent, " ok1xyz ", "2026-10-02 12:34:56", "OK1ABC", " ok1xyz ", "579", 12, 34, "15", "note"),
        Row(.rstSent, "\u{00A0}ok1xyz\u{00A0}", "2026-10-02 12:34:56", "OK1ABC", "\u{00A0}ok1xyz\u{00A0}", "579", 12, 34, "15", "note"),
        Row(.rstSent, "\u{0001}ok1xyz", "2026-10-02 12:34:56", "OK1ABC", "\u{0001}ok1xyz", "579", 12, 34, "15", "note"),
        Row(.rstSent, "59", "2026-10-02 12:34:56", "OK1ABC", "59", "579", 12, 34, "15", "note"),
        Row(.rstSent, " 59 ", "2026-10-02 12:34:56", "OK1ABC", " 59 ", "579", 12, 34, "15", "note"),
        Row(.rstSent, "\u{0009}59\u{0009}", "2026-10-02 12:34:56", "OK1ABC", "\u{0009}59\u{0009}", "579", 12, 34, "15", "note"),
        Row(.rstSent, "12", "2026-10-02 12:34:56", "OK1ABC", "12", "579", 12, 34, "15", "note"),
        Row(.rstSent, " 12 ", "2026-10-02 12:34:56", "OK1ABC", " 12 ", "579", 12, 34, "15", "note"),
        Row(.rstSent, "+12", "2026-10-02 12:34:56", "OK1ABC", "+12", "579", 12, 34, "15", "note"),
        Row(.rstSent, "-3", "2026-10-02 12:34:56", "OK1ABC", "-3", "579", 12, 34, "15", "note"),
        Row(.rstSent, "0012", "2026-10-02 12:34:56", "OK1ABC", "0012", "579", 12, 34, "15", "note"),
        Row(.rstSent, "\u{0661}\u{0662}", "2026-10-02 12:34:56", "OK1ABC", "\u{0661}\u{0662}", "579", 12, 34, "15", "note"),
        Row(.rstSent, "2147483647", "2026-10-02 12:34:56", "OK1ABC", "2147483647", "579", 12, 34, "15", "note"),
        Row(.rstSent, "2147483648", "2026-10-02 12:34:56", "OK1ABC", "2147483648", "579", 12, 34, "15", "note"),
        Row(.rstSent, "1 2", "2026-10-02 12:34:56", "OK1ABC", "1 2", "579", 12, 34, "15", "note"),
        Row(.rstSent, "12a", "2026-10-02 12:34:56", "OK1ABC", "12a", "579", 12, 34, "15", "note"),
        Row(.rstSent, "abc", "2026-10-02 12:34:56", "OK1ABC", "abc", "579", 12, 34, "15", "note"),
        Row(.rstSent, "stra\u{00DF}e", "2026-10-02 12:34:56", "OK1ABC", "stra\u{00DF}e", "579", 12, 34, "15", "note"),
        Row(.rstSent, "\u{01C6}x", "2026-10-02 12:34:56", "OK1ABC", "\u{01C6}x", "579", 12, 34, "15", "note"),
        Row(.rstSent, "i1", "2026-10-02 12:34:56", "OK1ABC", "i1", "579", 12, 34, "15", "note"),
        Row(.rstSent, "15 dl", "2026-10-02 12:34:56", "OK1ABC", "15 dl", "579", 12, 34, "15", "note"),
        Row(.rstSent, "\u{2007}x\u{2007}", "2026-10-02 12:34:56", "OK1ABC", "\u{2007}x\u{2007}", "579", 12, 34, "15", "note"),
        Row(.rstSent, "\u{3000}x\u{3000}", "2026-10-02 12:34:56", "OK1ABC", "\u{3000}x\u{3000}", "579", 12, 34, "15", "note"),
    ]

    static let rstRcvdRows: [Row] = [
        Row(.rstRcvd, "", "2026-10-02 12:34:56", "OK1ABC", "599", "", 12, 34, "15", "note"),
        Row(.rstRcvd, " ", "2026-10-02 12:34:56", "OK1ABC", "599", "", 12, 34, "15", "note"),
        Row(.rstRcvd, "\u{00A0}", "2026-10-02 12:34:56", "OK1ABC", "599", "", 12, 34, "15", "note"),
        Row(.rstRcvd, "ok1xyz", "2026-10-02 12:34:56", "OK1ABC", "599", "ok1xyz", 12, 34, "15", "note"),
        Row(.rstRcvd, " ok1xyz ", "2026-10-02 12:34:56", "OK1ABC", "599", " ok1xyz ", 12, 34, "15", "note"),
        Row(.rstRcvd, "\u{00A0}ok1xyz\u{00A0}", "2026-10-02 12:34:56", "OK1ABC", "599", "\u{00A0}ok1xyz\u{00A0}", 12, 34, "15", "note"),
        Row(.rstRcvd, "\u{0001}ok1xyz", "2026-10-02 12:34:56", "OK1ABC", "599", "\u{0001}ok1xyz", 12, 34, "15", "note"),
        Row(.rstRcvd, "59", "2026-10-02 12:34:56", "OK1ABC", "599", "59", 12, 34, "15", "note"),
        Row(.rstRcvd, " 59 ", "2026-10-02 12:34:56", "OK1ABC", "599", " 59 ", 12, 34, "15", "note"),
        Row(.rstRcvd, "\u{0009}59\u{0009}", "2026-10-02 12:34:56", "OK1ABC", "599", "\u{0009}59\u{0009}", 12, 34, "15", "note"),
        Row(.rstRcvd, "12", "2026-10-02 12:34:56", "OK1ABC", "599", "12", 12, 34, "15", "note"),
        Row(.rstRcvd, " 12 ", "2026-10-02 12:34:56", "OK1ABC", "599", " 12 ", 12, 34, "15", "note"),
        Row(.rstRcvd, "+12", "2026-10-02 12:34:56", "OK1ABC", "599", "+12", 12, 34, "15", "note"),
        Row(.rstRcvd, "-3", "2026-10-02 12:34:56", "OK1ABC", "599", "-3", 12, 34, "15", "note"),
        Row(.rstRcvd, "0012", "2026-10-02 12:34:56", "OK1ABC", "599", "0012", 12, 34, "15", "note"),
        Row(.rstRcvd, "\u{0661}\u{0662}", "2026-10-02 12:34:56", "OK1ABC", "599", "\u{0661}\u{0662}", 12, 34, "15", "note"),
        Row(.rstRcvd, "2147483647", "2026-10-02 12:34:56", "OK1ABC", "599", "2147483647", 12, 34, "15", "note"),
        Row(.rstRcvd, "2147483648", "2026-10-02 12:34:56", "OK1ABC", "599", "2147483648", 12, 34, "15", "note"),
        Row(.rstRcvd, "1 2", "2026-10-02 12:34:56", "OK1ABC", "599", "1 2", 12, 34, "15", "note"),
        Row(.rstRcvd, "12a", "2026-10-02 12:34:56", "OK1ABC", "599", "12a", 12, 34, "15", "note"),
        Row(.rstRcvd, "abc", "2026-10-02 12:34:56", "OK1ABC", "599", "abc", 12, 34, "15", "note"),
        Row(.rstRcvd, "stra\u{00DF}e", "2026-10-02 12:34:56", "OK1ABC", "599", "stra\u{00DF}e", 12, 34, "15", "note"),
        Row(.rstRcvd, "\u{01C6}x", "2026-10-02 12:34:56", "OK1ABC", "599", "\u{01C6}x", 12, 34, "15", "note"),
        Row(.rstRcvd, "i1", "2026-10-02 12:34:56", "OK1ABC", "599", "i1", 12, 34, "15", "note"),
        Row(.rstRcvd, "15 dl", "2026-10-02 12:34:56", "OK1ABC", "599", "15 dl", 12, 34, "15", "note"),
        Row(.rstRcvd, "\u{2007}x\u{2007}", "2026-10-02 12:34:56", "OK1ABC", "599", "\u{2007}x\u{2007}", 12, 34, "15", "note"),
        Row(.rstRcvd, "\u{3000}x\u{3000}", "2026-10-02 12:34:56", "OK1ABC", "599", "\u{3000}x\u{3000}", 12, 34, "15", "note"),
    ]

    static let serialSentRows: [Row] = [
        Row(.serialSent, "", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, " ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "\u{00A0}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "ok1xyz", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, " ok1xyz ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "\u{00A0}ok1xyz\u{00A0}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "\u{0001}ok1xyz", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "59", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 59, 34, "15", "note"),
        Row(.serialSent, " 59 ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 59, 34, "15", "note"),
        Row(.serialSent, "\u{0009}59\u{0009}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 59, 34, "15", "note"),
        Row(.serialSent, "12", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.serialSent, " 12 ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.serialSent, "+12", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.serialSent, "-3", "2026-10-02 12:34:56", "OK1ABC", "599", "579", -3, 34, "15", "note"),
        Row(.serialSent, "0012", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.serialSent, "\u{0661}\u{0662}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "note"),
        Row(.serialSent, "2147483647", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 2147483647, 34, "15", "note"),
        Row(.serialSent, "2147483648", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "1 2", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "12a", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "abc", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "stra\u{00DF}e", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "\u{01C6}x", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "i1", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "15 dl", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "\u{2007}x\u{2007}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
        Row(.serialSent, "\u{3000}x\u{3000}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", nil, 34, "15", "note"),
    ]

    static let serialRcvdRows: [Row] = [
        Row(.serialRcvd, "", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, " ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "\u{00A0}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "ok1xyz", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, " ok1xyz ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "\u{00A0}ok1xyz\u{00A0}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "\u{0001}ok1xyz", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "59", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 59, "15", "note"),
        Row(.serialRcvd, " 59 ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 59, "15", "note"),
        Row(.serialRcvd, "\u{0009}59\u{0009}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 59, "15", "note"),
        Row(.serialRcvd, "12", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 12, "15", "note"),
        Row(.serialRcvd, " 12 ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 12, "15", "note"),
        Row(.serialRcvd, "+12", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 12, "15", "note"),
        Row(.serialRcvd, "-3", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, -3, "15", "note"),
        Row(.serialRcvd, "0012", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 12, "15", "note"),
        Row(.serialRcvd, "\u{0661}\u{0662}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 12, "15", "note"),
        Row(.serialRcvd, "2147483647", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 2147483647, "15", "note"),
        Row(.serialRcvd, "2147483648", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "1 2", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "12a", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "abc", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "stra\u{00DF}e", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "\u{01C6}x", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "i1", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "15 dl", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "\u{2007}x\u{2007}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
        Row(.serialRcvd, "\u{3000}x\u{3000}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, nil, "15", "note"),
    ]

    static let exchangeRows: [Row] = [
        Row(.exchange, "", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "", "note"),
        Row(.exchange, " ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "", "note"),
        Row(.exchange, "\u{00A0}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "", "note"),
        Row(.exchange, "ok1xyz", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "OK1XYZ", "note"),
        Row(.exchange, " ok1xyz ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "OK1XYZ", "note"),
        Row(.exchange, "\u{00A0}ok1xyz\u{00A0}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "OK1XYZ", "note"),
        Row(.exchange, "\u{0001}ok1xyz", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "\u{0001}OK1XYZ", "note"),
        Row(.exchange, "59", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "59", "note"),
        Row(.exchange, " 59 ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "59", "note"),
        Row(.exchange, "\u{0009}59\u{0009}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "59", "note"),
        Row(.exchange, "12", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "12", "note"),
        Row(.exchange, " 12 ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "12", "note"),
        Row(.exchange, "+12", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "+12", "note"),
        Row(.exchange, "-3", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "-3", "note"),
        Row(.exchange, "0012", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "0012", "note"),
        Row(.exchange, "\u{0661}\u{0662}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "\u{0661}\u{0662}", "note"),
        Row(.exchange, "2147483647", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "2147483647", "note"),
        Row(.exchange, "2147483648", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "2147483648", "note"),
        Row(.exchange, "1 2", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "1 2", "note"),
        Row(.exchange, "12a", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "12A", "note"),
        Row(.exchange, "abc", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "ABC", "note"),
        Row(.exchange, "stra\u{00DF}e", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "STRASSE", "note"),
        Row(.exchange, "\u{01C6}x", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "\u{01C4}X", "note"),
        Row(.exchange, "i1", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "I1", "note"),
        Row(.exchange, "15 dl", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15 DL", "note"),
        Row(.exchange, "\u{2007}x\u{2007}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "X", "note"),
        Row(.exchange, "\u{3000}x\u{3000}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "X", "note"),
    ]

    static let noteRows: [Row] = [
        Row(.note, "", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", ""),
        Row(.note, " ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", ""),
        Row(.note, "\u{00A0}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", ""),
        Row(.note, "ok1xyz", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "ok1xyz"),
        Row(.note, " ok1xyz ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "ok1xyz"),
        Row(.note, "\u{00A0}ok1xyz\u{00A0}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "ok1xyz"),
        Row(.note, "\u{0001}ok1xyz", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "\u{0001}ok1xyz"),
        Row(.note, "59", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "59"),
        Row(.note, " 59 ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "59"),
        Row(.note, "\u{0009}59\u{0009}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "59"),
        Row(.note, "12", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "12"),
        Row(.note, " 12 ", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "12"),
        Row(.note, "+12", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "+12"),
        Row(.note, "-3", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "-3"),
        Row(.note, "0012", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "0012"),
        Row(.note, "\u{0661}\u{0662}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "\u{0661}\u{0662}"),
        Row(.note, "2147483647", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "2147483647"),
        Row(.note, "2147483648", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "2147483648"),
        Row(.note, "1 2", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "1 2"),
        Row(.note, "12a", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "12a"),
        Row(.note, "abc", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "abc"),
        Row(.note, "stra\u{00DF}e", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "stra\u{00DF}e"),
        Row(.note, "\u{01C6}x", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "\u{01C6}x"),
        Row(.note, "i1", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "i1"),
        Row(.note, "15 dl", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "15 dl"),
        Row(.note, "\u{2007}x\u{2007}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "x"),
        Row(.note, "\u{3000}x\u{3000}", "2026-10-02 12:34:56", "OK1ABC", "599", "579", 12, 34, "15", "x"),
    ]

    @Test func baseMatchesTheProbe() {
        #expect(LogTableColumns.editTimeText(Self.base().timestampUtc) == "2026-10-02 12:34:56")
    }

    @Test(arguments: rows)
    func editMatchesKotlin(row: Row) {
        let q: Qso = LogTableEdit.apply(column: row.column, text: row.input, to: Self.base())
        let input: String = row.input
        if row.time.hasPrefix("+999999999") {
            // `Date` loses second precision there (known divergence "A date outside the `Date` range"): pinned only as
            // "the time was taken".
            #expect(q.timestampUtc != Self.base().timestampUtc, "\(input)")
        } else {
            #expect(LogTableColumns.editTimeText(q.timestampUtc) == row.time, "\(input)")
        }
        #expect(q.call == row.call, "\(input)")
        #expect(q.rstSent == row.rstSent, "\(input)")
        #expect(q.rstRcvd == row.rstRcvd, "\(input)")
        #expect(q.serialSent == row.serialSent, "\(input)")
        #expect(q.serialRcvd == row.serialRcvd, "\(input)")
        #expect(q.exchangeRcvd == row.exchange, "\(input)")
        #expect(q.comment == row.note, "\(input)")
    }

    /// Band, mode, X-QSO, warning, points and multiplier are not text cells: `applyEdit` leaves the QSO as it is.
    @Test func otherColumnsLeaveTheQsoUnchanged() {
        for column in [LogTableEdit.Column.band, .mode, .xqso, .warning, .points, .mult] {
            #expect(LogTableEdit.apply(column: column, text: "ok1xyz", to: Self.base()) == Self.base())
        }
    }

    @Test func editTextIsTheFullTimeOrTheCellText() {
        let q = Self.base()
        #expect(LogTableEdit.editText(q, column: .time) == "2026-10-02 12:34:56")
        #expect(LogTableEdit.editText(q, column: .serialSent) == "12")
        #expect(LogTableEdit.editText(q, column: .exchange) == "15")
        #expect(LogTableEdit.textColumns.map(\.rawValue) == [0, 1, 4, 5, 6, 7, 8, 9], "Kotlin column 0 + TEXT_COLS")
    }

    @Test func modesAreKotlinModeValues() {
        // Probe row MODES.
        #expect(LogTableEdit.modes.map(\.rawValue) == ["CW", "SSB", "FM", "AM", "RTTY", "PSK", "FT8", "FT4", "JT65",
                                                       "DIGITAL"])
        #expect(LogTableEdit.pickMode(.ft8, to: Self.base()).mode == .ft8)
    }

    @Test func toggleXqsoFlipsAndReports() {
        let on = LogTableEdit.toggleXqso(Self.base())
        #expect(on.qso.xqso)
        #expect(on.status.czech == "OK1ABC: X-QSO, nepočítá se")
        let off = LogTableEdit.toggleXqso(on.qso)
        #expect(!off.qso.xqso)
        #expect(off.status.czech == "OK1ABC: zase se počítá")
        let english = Self.translator(["zase se počítá": "counts again"])
        #expect(off.status.text(english) == "OK1ABC: counts again", "only the Kotlin tr part is translated")
    }

    static func translator(_ map: [String: String]) -> Translator {
        var entries: [JavaStringKey: String] = [:]
        for (key, value) in map {
            entries[JavaStringKey(key)] = value
        }
        return Translator(language: "en", translations: LanguageCatalog.Translations(entries))
    }

    // MARK: - Bulk actions

    static func rows(_ count: Int) -> [Qso] {
        (0..<count).map { i in
            var q = base()
            q.id = Int64(i + 1)
            q.timestampUtc = Date(timeIntervalSince1970: 1_790_944_496 + Double(i * 600 + (i == 1 ? 7 : 0)))
            return q
        }
    }

    @Test func labelsMatchKotlin() {
        // Probe rows BULK (Czech keys; Kotlin translates them when the enum initialises).
        let expected: [(String, String, String)] = [
            ("Operátor…", "Operátor", "Volačka operátora (prázdné = smazat)"),
            ("Mód…", "Mód", "CW, SSB, RTTY, FT8…"),
            ("Frekvence…", "Frekvence", "Frekvence v kHz (určí i pásmo), např. 14025.5"),
            ("Posun času…", "Posun času", "+5 / -5 minut, +1:30, -2h"),
            ("Interpolovat čas", "Interpolace času", ""),
            ("X-QSO", "X-QSO", ""),
        ]
        #expect(BulkAction.allCases.count == expected.count)
        for (action, labels) in zip(BulkAction.allCases, expected) {
            #expect(action.button.czech == labels.0)
            #expect(action.title.czech == labels.1)
            #expect(action.hint.czech == labels.2)
        }
        // Kotlin writes these outside `tr`; they must not follow the language.
        let english = Self.translator(["Frekvence…": "X", "Frekvence": "X", "X-QSO": "X", "CW, SSB, RTTY, FT8…": "X",
                                       "Mód": "Mode"])
        #expect(BulkAction.frequency.button.text(english) == "Frekvence…")
        #expect(BulkAction.frequency.title.text(english) == "Frekvence")
        #expect(BulkAction.xqso.button.text(english) == "X-QSO")
        #expect(BulkAction.mode.hint.text(english) == "CW, SSB, RTTY, FT8…")
        #expect(BulkAction.mode.title.text(english) == "Mode", "evaluated when shown")
        #expect(BulkAction.mode.dialogTitle(count: 3).czech == "Mód (3 QSO)")
        #expect(BulkAction.mode.dialogTitle(count: 3).text(english) == "Mode (3 QSO)")
        #expect(BulkAction.allCases.map(\.needsText) == [true, true, true, true, false, false])
    }

    @Test func operatorModeFrequencyAndShift() {
        let chosen = Self.rows(2)
        let op = BulkAction.operator.run(text: "  ok1xoe ", on: chosen)
        #expect(op.edits.map(\.new.operator) == ["OK1XOE", "OK1XOE"])
        #expect(op.edits.map(\.old) == chosen)
        #expect(op.status?.czech == "Operátor: upraveno 2 QSO")
        let english = Self.translator(["Operátor": "Operator"])
        #expect(op.status?.text(english) == "Operator: upraveno 2 QSO", "only the label follows the language")

        let mode = BulkAction.mode.run(text: " usb ", on: chosen)
        #expect(mode.edits.map(\.new.mode) == [.ssb, .ssb])
        #expect(mode.status?.czech == "Mód SSB: upraveno 2 QSO")
        let badMode = BulkAction.mode.run(text: " xyz ", on: chosen)
        #expect(badMode.edits.isEmpty)
        #expect(badMode.status?.czech == "Mód: neznámý „xyz“")

        let freq = BulkAction.frequency.run(text: "7010,5", on: chosen)
        #expect(freq.edits.map(\.new.freqHz) == [7_010_500, 7_010_500])
        #expect(freq.edits.map(\.new.band) == [.m40, .m40])
        #expect(freq.status?.czech == "Frekvence: upraveno 2 QSO")
        let badFreq = BulkAction.frequency.run(text: "5000", on: chosen)
        #expect(badFreq.status?.czech == "Frekvence: „5000“ není v žádném pásmu")

        let shift = BulkAction.shiftTime.run(text: "+1:30", on: chosen)
        #expect(shift.edits.map { $0.new.timestampUtc!.timeIntervalSince($0.old.timestampUtc!) } == [5_400, 5_400])
        #expect(shift.status?.czech == "Posun času: upraveno 2 QSO")
        let badShift = BulkAction.shiftTime.run(text: "0", on: chosen)
        #expect(badShift.status?.czech == "Posun času: neplatné „0“ (např. +5, -1:30, +2h)")
        #expect(BulkAction.shiftTime.run(text: "x", on: []).status != nil, "the input error shows even without rows")
    }

    @Test func emptySelectionDoesNothing() {
        for action in [BulkAction.operator, .mode, .frequency, .shiftTime, .xqso] {
            let outcome = action.run(text: "7010", on: [])
            if action == .mode {
                #expect(outcome.status?.czech == "Mód: neznámý „7010“")
            } else {
                #expect(outcome.status == nil, "\(action)")
            }
            #expect(outcome.edits.isEmpty)
        }
    }

    @Test func xqsoMarksAllUnlessAllAreMarked() {
        var chosen = Self.rows(3)
        chosen[1].xqso = true
        let on = BulkAction.xqso.run(text: nil, on: chosen)
        #expect(on.edits.map(\.new.xqso) == [true, true, true])
        #expect(on.edits.count == 3, "every chosen row is saved, also the one already marked")
        #expect(on.status?.czech == "X-QSO: upraveno 3 QSO")
        let off = BulkAction.xqso.run(text: nil, on: on.edits.map(\.new))
        #expect(off.edits.map(\.new.xqso) == [false, false, false])
        #expect(off.status?.czech == "Zrušení X-QSO: upraveno 3 QSO")
    }

    @Test func interpolation() {
        let three = Self.rows(3)
        let done = BulkAction.interpolate.run(text: nil, on: three)
        #expect(done.edits.count == 3)
        #expect(done.edits[1].new.timestampUtc == Date(timeIntervalSince1970: 1_790_945_100), "rounded to the minute")
        #expect(done.status?.czech == "Interpolace času: upraveno 3 QSO")
        var untimed = three
        untimed[2].timestampUtc = nil
        let nothing = BulkAction.interpolate.run(text: nil, on: untimed)
        #expect(nothing.edits.isEmpty)
        #expect(nothing.status?.czech == "Interpolace času: nic se nezměnilo")
        let few = "Interpolace času: vyber aspoň 3 QSO (první a poslední čas zůstanou)"
        #expect(BulkAction.interpolate.run(text: nil, on: Self.rows(2)).status?.czech == few)
        #expect(BulkAction.interpolate.run(text: nil, on: []).status?.czech == few)
        #expect(BulkAction.interpolate.run(text: nil, on: Self.rows(2)).edits.isEmpty)
    }
}
