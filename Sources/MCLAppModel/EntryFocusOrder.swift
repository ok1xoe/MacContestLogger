import Foundation
import MCLCore

/// An input field of the entry window that takes part in Tab / Shift+Tab / space navigation.
public enum EntryFieldKey: Hashable, Sendable {
    case call
    case rstSent
    /// Free logging: the received report (Kotlin `Rcv`).
    case rstRcvd
    /// Free logging: the exchange (Kotlin `Exch`).
    case exchange
    /// A received field of the active contest, by its id.
    case contest(String?)
    /// The post-contest time field „Čas UTC" (not in the Tab order: Kotlin gives it only the shared `keys`).
    case time
}

/// Field order of the entry window (Kotlin `tabOrder`, `moveFocus`, `focusExchange`, `K:EntryPanel.kt:686-721` and
/// the call field's space handler `:1100-1118`): call, sent report, then the contest's received fields (or Rcv and
/// Exch outside a contest). Tab walks every field, the space bar skips the reports.
public struct EntryFocusOrder: Equatable, Sendable {

    public struct Entry: Equatable, Sendable {
        public let key: EntryFieldKey
        /// A report field (RST/RS), skipped by the space bar.
        public let isReport: Bool
    }

    public let entries: [Entry]
    /// Where the space bar in the call field jumps (Kotlin `focusExchange`): the first contest field that is not a
    /// report, else the first contest field; `Exch` outside a contest; `nil` = a contest without received fields.
    public let exchangeTarget: EntryFieldKey?

    public init(contestActive: Bool, fields: [ContestDefinition.ExchangeField]) {
        var entries: [Entry] = [Entry(key: .call, isReport: false), Entry(key: .rstSent, isReport: true)]
        if contestActive {
            // Kotlin `cfields.associate { it.id to FocusRequester() }`: one requester per id, so a repeated id
            // (a broken definition) focuses one shared field.
            for field in fields {
                entries.append(Entry(key: .contest(field.id), isReport: Self.isReport(field)))
            }
            let target: ContestDefinition.ExchangeField? = fields.first { !Self.isReport($0) } ?? fields.first
            exchangeTarget = target.map { .contest($0.id) }
        } else {
            entries.append(Entry(key: .rstRcvd, isReport: true))
            entries.append(Entry(key: .exchange, isReport: false))
            exchangeTarget = .exchange
        }
        self.entries = entries
    }

    /// Kotlin `isReport`: RST or RS.
    public static func isReport(_ field: ContestDefinition.ExchangeField) -> Bool {
        field.type == .RST || field.type == .RS
    }

    /// Kotlin `moveFocus(from, direction, skipReports)`: the next field in `direction` (wrapping around), skipping
    /// reports when asked; `nil` when `from` is not in the order or every other field is skipped.
    public func next(from key: EntryFieldKey, direction: Int, skipReports: Bool) -> EntryFieldKey? {
        guard let start = entries.firstIndex(where: { $0.key == key }) else { return nil }
        var index: Int = start
        for _ in 0..<entries.count {
            index = Self.floorMod(index + direction, entries.count)
            let entry: Entry = entries[index]
            if !(skipReports && entry.isReport) {
                return entry.key
            }
        }
        return nil
    }

    /// The space bar in the call field jumps to the exchange unless the call field holds a command that takes an
    /// argument (OPON, TOUR, BONUS…): Kotlin `call.trim().uppercase().substringBefore(' ')` in
    /// `CallFieldCommands.ARGUMENT_KEYWORDS`.
    public static func spaceJumpsFromCall(_ call: String) -> Bool {
        let upper: String = KotlinStrings.uppercase(KotlinStrings.trim(call))
        let first: String = upper.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        return !CallFieldCommands.isArgumentKeyword(first)
    }

    private static func floorMod(_ value: Int, _ modulus: Int) -> Int {
        let remainder: Int = value % modulus
        return remainder < 0 ? remainder + modulus : remainder
    }
}
