import Foundation

/// The QSO edit dialog (N1MM Edit → Edit Last Contact, Ctrl+Y, and the Entry window's Edit button): every field of a
/// logged QSO as text, checked as a whole and applied to the stored row. The time is `yyyy-MM-dd HH:mm:ss` UTC, the
/// frequency in kHz (the band follows it), the mode one of `Mode`; the other fields are applied like the log table's
/// cell edits (`LogTableEdit.apply`).
public struct QsoEditForm: Equatable, Sendable {

    public var time: String
    public var call: String
    public var freqKHz: String
    public var mode: String
    public var rstSent: String
    public var rstRcvd: String
    public var serialSent: String
    public var serialRcvd: String
    public var exchange: String
    public var note: String
    public var `operator`: String
    public var xqso: Bool

    /// The form of a stored QSO.
    public init(_ qso: Qso) {
        time = LogTableColumns.editTimeText(qso.timestampUtc)
        call = qso.call
        freqKHz = qso.freqHz > 0 ? FrequencyText.formatHz(Int64(qso.freqHz)) : ""
        mode = qso.mode?.rawValue ?? ""
        rstSent = qso.rstSent
        rstRcvd = qso.rstRcvd
        serialSent = qso.serialSent.map { String($0) } ?? ""
        serialRcvd = qso.serialRcvd.map { String($0) } ?? ""
        exchange = qso.exchangeRcvd
        note = qso.comment
        `operator` = qso.operator
        xqso = qso.xqso
    }

    /// The time field as a date for the calendar of the dialog (`nil` while the text is not a valid time); setting it
    /// writes the text.
    public var date: Date? {
        get { N1mmContactParser.parseLocalDateTimeUtc(KotlinText.trim(time)) }
        set { time = LogTableColumns.editTimeText(newValue) }
    }

    /// The arrows of a serial number field: the number `delta` up or down, never below 1 (an empty or invalid field
    /// starts from 0).
    public static func steppedSerial(_ text: String, by delta: Int) -> String {
        let current: Int = Int(KotlinText.trim(text)) ?? 0
        return String(max(1, current + delta))
    }

    /// Why the form cannot be saved (a Czech translation key; `%s` = the offending text).
    public enum Problem: Error, Equatable, Sendable {
        case blankCall
        case time(String)
        case frequency(String)
        case mode(String)
        case serial(String)

        public var message: ContestMessage {
            switch self {
            case .blankCall: return ContestMessage("Volačka nesmí být prázdná")
            case .time(let text): return ContestMessage("Neplatný čas: %s (rrrr-mm-dd hh:mm:ss)",
                                                        parts: [.value(.string(text))])
            case .frequency(let text): return ContestMessage("Neplatná frekvence: %s", parts: [.value(.string(text))])
            case .mode(let text): return ContestMessage("Neznámý mód: %s", parts: [.value(.string(text))])
            case .serial(let text): return ContestMessage("Neplatné číslo: %s", parts: [.value(.string(text))])
            }
        }
    }

    /// The edited QSO, or the first problem of the form. Nothing that is not in the form changes.
    public func apply(to qso: Qso) -> Result<Qso, Problem> {
        if KotlinText.isBlank(call) {
            return .failure(.blankCall)
        }
        var edited: Qso = qso
        let trimmedTime: String = KotlinText.trim(time)
        if trimmedTime != LogTableColumns.editTimeText(qso.timestampUtc) {
            guard let date = N1mmContactParser.parseLocalDateTimeUtc(trimmedTime) else {
                return .failure(.time(trimmedTime))
            }
            edited.timestampUtc = date
        }
        let freqText: String = KotlinText.trim(freqKHz)
        if !freqText.isEmpty {
            let hz: Int64 = FrequencyText.parseHz(freqText)
            guard hz > 0, hz <= Int64(Int32.max) else { return .failure(.frequency(freqText)) }
            if hz != Int64(qso.freqHz) {
                edited.freqHz = Int(hz)
            }
        }
        let modeText: String = JavaText.toUpperCase(KotlinText.trim(mode))
        if modeText.isEmpty {
            edited.mode = nil
        } else {
            guard let parsed = Mode(rawValue: modeText) else { return .failure(.mode(modeText)) }
            edited.mode = parsed
        }
        for (text, column) in [(serialSent, LogTableEdit.Column.serialSent), (serialRcvd, .serialRcvd)] {
            let trimmed: String = KotlinText.trim(text)
            if !trimmed.isEmpty && KotlinNumber.toIntOrNull(trimmed) == nil {
                return .failure(.serial(trimmed))
            }
            edited = LogTableEdit.apply(column: column, text: text, to: edited)
        }
        edited = LogTableEdit.apply(column: .call, text: call, to: edited)
        edited = LogTableEdit.apply(column: .rstSent, text: KotlinText.trim(rstSent), to: edited)
        edited = LogTableEdit.apply(column: .rstRcvd, text: KotlinText.trim(rstRcvd), to: edited)
        edited = LogTableEdit.apply(column: .exchange, text: exchange, to: edited)
        edited = LogTableEdit.apply(column: .note, text: note, to: edited)
        edited.operator = JavaText.toUpperCase(KotlinText.trim(`operator`))
        edited.xqso = xqso
        return .success(edited)
    }
}
