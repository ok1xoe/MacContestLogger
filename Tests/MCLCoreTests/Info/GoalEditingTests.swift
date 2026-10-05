import Testing
@testable import MCLCore

/// `GoalEditing` against `ui/GoalWindows.kt` and `ui/RateWindow.kt:539-552` of v1.1.1: `hourLabel` is the real
/// private Kotlin function measured on the JVM; the draft, bulk fill and the status texts are transcribed over the
/// real `GoalSet`/`GoalFileParser` (maintainer-only probe).
@Suite struct GoalEditingTests {

    @Test func hourLabelMatchesTheJvm() throws {
        let rows = InfoProbeTable.area("hourLabel")
        #expect(rows.count == 20)
        for row in rows {
            #expect(GoalEditing.hourLabel(try #require(Int32(row.input))) == row.result, "\(row.input)")
        }
    }

    static func keyText(_ keys: [Int32]) -> String {
        keys.map { String($0) }.joined(separator: ",")
    }

    @Test func editorHoursMatchTheJvm() throws {
        let rows = InfoProbeTable.area("hours")
        #expect(rows.count == 33)
        for row in rows {
            let f = row.input.split(separator: "|").map(String.init)
            let start: JavaInstant? = f[0] == "~" ? nil : JavaInstant.ofEpochSecond(Int64(f[0])!)
            let keys = try GoalSet.hoursOf(start, Int32(try #require(Int(f[1]))))
            #expect(Self.keyText(keys) == row.result, "\(row.input)")
        }
    }

    @Test func hoursUseTheDefinitionLength() throws {
        // GW:68-71: the definition's period, else 48 hours.
        let start = InfoProbeTable.contestStart
        let none = try GoalEditing.hours(contestStart: start, definition: nil)
        #expect(none.count == 48)
        #expect(try GoalEditing.hours(contestStart: nil, definition: nil).isEmpty)
        #expect(none.first == 109)
        // 09:30Z start: the first hour is 09:00 of day 1, the 16th is 00:00 of day 2.
        #expect(none[14] == 123)
        #expect(none[15] == 200)
    }

    @Test func draftFromSavedGoalsMatchesTheJvm() throws {
        let row = InfoProbeTable.area("draft")[0]
        // Input: `hours=<keys> saved=<TreeMap>`; result `key=text,…`.
        let hours = try GoalSet.hoursOf(InfoProbeTable.contestStart, 6)
        let draft = GoalEditing.Draft(goalSet: GoalSet.of([109: 10, 111: 0, 113: 25, 999: 7]), hours: hours)
        #expect(row.input == "hours=" + Self.keyText(hours) + " saved={109=10, 111=0, 113=25, 999=7}")
        let text = hours.map { String($0) + "=" + draft.text(for: $0) }.joined(separator: ",")
        #expect(text == row.result)
        // The saved hour outside the contest (999) is dropped by the next save.
        #expect(draft.goalSet().entries[999] == nil)
    }

    @Test func digitFilterMatchesTheJvm() {
        let rows = InfoProbeTable.area("filter")
        #expect(rows.count == 16)
        for row in rows {
            #expect("[" + GoalEditing.digitsOnly(row.input) + "]" == row.result, "\(row.input)")
        }
    }

    /// The probe's hand-made drafts: raw texts as in the Kotlin `draft` map, bypassing the field filter.
    @Test func saveMatchesTheJvm() throws {
        let rows = InfoProbeTable.area("save")
        #expect(rows.count == 4)
        for row in rows {
            var texts: [Int32: String] = [:]
            for item in row.input.split(separator: ",", omittingEmptySubsequences: false) {
                let eq = try #require(item.firstIndex(of: "="))
                texts[Int32(item[..<eq])!] = String(item[item.index(after: eq)...])
            }
            let draft = GoalEditing.Draft(hours: texts.keys.sorted(), texts: texts)
            let set = draft.goalSet()
            let config = GoalFileWriter.toConfigMap(set)
            let ordered = config.keys.sorted { JavaText.compare($0, $1) < 0 }
            let configText = "{" + ordered.map { $0 + "=" + String(config[$0]!) }.joined(separator: ", ") + "}"
            let text = "count=" + String(set.entries.count) + ";config=" + configText + ";status="
                + GoalEditing.savedText(hours: draft.goalCount())
            #expect(text == row.result, "\(row.input)")
        }
    }

    @Test func bulkFillMatchesTheJvm() throws {
        let rows = InfoProbeTable.area("bulk")
        #expect(rows.count == 24)
        for row in rows {
            let f = row.input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let hours: [Int32] = f[0].split(separator: ",").map { Int32($0)! }
            var texts: [Int32: String] = [:]
            for h in hours { texts[h] = "x" + String(h) }
            var draft = GoalEditing.Draft(hours: hours, texts: texts)
            var bulk = GoalEditing.BulkFill(hours: hours)
            bulk.fromKey = try #require(Int32(f[1]))
            bulk.toKey = try #require(Int32(f[2]))
            bulk.setValue(f[3])
            bulk.apply(to: &draft)
            let text = draft.hours.map { String($0) + "=" + draft.text(for: $0) }.joined(separator: ",")
            #expect(text == row.result, "\(row.input)")
        }
    }

    @Test func clearAllEmptiesEveryField() {
        var draft = GoalEditing.Draft(goalSet: GoalSet.of([109: 10, 110: 20]), hours: [109, 110])
        draft.clearAll()
        #expect(draft.goalSet().isEmpty)
        // GW:130: a field edit keeps only digits.
        draft.setText("1a2", for: 109)
        #expect(draft.text(for: 109) == "12")
        #expect(GoalEditing.BulkFill(hours: []).fromKey == 0)
    }

    @Test func importStatusMatchesTheJvm() {
        let rows = InfoProbeTable.area("import")
        #expect(rows.count == 15)
        for row in rows {
            let f = row.input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            // `f[0]` is the lines joined by a backslash and `n`; an empty text is no lines.
            let lines: [String] = f[0].isEmpty ? [] : f[0].components(separatedBy: "\\n")
            let band: String? = f[1] == "~" ? nil : f[1]
            let result = GoalFileParser.parse(lines, band)
            let bands = InfoProbeTable.listText(result.bands)
            #expect("bands=" + bands == f[2], "\(row.input)")
            #expect(GoalEditing.importStatus(result, band: band) == row.result, "\(row.input)")
        }
    }

    @Test func fixedTextsMatchTheJvm() {
        let rows = InfoProbeTable.area("importMsg")
        #expect(rows.count == 8)
        let expected: [String: String] = [
            "read": "Cíle se nepodařilo přečíst (x)",
            "saveFail": GoalEditing.saveFailedText("x"),
            "noExport": "Není co exportovat — žádné cíle nejsou načtené.",
            "exported": "Cíle uloženy do /tmp/goals.txt",
            "exportFail": "Export cílů selhal (x)",
            "help1": GoalEditing.helpText(),
            "help2": GoalEditing.noContestText(),
            "fromLogHelp": GoalEditing.fromLogHelpText(),
        ]
        for row in rows {
            #expect(expected[row.input] == row.result, "\(row.input)")
        }
    }

    @Test func fromLogStatusMatchesTheJvm() {
        let rows = InfoProbeTable.area("fromlog")
        #expect(rows.count == 3)
        for row in rows {
            let f = row.input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let band: Band? = f[2] == "~" ? nil : Band.from(adif: f[2])
            #expect(GoalEditing.fromLogStatus(contestName: f[0], hours: Int(f[1])!, band: band) == row.result,
                    "\(row.input)")
        }
        for row in InfoProbeTable.area("bandlabel") {
            let band: Band? = row.input == "~" ? nil : Band.from(adif: row.input)
            #expect(GoalEditing.bandLabel(band) == row.result)
        }
    }

    @Test func translatedStatus() {
        let english = SpotActionsTests.translator([
            "Načteno %s cílů": "Loaded %s goals", "(pásmo %s)": "(band %s)",
            "; %s řádků nerozpoznáno: %s": "; %s lines not recognized: %s",
        ])
        let result = GoalFileParser.parse(["Type=GOAL  SubType=", "101 20", "junk"], nil)
        #expect(GoalEditing.importStatus(result, band: "80m", translate: english)
            == "Loaded 1 goals (band 80m); 1 lines not recognized: junk")
    }
}
