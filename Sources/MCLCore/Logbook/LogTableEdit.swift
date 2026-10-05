import Foundation

/// Editing in the logbook table („Přehled spojení"): the in-cell edit, the mode pick, the X-QSO toggle.
///
/// Port of `applyEdit`, `onPickMode` and `onToggleXqso` of the Kotlin `ui/LogTable.kt` (v1.1.1, `LT:356-367,
/// 786-799`), measured by a maintainer-only probe. The functions return the edited QSO; saving it
/// (`LogbookMutations.update`) and the rescore are the caller's.
///
/// `apply` is literal, quirks included:
/// - the callsign is set as typed — only the `Qso.call` setter trims it (Java `trim`) and uppercases it, so a
///   no-break space stays and an emptied cell gives an empty callsign;
/// - the reports are blank → empty, otherwise **untrimmed** (`" 59 "` stays);
/// - the serial numbers are Kotlin `trim().toIntOrNull()` (`+5` → 5, `"١٢"` → 12, an overflow or text → none);
/// - the exchange is trimmed and uppercased (Kotlin `uppercase()`), the note only trimmed (blank → empty);
/// - the time is Kotlin `trim()` + `LocalDateTime.parse(…, "yyyy-MM-dd HH:mm:ss")` in UTC with the SMART resolver
///   (`2026-02-30` → 28 Feb, `24:00:00` → the next midnight); an unparsable time leaves the time unchanged;
/// - any other column leaves the QSO as it is (Kotlin still saves it).
public enum LogTableEdit {

    public typealias Column = LogTableColumns.Column

    /// Columns edited in a text field (Kotlin column 0 and `TEXT_COLS`).
    public static let textColumns: [Column] = [
        .time, .call, .rstSent, .rstRcvd, .serialSent, .serialRcvd, .exchange, .note,
    ]

    /// The text the edit field starts with: the full time `yyyy-MM-dd HH:mm:ss` for the time column, otherwise the
    /// cell text (Kotlin `editValue`).
    public static func editText(_ qso: Qso, column: Column) -> String {
        if column == .time {
            return LogTableColumns.editTimeText(qso.timestampUtc)
        }
        return LogTableColumns.cellText(qso, column: column, marks: nil)
    }

    /// Kotlin `applyEdit(state, qso, col, text)` without the save.
    public static func apply(column: Column, text: String, to qso: Qso) -> Qso {
        var edited = qso
        switch column {
        case .time:
            if let date = N1mmContactParser.parseLocalDateTimeUtc(KotlinText.trim(text)) {
                edited.timestampUtc = date
            }
        case .call:
            edited.call = text
        case .rstSent:
            edited.rstSent = KotlinText.isBlank(text) ? "" : text
        case .rstRcvd:
            edited.rstRcvd = KotlinText.isBlank(text) ? "" : text
        case .serialSent:
            edited.serialSent = intOrNil(text)
        case .serialRcvd:
            edited.serialRcvd = intOrNil(text)
        case .exchange:
            let trimmed: String = KotlinText.trim(text)
            edited.exchangeRcvd = KotlinText.isBlank(trimmed) ? "" : JavaText.toUpperCase(trimmed)
        case .note:
            let trimmed: String = KotlinText.trim(text)
            edited.comment = KotlinText.isBlank(trimmed) ? "" : trimmed
        case .band, .mode, .xqso, .warning, .points, .mult:
            break
        }
        return edited
    }

    /// The modes of the mode cell's menu, in Kotlin `Mode.values()` order.
    public static let modes: [Mode] = Mode.allCases

    /// Kotlin `onPickMode`: the picked mode, nothing else.
    public static func pickMode(_ mode: Mode, to qso: Qso) -> Qso {
        var edited = qso
        edited.mode = mode
        return edited
    }

    /// Kotlin `onToggleXqso`: flips the X-QSO flag; the status is `"<CALL>: " + tr("X-QSO, nepočítá se")` or
    /// `tr("zase se počítá")` (the callsign and the separator are outside `tr`).
    public static func toggleXqso(_ qso: Qso) -> (qso: Qso, status: ContestMessage) {
        var edited = qso
        edited.xqso = !qso.xqso
        let key: String = edited.xqso ? "X-QSO, nepočítá se" : "zase se počítá"
        let status = ContestMessage(verbatimPattern, parts: [.value(.string(edited.call)), .message(ContestMessage(key))])
        return (edited, status)
    }

    /// Kotlin `trim().toIntOrNull()`.
    private static func intOrNil(_ text: String) -> Int? {
        KotlinNumber.toIntOrNull(KotlinText.trim(text)).map { Int($0) }
    }

    /// `"<a>: <b>"` — a pattern that is no translation key (Kotlin concatenates the parts outside `tr`).
    static let verbatimPattern = "%s: %s"
}

/// A bulk edit of the selected rows of the logbook table (N1MM Log window → right click). Port of the Kotlin
/// `BulkAction` and of its handling in `ui/LogTable.kt` (`LT:376-413`) over `BulkEdit`.
///
/// The labels are `ContestMessage`s evaluated when shown (Kotlin translates them once, when the enum is
/// initialised — a technique difference); the ones Kotlin writes outside `tr` are verbatim.
public enum BulkAction: CaseIterable, Sendable {
    case `operator`, mode, frequency, shiftTime, interpolate, xqso

    /// The button of the selection bar.
    public var button: ContestMessage {
        switch self {
        case .operator: return ContestMessage("Operátor…")
        case .mode: return ContestMessage("Mód…")
        case .frequency: return .verbatim("Frekvence…")
        case .shiftTime: return ContestMessage("Posun času…")
        case .interpolate: return ContestMessage("Interpolovat čas")
        case .xqso: return .verbatim("X-QSO")
        }
    }

    /// The title of the text dialog.
    public var title: ContestMessage {
        switch self {
        case .operator: return ContestMessage("Operátor")
        case .mode: return ContestMessage("Mód")
        case .frequency: return .verbatim("Frekvence")
        case .shiftTime: return ContestMessage("Posun času")
        case .interpolate: return ContestMessage("Interpolace času")
        case .xqso: return .verbatim("X-QSO")
        }
    }

    /// The hint of the text dialog.
    public var hint: ContestMessage {
        switch self {
        case .operator: return ContestMessage("Volačka operátora (prázdné = smazat)")
        case .mode: return .verbatim("CW, SSB, RTTY, FT8…")
        case .frequency: return ContestMessage("Frekvence v kHz (určí i pásmo), např. 14025.5")
        case .shiftTime: return .verbatim("+5 / -5 minut, +1:30, -2h")
        case .interpolate, .xqso: return .verbatim("")
        }
    }

    /// Whether the action asks for a text first (X-QSO and the interpolation run at once).
    public var needsText: Bool {
        switch self {
        case .interpolate, .xqso: return false
        default: return true
        }
    }

    /// Kotlin `action.title + " (${chosen.size} QSO)"`.
    public func dialogTitle(count: Int) -> ContestMessage {
        ContestMessage("%s (%s QSO)", parts: [.message(title), .value(.int(count))])
    }

    /// What a bulk action does: the rows to save (in the order of `chosen`) and the status text (`nil` = unchanged).
    /// Kotlin's `chosen` is the displayed rows in table order (`rows.filter { it.id in selected }`, `LT:377`) — the
    /// caller must pass that order, the interpolation anchors on it.
    public struct Outcome: Equatable, Sendable {
        public let edits: [LogbookMutations.Edit]
        public let status: ContestMessage?
    }

    /// Runs the action over the chosen rows. `text` is the dialog input (ignored by X-QSO and the interpolation).
    ///
    /// Kotlin `bulkUpdate(chosen, label, change)`: an empty selection does nothing (no status); a change that reports
    /// nothing changed gives `tr("%s: nic se nezměnilo", label)`; otherwise **every** chosen row is saved and the
    /// status is `"<label>: upraveno <n> QSO"` (outside `tr`). An invalid input gives its error text even for an
    /// empty selection. The interpolation of fewer than 3 rows ends with
    /// `tr("Interpolace času: vyber aspoň 3 QSO (první a poslední čas zůstanou)")`.
    public func run(text: String?, on chosen: [Qso]) -> Outcome {
        let t: String = KotlinText.trim(text ?? "")
        switch self {
        case .xqso:
            let on: Bool = !chosen.allSatisfy(\.xqso)
            let label: ContestMessage = on ? .verbatim("X-QSO") : ContestMessage("Zrušení X-QSO")
            return Self.bulkUpdate(chosen, label) { list in
                for i in list.indices {
                    list[i].xqso = on
                }
                return true
            }
        case .interpolate:
            let outcome = Self.bulkUpdate(chosen, ContestMessage("Interpolace času")) { list in
                BulkEdit.interpolateTime(&list)
            }
            if chosen.count < 3 {
                let status = ContestMessage("Interpolace času: vyber aspoň 3 QSO (první a poslední čas zůstanou)")
                return Outcome(edits: outcome.edits, status: status)
            }
            return outcome
        case .operator:
            return Self.bulkUpdate(chosen, ContestMessage("Operátor")) { list in
                BulkEdit.setOperator(&list, operator: t)
                return true
            }
        case .mode:
            guard let mode = Mode.from(adif: t) else {
                return Outcome(edits: [], status: ContestMessage("Mód: neznámý „%s“", .string(t)))
            }
            return Self.bulkUpdate(chosen, ContestMessage("Mód %s", .string(mode.rawValue))) { list in
                BulkEdit.setMode(&list, mode: mode)
                return true
            }
        case .frequency:
            guard let hz = BulkEdit.parseFrequencyKHz(t) else {
                return Outcome(edits: [], status: ContestMessage("Frekvence: „%s“ není v žádném pásmu", .string(t)))
            }
            return Self.bulkUpdate(chosen, .verbatim("Frekvence")) { list in
                BulkEdit.setFrequencyHz(&list, freqHz: hz)
                return true
            }
        case .shiftTime:
            guard let seconds = BulkEdit.parseShift(t) else {
                let status = ContestMessage("Posun času: neplatné „%s“ (např. +5, -1:30, +2h)", .string(t))
                return Outcome(edits: [], status: status)
            }
            return Self.bulkUpdate(chosen, ContestMessage("Posun času")) { list in
                BulkEdit.shiftTime(&list, by: seconds)
                return true
            }
        }
    }

    /// Kotlin `AppState.bulkUpdate` without the saves.
    private static func bulkUpdate(_ selected: [Qso], _ label: ContestMessage,
                                   _ change: (inout [Qso]) -> Bool) -> Outcome {
        if selected.isEmpty {
            return Outcome(edits: [], status: nil)
        }
        var changed: [Qso] = selected
        if !change(&changed) {
            return Outcome(edits: [], status: ContestMessage("%s: nic se nezměnilo", parts: [.message(label)]))
        }
        var edits: [LogbookMutations.Edit] = []
        for (old, new) in zip(selected, changed) {
            edits.append(LogbookMutations.Edit(old: old, new: new))
        }
        let status = ContestMessage(updatedPattern, parts: [.message(label), .value(.int(selected.count))])
        return Outcome(edits: edits, status: status)
    }

    /// `"$label: upraveno ${n} QSO"` — Kotlin writes it outside `tr`; the pattern is no translation key, so only the
    /// label follows the language.
    static let updatedPattern = "%s: upraveno %s QSO"
}
