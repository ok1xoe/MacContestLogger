import Testing
@testable import MCLCore

/// `ClusterTexts` against `ui/DxClusterWindow.kt` (`:89-94`, `:160-170`, `:175-187`, `:283`) and
/// `ui/BlacklistWindow.kt` (`:48`) of v1.1.1; `favLabel` and `fmtAdded` measured on the JVM (`spots-core-probe.tsv`).
@Suite struct ClusterTextsTests {

    static func favorite(_ name: String, _ host: String) -> DxClusterFavorite {
        var favorite = DxClusterFavorite()
        favorite.name = name
        favorite.host = host
        return favorite
    }

    @Test func fmtAddedMatchesTheJvm() {
        let rows = SpotsCoreProbeTable.area("fmtAdded")
        #expect(rows.count == 10)
        for row in rows {
            let input = String(row.input.dropFirst().dropLast())
            #expect("[" + ClusterTexts.fmtAdded(input) + "]" == row.result, "\(row.input)")
        }
    }

    /// The Java getters turn `null` into `""`, so the probe's `[null]` row is the empty favourite.
    @Test func favLabelMatchesTheJvm() throws {
        let rows = SpotsCoreProbeTable.area("favLabel")
        #expect(rows.count == 7)
        let pattern = try Regex("^\\[(.*)\\] \\[(.*)\\]$")
        for row in rows {
            let match = try #require(row.input.wholeMatch(of: pattern))
            var name = String(try #require(match.output[1].substring))
            var host = String(try #require(match.output[2].substring))
            if name == "null" { name = "" }
            if host == "null" { host = "" }
            let label = ClusterTexts.favLabel(Self.favorite(name, host), translator: .source)
            #expect("[" + label + "]" == row.result, "\(row.input)")
        }
    }

    @Test func favLabelIsTranslatedOnlyForTheNoNameText() {
        let english = SpotActionsTests.translator(["— bez názvu —": "— unnamed —"])
        #expect(ClusterTexts.favLabel(Self.favorite("", ""), translator: english) == "— unnamed —")
        #expect(ClusterTexts.favLabel(Self.favorite("", "dx.example"), translator: english) == "dx.example")
    }

    /// `DW:90-94`: `lastFavorite`, else the first name; the selection by label or name, else the first.
    @Test func favoriteSelection() {
        let first = Self.favorite("", "first.example")
        let second = Self.favorite("Second", "second.example")
        let favorites = [first, second]
        #expect(ClusterTexts.initialSelection(lastFavorite: "", favorites: favorites) == "")
        #expect(ClusterTexts.initialSelection(lastFavorite: " ", favorites: [second]) == "Second")
        #expect(ClusterTexts.initialSelection(lastFavorite: "X", favorites: favorites) == "X")
        #expect(ClusterTexts.selectedFavorite("Second", favorites: favorites, translator: .source) == second)
        #expect(ClusterTexts.selectedFavorite("first.example", favorites: favorites, translator: .source) == first)
        // The first favourite has an empty name, so an empty selection matches it by name.
        #expect(ClusterTexts.selectedFavorite("", favorites: favorites, translator: .source) == first)
        #expect(ClusterTexts.selectedFavorite("gone", favorites: [second, first], translator: .source) == second)
        #expect(ClusterTexts.selectedFavorite("gone", favorites: [], translator: .source) == nil)
    }

    /// `DW:161-169`: name (`ifBlank { null }`) or status, then ✓ / … / ✗, joined by `" · "`.
    @Test func parallelSummary() {
        var rbn = DxClusterSession.Snapshot()
        rbn.currentFavorite = Self.favorite("RBN", "rbn.example")
        rbn.connected = true
        rbn.loggedIn = true
        var skimmer = DxClusterSession.Snapshot()
        skimmer.currentFavorite = Self.favorite(" ", "skim.example")
        skimmer.connected = true
        skimmer.status = "Připojeno k skim.example"
        var dropped = DxClusterSession.Snapshot()
        dropped.status = "Odpojeno"
        #expect(ClusterTexts.parallelItem(rbn) == "RBN ✓")
        #expect(ClusterTexts.parallelItem(skimmer) == "Připojeno k skim.example …")
        #expect(ClusterTexts.parallelItem(dropped) == "Odpojeno ✗")
        #expect(ClusterTexts.parallelSummary([]) == nil)
        #expect(ClusterTexts.parallelSummary([rbn, skimmer, dropped])?.czech
            == "Souběžně: RBN ✓ · Připojeno k skim.example … · Odpojeno ✗")
    }

    /// `DW:186`: label, else command, else `tr("(prázdné)")`; the edit dialog trims both (`DW:266`).
    @Test func macroLabels() {
        #expect(ClusterTexts.macroLabel(DxClusterCommand(label: "SH/DX", command: "sh/dx 30"), translator: .source)
            == "SH/DX")
        #expect(ClusterTexts.macroLabel(DxClusterCommand(label: " ", command: "sh/dx 30"), translator: .source)
            == "sh/dx 30")
        #expect(ClusterTexts.macroLabel(DxClusterCommand(label: "", command: "\u{00A0}"), translator: .source)
            == "(prázdné)")
        let english = SpotActionsTests.translator(["(prázdné)": "(empty)"])
        #expect(ClusterTexts.macroLabel(DxClusterCommand(), translator: english) == "(empty)")
        #expect(ClusterTexts.editedMacro(label: " Spots ", command: "\u{00A0}sh/dx\u{00A0}")
            == DxClusterCommand(label: "Spots", command: "sh/dx"))
        #expect(ClusterTexts.macroSaveFailed("disk full").czech == "Uložení tlačítka selhalo (disk full)")
        #expect(ClusterTexts.macroSaveFailed(nil).czech == "Uložení tlačítka selhalo (null)")
    }
}
