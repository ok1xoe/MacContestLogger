import Foundation
import MCLCore

/// Window font size of the shared stepper (Kotlin `FontControls.kt`, project rule: every window has the stepper at
/// the top right). Not persisted: every window opens at `defaultSize`.
public enum WindowFont {
    public static let minSize = 8
    public static let maxSize = 28
    /// Kotlin `WINDOW_FONT_BASE`: the size at which a window's typography is at its original scale.
    public static let defaultSize = 12

    /// Kotlin `coerceFont`.
    public static func clamp(_ size: Int) -> Int {
        min(max(size, minSize), maxSize)
    }

    /// A text (or field) of design size `base` at the default window size, in a window set to `windowSize`. Kotlin
    /// `WindowFontScope` scales the typography by `fontSp / WINDOW_FONT_BASE` (`FontControls.kt:64-69`), so the size
    /// is multiplied, not shifted: 14 pt at stepper 20 is 23.3 pt.
    public static func size(_ base: Double, windowSize: Int) -> Double {
        base * Double(windowSize) / Double(defaultSize)
    }
}

/// The score strip of the main window (Kotlin `ScoreBar`, `K:EntryPanel.kt:1500-1528`).
public struct ScoreLine: Equatable, Sendable {
    public let qso: String
    public let points: String
    public let mult: String
    public let total: String

    /// In a contest the session's score (zeros before the first score); `nil` in free logging, which has no score.
    @MainActor
    public static func of(contest: ContestModel) -> ScoreLine? {
        guard contest.isActive else { return nil }
        let score: ScoreState? = contest.score
        let qso: Int32 = score?.qsoCount ?? 0
        let points: Int64 = score?.qsoPoints ?? 0
        let mult: Int32 = score?.multTotal ?? 0
        let total: Int64 = score?.total ?? 0
        return ScoreLine(qso: String(qso), points: String(points), mult: String(mult), total: String(total))
    }
}

/// The status line of the main window (Kotlin `StatusBar`, `KApp:516-541`).
public struct StatusLine: Equatable, Sendable {
    /// The sent exchange (`sentExchangeLine`); shown as „Předávaný kód: %s" when not blank.
    public let sentExchange: String?
    /// The status message, or the active rig's CAT status when there is none (`statusMessage.ifEmpty { cat.status }`).
    public let message: String
    /// The active contest's name (or id), `nil` outside a contest or when blank.
    public let contestName: String?

    /// Kotlin `state.cat.status` without a rig session (`CatConnection.status`: `statusText ?: tr("TRX odpojen")`).
    public static let catDisconnectedKey = "TRX odpojen"

    @MainActor
    public static func of(_ app: AppModel) -> StatusLine {
        let sent: String = app.entry.sentExchangeText
        let status: String = app.status.message
        let message: String = status.isEmpty ? app.rig.activeStatus : status
        let contest: ContestModel = app.contest
        let name: String? = contest.activeName ?? contest.activeId
        let shownName: String? = contest.isActive ? KotlinStrings.nilIfBlank(name) : nil
        let shownSent: String? = contest.isActive ? KotlinStrings.nilIfBlank(sent) : nil
        return StatusLine(sentExchange: shownSent, message: message, contestName: shownName)
    }
}

/// What the entry window shows under the fields for the typed call (Kotlin `K:EntryPanel.kt:1158-1182`).
public enum EntryFeedback: Equatable, Sendable {
    /// One multiplier chip: the binding id and the state's short text (a Czech translation key).
    public struct Chip: Equatable, Sendable {
        public let bindingId: String
        public let stateKey: String
        public let state: MultiplierEvalResult.MultiplierState
    }

    case none
    /// A contest preview: the DUPE chip and the multiplier chips.
    case contest(dupe: Bool, chips: [Chip])

    @MainActor
    public static func of(entry: EntryModel, contest: ContestModel) -> EntryFeedback {
        let call: String = entry.form.call
        if contest.isActive {
            guard let preview = contest.lastPreview, !KotlinStrings.isBlank(call) else { return .none }
            let chips: [Chip] = preview.multipliers.map { result in
                Chip(bindingId: result.bindingId ?? "null", stateKey: shortStateKey(result.state),
                     state: result.state)
            }
            return .contest(dupe: preview.dupe, chips: chips)
        }
        return .none
    }

    /// Kotlin `shortState`.
    public static func shortStateKey(_ state: MultiplierEvalResult.MultiplierState) -> String {
        switch state {
        case .knownNewMultiplier: return "NOVÝ"
        case .knownAlreadyWorked: return "už"
        case .unknownAccepted: return "neznámý"
        case .suspicious: return "podezřelý"
        case .invalidFormat: return "chybný"
        }
    }

    /// Kotlin: in a contest without the station call a warning is shown (points are relative to the own station).
    @MainActor
    public static func missingStationCall(_ contest: ContestModel) -> Bool {
        contest.isActive && KotlinStrings.isBlank(contest.runtime.stationCall)
    }
}
