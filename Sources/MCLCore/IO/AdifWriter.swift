import Foundation

/// Export of QSOs to ADIF format — port of `io/AdifWriter.java` (v1.1.1).
///
/// Document: line `ADIF export z MacContestLogger`, header (`ADIF_VER`, `PROGRAMID`,
/// optionally station data) terminated by `<EOH>\n`, then records terminated by `<EOR>\n`. Fields
/// `<NAME:length>value` + one space; **length is in UTF-16 units** like Java's
/// `String.length()` (emoji = 2). Empty fields are omitted, values are not sanitised.
/// Date and time in UTC (`yyyyMMdd`, `HHmmss`, seconds truncated).
///
/// Model divergence: `runMode` is non-optional in Swift, so `APP_N1MM_RUNNING` is always
/// written (Java omits it only on an explicit `setRunMode(null)`, which the app never does).
public struct AdifWriter: Sendable {

    /// ADIF `CONTEST_ID` for all records; `nil` = omit.
    public let contestId: String?

    /// - Parameter contestId: Cabrillo contest name; `nil` or blank (Java `isBlank`) = no contest.
    public init(contestId: String? = nil) {
        if let contestId, !JavaText.isBlank(contestId) {
            self.contestId = contestId
        } else {
            self.contestId = nil
        }
    }

    /// The whole ADIF document. With `station` writes `STATION_CALLSIGN`, `OPERATOR`,
    /// `MY_GRIDSQUARE` and `MY_NAME` to the header (empty ones omitted).
    public func toAdif(_ qsos: [Qso], station: Station? = nil) -> String {
        var out = "ADIF export z MacContestLogger\n"
        Self.field(&out, "ADIF_VER", "3.1.4")
        Self.field(&out, "PROGRAMID", "MacContestLogger")
        if let station {
            Self.field(&out, "STATION_CALLSIGN", station.call)
            Self.field(&out, "OPERATOR", station.operator)
            Self.field(&out, "MY_GRIDSQUARE", station.gridSquare)
            Self.field(&out, "MY_NAME", station.name)
        }
        out += "<EOH>\n"
        for q in qsos {
            appendRecord(&out, q)
        }
        return out
    }

    /// Writes the document to a file in UTF-8 (no BOM, non-atomically like `Files.writeString`).
    /// Write error → `UncheckedIOError("Nelze zapsat ADIF: <path>")`.
    public func writeToFile(_ qsos: [Qso], station: Station? = nil, to file: URL) throws(UncheckedIOError) {
        do {
            try Data(toAdif(qsos, station: station).utf8).write(to: file)
        } catch {
            throw UncheckedIOError(message: "Nelze zapsat ADIF: " + file.path, cause: error)
        }
    }

    /// A single record without header (Club Log realtime, UDP).
    public func record(_ q: Qso) -> String {
        var out = ""
        appendRecord(&out, q)
        return out
    }

    private func appendRecord(_ out: inout String, _ q: Qso) {
        if let timestamp = q.timestampUtc, let (day, second) = JavaLocalDate.split(timestamp) {
            let date = JavaLocalDate.civil(epochDay: day)
            let ymd: String = JavaLocalDate.formatYearOfEra(date.year)
                + JavaLocalDate.twoDigits(date.month) + JavaLocalDate.twoDigits(date.day)
            let hms: String = JavaLocalDate.twoDigits(second / 3600)
                + JavaLocalDate.twoDigits(second / 60 % 60) + JavaLocalDate.twoDigits(second % 60)
            Self.field(&out, "QSO_DATE", ymd)
            Self.field(&out, "TIME_ON", hms)
        }
        Self.field(&out, "CALL", q.call)
        if let band = q.band {
            Self.field(&out, "BAND", band.adif)
        }
        Self.field(&out, "FREQ", JavaFormat.fixed(Double(q.freqHz) / 1_000_000.0, precision: 6))
        if let mode = q.mode {
            Self.field(&out, "MODE", mode.adif)
        }
        Self.field(&out, "RST_SENT", q.rstSent)
        Self.field(&out, "RST_RCVD", q.rstRcvd)
        if let serial = q.serialSent {
            Self.field(&out, "STX", String(serial))
        }
        if let serial = q.serialRcvd {
            Self.field(&out, "SRX", String(serial))
        }
        // Exchange as text (ADIF 3: STX_STRING / SRX_STRING) — zones, districts, locators…
        Self.field(&out, "STX_STRING", JavaText.trim(q.exchangeSent))
        Self.field(&out, "SRX_STRING", JavaText.trim(q.exchangeRcvd))
        if let contestId {
            Self.field(&out, "CONTEST_ID", contestId)
        }
        if let dxcc = q.dxccEntity {
            Self.field(&out, "DXCC", String(dxcc))
        }
        Self.field(&out, "COUNTRY", q.dxccName)
        Self.field(&out, "CONT", q.continent)
        // N1MM extension: Run/S&P on the QSO.
        Self.field(&out, "APP_N1MM_RUNNING", q.runMode == .run ? "Y" : "N")
        Self.field(&out, "OPERATOR", q.operator)
        Self.field(&out, "COMMENT", q.comment)
        out += "<EOR>\n"
    }

    private static func field(_ out: inout String, _ name: String, _ value: String) {
        if value.isEmpty { return }
        out += "<"
        out += name
        out += ":"
        out += String(value.utf16.count)
        out += ">"
        out += value
        out += " "
    }
}
