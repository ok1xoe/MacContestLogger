import Foundation
import MCLCore
import Observation

/// The „Přiřadit volačku k zemi" window (N1MM „Add call to country"): the user's own call → DXCC entity list. The
/// list lives in `<data dir>/dxcc-overrides.json` (`DxccOverrideStore`) and is asked before every other DXCC source, so
/// an assignment applies to the next lookup at once. QSOs already in the log keep their country until „Přepočítat
/// DXCC v deníku" (the window offers it).
@Observable @MainActor
public final class DxccOverridesModel {

    /// An entity the country can be chosen from.
    public struct Choice: Equatable, Identifiable, Sendable {
        public let number: Int
        public let name: String
        public let prefix: String

        public var id: Int {
            number
        }

        /// `Germany (DL) · 230`.
        public var label: String {
            let head: String = prefix.isEmpty ? name : name + " (" + prefix + ")"
            return head + " · " + String(number)
        }
    }

    /// The assignments, in the order they were made.
    public private(set) var entries: [DxccOverrideStore.Entry] = []
    /// Every entity of the country data, by name.
    public private(set) var choices: [Choice] = []
    /// The callsign being assigned.
    public var call: String
    /// Narrows `shown` (name, prefix or number).
    public var filter: String = ""
    /// The chosen entity (its DXCC number).
    public var selected: Int?

    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let store: DxccOverrideStore?

    init(contest: ContestModel, status: StatusModel, call: String) {
        self.contest = contest
        self.status = status
        self.store = contest.dxccOverrides
        self.call = DxccOverrideStore.normalize(call)
        reload()
    }

    /// Reads the list and the entities again.
    public func reload() {
        entries = store?.all ?? []
        var seen: Set<Int> = []
        var list: [Choice] = []
        for entity in contest.runtime.dxccLookup?.entities() ?? [] {
            let number: Int = entity.adifDxcc ?? entity.entityCode
            guard seen.insert(number).inserted else { continue }
            list.append(Choice(number: number, name: entity.name ?? "?",
                               prefix: entity.primaryPrefix ?? entity.countryCode ?? ""))
        }
        choices = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let number = selected, !seen.contains(number) {
            selected = nil
        }
    }

    /// The entities matching `filter`.
    public var shown: [Choice] {
        let needle: String = filter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return choices }
        return choices.filter { $0.label.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    public var canAdd: Bool {
        store != nil && !DxccOverrideStore.normalize(call).isEmpty && selected != nil
    }

    public var hasEngine: Bool {
        contest.runtime.dxccLookup != nil
    }

    /// Assigns the call to the chosen entity (replacing an earlier assignment of the same call) and saves.
    public func add() async {
        guard let store, let number = selected, let choice = choices.first(where: { $0.number == number }) else {
            return
        }
        guard let stored = store.set(call: call, dxcc: number, name: choice.name) else { return }
        guard await save(store) else { return }
        status.show("Volačka %s přiřazena k zemi %s", .string(stored), .string(choice.name))
        reload()
        call = ""
    }

    /// Removes the assignment of `call` and saves.
    public func remove(_ call: String) async {
        guard let store, store.remove(call: call) else { return }
        guard await save(store) else { return }
        status.show("Přiřazení volačky %s odebráno", .string(call))
        reload()
    }

    private func save(_ store: DxccOverrideStore) async -> Bool {
        do {
            try await BlockingQueue.run {
                try store.save()
            }
            return true
        } catch {
            status.show("Uložení přiřazení selhalo: %s", .string(ErrorText.message(error)))
            reload()
            return false
        }
    }
}
