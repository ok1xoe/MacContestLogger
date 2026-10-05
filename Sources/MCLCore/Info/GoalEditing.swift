import Foundation

/// The logic of the goal editor and the goal import messages of v1.1.1 (`ui/GoalWindows.kt` — `hourLabel` `:59`,
/// `GoalEditorWindow` draft/save/bulk fill `:72-98`, `:130-142`, `:186-207`, `GoalFromLogWindow` status `:260-281`; `ui/RateWindow.kt`
/// `applyGoalImport` `:539-552`). Pure values; the draft is a dictionary of texts so a field can be emptied without a
/// zero being filled in. Measured through the real `GoalSet`/`GoalFileParser` (maintainer-only probe, rows
/// `hourLabel`, `hours`, `draft`, `filter`, `save`, `bulk`, `import`, `fromlog`); the composable glue is a
/// transcription.
public enum GoalEditing {

    /// The contest length when the definition has none (`DEFAULT_CONTEST_HOURS`).
    public static let defaultContestHours: Int = 48

    /// `2. den 22:00` from the key `dhh` (`GW:59`). The word "den" is a literal, not translated (as in Kotlin);
    /// the arithmetic is `Int`.
    public static func hourLabel(_ key: Int32) -> String {
        String(key / 100) + ". den " + JavaFormat.format("%02d", .int(Int(key % 100))) + ":00"
    }

    /// The hour keys of the editor (`GW:72-75`): the hours of the active contest by the definition's length.
    ///
    /// - Throws: `JavaDateTimeException` at the edges of the `Instant` range, like `GoalSet.hoursOf`.
    public static func hours(contestStart: JavaInstant?, definition: ContestDefinition?)
        throws(JavaDateTimeException) -> [Int32] {
        let duration: Int = definition?.period?.durationHours ?? defaultContestHours
        return try GoalSet.hoursOf(contestStart, Int32(truncatingIfNeeded: duration))
    }

    /// `filter(Char::isDigit)` of the text fields: only `Character.isDigit` UTF-16 units (also non-ASCII digits).
    public static func digitsOnly(_ text: String) -> String {
        JavaChar.string(text.utf16.filter { JavaChar.isDigit($0) })
    }

    /// The editor's draft: the text of every hour (`GW:78-83`).
    public struct Draft: Equatable, Sendable {
        public let hours: [Int32]
        public internal(set) var texts: [Int32: String]

        /// A draft with the given texts as they are (no digit filter) — for tests that replay hand-made drafts.
        init(hours: [Int32], texts: [Int32: String]) {
            self.hours = hours
            self.texts = texts
        }

        /// From the saved goals: the text of an hour with a goal is the number, otherwise empty. Saved goals of
        /// hours outside `hours` are not in the draft (and are dropped by the next save).
        public init(goalSet: GoalSet, hours: [Int32]) {
            self.hours = hours
            var texts: [Int32: String] = [:]
            for key in hours {
                texts[key] = goalSet.entries[key].map { String($0) } ?? ""
            }
            self.texts = texts
        }

        /// The text of an hour's field (`draft[key] ?: ""`).
        public func text(for key: Int32) -> String {
            texts[key] ?? ""
        }

        /// A field edit (`GW:160`): only digits are kept.
        public mutating func setText(_ text: String, for key: Int32) {
            texts[key] = GoalEditing.digitsOnly(text)
        }

        /// "Vymazat vše" (`GW:172`).
        public mutating func clearAll() {
            for key in hours {
                texts[key] = ""
            }
        }

        /// The goals as saved (`GW:89-93`): `trim().toIntOrNull()` of every text, non-negative ones only.
        public func goalSet() -> GoalSet {
            var byKey: [Int32: Int32] = [:]
            for (key, text) in texts {
                if let number = KotlinNumber.toIntOrNull(KotlinText.trim(text)), number >= 0 {
                    byKey[key] = number
                }
            }
            return GoalSet.of(byKey)
        }

        /// The number of hours with a goal — the count in the status text.
        public func goalCount() -> Int {
            goalSet().entries.count
        }
    }

    /// The bulk fill of a range of hours (`BulkFill`, `GW:186-207`, apply `GW:138-142`).
    public struct BulkFill: Equatable, Sendable {
        public private(set) var value: String = ""
        public var fromKey: Int32
        public var toKey: Int32

        /// The range starts as the whole contest (`hours.firstOrNull() ?: 0` … `hours.lastOrNull() ?: 0`).
        public init(hours: [Int32]) {
            fromKey = hours.first ?? 0
            toKey = hours.last ?? 0
        }

        /// An edit of the value field: only digits are kept.
        public mutating func setValue(_ text: String) {
            value = GoalEditing.digitsOnly(text)
        }

        /// "Vyplnit": the trimmed value into every hour of the range; the range ends may be swapped.
        public func apply(to draft: inout Draft) {
            let from: Int32 = min(fromKey, toKey)
            let to: Int32 = max(fromKey, toKey)
            let text: String = KotlinText.trim(value)
            for key in draft.hours where key >= from && key <= to {
                draft.texts[key] = text
            }
        }
    }

    // MARK: - Texts

    /// The explanation above the editor (`GW:123-127`): two `tr` pieces and the default goal.
    public static func helpText(translate: Translator = .source) -> String {
        translate.translate("Plánovaný počet QSO pro každou hodinu. Prázdné pole = s provozem ")
            + translate.translate("se nepočítá. Bez jediného vyplněného cíle platí ")
            + String(GoalSet.defaultGoal) + " na hodinu."
    }

    /// The text when there is no running contest with a start date (`GW:114-117`).
    public static func noContestText(translate: Translator = .source) -> String {
        translate.translate("Cíle se plánují po hodinách závodu, takže je potřeba běžící závod ")
            + translate.translate("s vyplněným datem startu.")
    }

    /// `Cíle uloženy (N hodin)` after a successful save from the editor (`GW:95`).
    public static func savedText(hours: Int, translate: Translator = .source) -> String {
        translate.translate("Cíle uloženy (%s hodin)", [.int(hours)])
    }

    /// `Uložení cílů selhalo (…)` (`GW:96`, `RW:541`).
    public static func saveFailedText(_ message: String?, translate: Translator = .source) -> String {
        translate.translate("Uložení cílů selhalo (%s)", [.string(message)])
    }

    /// The status after importing a goal file (`RW:539-552`): the count of goals, the band, and the first
    /// unrecognized line — ignored lines are not silenced, otherwise the operator would follow a plan that is
    /// not complete.
    public static func importStatus(_ result: GoalImport, band: String?, translate: Translator = .source) -> String {
        var text: String = translate.translate("Načteno %s cílů", [.int(result.goals.entries.count)])
        if let band {
            text += " " + translate.translate("(pásmo %s)", [.string(band)])
        }
        if let first = result.ignoredLines.first {
            text += translate.translate("; %s řádků nerozpoznáno: %s",
                                        [.int(result.ignoredLines.count), .string(first)])
        }
        return text
    }

    /// The status after taking goals from an earlier log (`GW:275-278` of `GoalFromLogWindow`):
    /// `Cíle převzaty ze závodu X (N hodin, pásmo 20m)`.
    public static func fromLogStatus(contestName: String, hours: Int, band: Band?,
                                     translate: Translator = .source) -> String {
        var text: String = translate.translate("Cíle převzaty ze závodu %s", [.string(contestName)])
        text += " (" + String(hours) + " hodin"
        if let band {
            text += translate.translate(", pásmo %s", [.string(band.adif)])
        }
        return text + ")"
    }

    /// The label of the band picker of that window (`GW:314`): the band or `všechna`.
    public static func bandLabel(_ band: Band?, translate: Translator = .source) -> String {
        band?.adif ?? translate.translate("všechna")
    }

    /// The explanation of that window (`GW:298`).
    public static func fromLogHelpText(translate: Translator = .source) -> String {
        translate.translate("Cílem každé hodiny bude počet spojení, která v ní ve vybraném závodu padla.")
    }
}
