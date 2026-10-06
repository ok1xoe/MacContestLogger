/// Texts of the DX Cluster and Blacklist windows of v1.1.1 (`ui/DxClusterWindow.kt`: the favourite selection `:89-94`,
/// the parallel summary `:160-170`, the macro buttons `:175-187`, `favLabel` `:283`; `ui/BlacklistWindow.kt`:
/// `fmtAdded` `:48`).
public enum ClusterTexts {

    public static let noName = "— bez názvu —"
    public static let noCluster = "— žádný cluster —"
    public static let emptyMacro = "(prázdné)"
    public static let parallelKey = "Souběžně: %s"
    public static let parallelToggleKey = "Souběžné spojení: %s"
    public static let macroSaveFailedKey = "Uložení tlačítka selhalo (%s)"

    /// `favLabel`: the name, else the host, else `tr("— bez názvu —")` (Kotlin `ifBlank`).
    public static func favLabel(_ favorite: DxClusterFavorite, translator: Translator) -> String {
        if !KotlinText.isBlank(favorite.name) { return favorite.name }
        if !KotlinText.isBlank(favorite.host) { return favorite.host }
        return translator.translate(noName)
    }

    /// The initial selection: `lastFavorite`, when blank the first favourite's name, else `""`.
    public static func initialSelection(lastFavorite: String, favorites: [DxClusterFavorite]) -> String {
        KotlinText.isBlank(lastFavorite) ? (favorites.first?.name ?? "") : lastFavorite
    }

    /// The selected favourite: the first whose label or name equals the selection (`String.equals`), else the first.
    public static func selectedFavorite(_ selection: String, favorites: [DxClusterFavorite],
                                        translator: Translator) -> DxClusterFavorite? {
        let match = favorites.first { favorite in
            JavaText.equals(favLabel(favorite, translator: translator), selection)
                || JavaText.equals(favorite.name, selection)
        }
        return match ?? favorites.first
    }

    /// One parallel connection in the summary: the favourite's name (`ifBlank { null }`), else the status, then
    /// `" ✓"` logged in, `" …"` connected, `" ✗"` otherwise.
    public static func parallelItem(_ snapshot: DxClusterSession.Snapshot) -> String {
        let name: String? = snapshot.currentFavorite.flatMap { KotlinText.isBlank($0.name) ? nil : $0.name }
        return (name ?? snapshot.status) + " " + stateMark(snapshot)
    }

    /// `✓` logged in, `…` connected, `✗` otherwise (also without a connection at all).
    public static func stateMark(_ snapshot: DxClusterSession.Snapshot?) -> String {
        guard let snapshot else { return "✗" }
        if snapshot.loggedIn { return "✓" }
        return snapshot.connected ? "…" : "✗"
    }

    /// `tr("Souběžně: %s", …)` over the parallel connections joined by `" · "`; `nil` when there are none (the row is
    /// hidden).
    public static func parallelSummary(_ snapshots: [DxClusterSession.Snapshot]) -> EntryStatus? {
        if snapshots.isEmpty { return nil }
        let joined: String = snapshots.map(parallelItem).joined(separator: " · ")
        return .tr(parallelKey, .string(joined))
    }

    /// A macro button: the label, else the command, else `tr("(prázdné)")`.
    public static func macroLabel(_ command: DxClusterCommand, translator: Translator) -> String {
        if !KotlinText.isBlank(command.label) { return command.label }
        if !KotlinText.isBlank(command.command) { return command.command }
        return translator.translate(emptyMacro)
    }

    /// The edited button as saved: label and command Kotlin-trimmed.
    public static func editedMacro(label: String, command: String) -> DxClusterCommand {
        DxClusterCommand(label: KotlinText.trim(label), command: KotlinText.trim(command))
    }

    /// `tr("Uložení tlačítka selhalo (%s)", it.message)`.
    public static func macroSaveFailed(_ message: String?) -> EntryStatus {
        .tr(macroSaveFailedKey, .string(message))
    }

    /// `fmtAdded`: `"—"` for a blank time, otherwise the first 16 UTF-16 units with `T` replaced by a space.
    public static func fmtAdded(_ iso: String) -> String {
        if KotlinText.isBlank(iso) { return "—" }
        let units: [UInt16] = Array(iso.utf16.prefix(16))
        let replaced: [UInt16] = units.map { $0 == 0x54 ? 0x20 : $0 }
        return JavaChar.string(replaced)
    }
}
