import Testing
@testable import MCLCore

/// N1MM Score window „Copy all" / „Print to file": the setup and station lines and the aligned table.
@Suite struct ScoreSummaryTextTests {

    @Test func setupLinesLeaveOutEmptyValues() {
        var setup = ContestSetup()
        setup.category = ["POWER": "HIGH", "OPERATOR": "MULTI-OP", "BAND": " "]
        setup.operators = "OK1XOE OK1ABC"
        setup.startedAt = "2026-11-28 00:00"
        var station = StationConfig()
        station.gridSquare = "JN79"
        station.cqZone = "15"
        station.ituZone = "28"
        #expect(ScoreSummaryText.setupLines(setup: setup, station: station) == [
            "Kategorie:     OPERATOR MULTI-OP · POWER HIGH",
            "Operátoři:     OK1XOE OK1ABC",
            "Začátek:       2026-11-28 00:00 UTC",
            "Lokátor:       JN79",
            "Zóny:          CQ 15 · ITU 28",
        ])
        #expect(ScoreSummaryText.setupLines(setup: nil, station: StationConfig()).isEmpty)
    }

    @Test func theTableIsAligned() {
        let table = ScoreTable(headers: ["Pásmo", "QSO", "Body"], lead: 1, rows: [["20m", "5", "15"], ["40m", "12", "3"]],
                               total: ["Celkem", "17", "18"], modesTitle: nil, modeRows: [],
                               footer: "Body 18 × násobiče 2  =  skóre 36", skippedNote: nil)
        #expect(ScoreSummaryText.tableText(table) == """
            Pásmo   QSO  Body
            -----------------
            20m       5    15
            40m      12     3
            -----------------
            Celkem   17    18

            Body 18 × násobiče 2  =  skóre 36

            """)
    }
}
