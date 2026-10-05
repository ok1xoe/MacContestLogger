import Testing
@testable import MCLCore

/// Port of the Java `goals/GoalFileWriterTest` (6 tests).
@Suite struct GoalFileWriterTests {

    @Test func exportedFileReadsBackAsTheSameSet() {
        let original = GoalSet.of([GoalSet.key(1, 21): 80, GoalSet.key(2, 5): 30])

        let lines: [String] = GoalFileWriter.format(original)
        let back = GoalFileParser.parse(lines, nil)

        #expect(original.entries == back.goals.entries)
        #expect(back.ignoredLines.isEmpty, "our own export must pass our own parser")
    }

    @Test func exportCarriesTheN1mmHeaderAndSortedKeys() {
        let lines: [String] = GoalFileWriter.format(GoalSet.of([205: 30, 121: 80, 122: 60]))

        #expect(lines.first == "Type=GOAL  SubType=")
        #expect(lines.dropFirst().map(JavaText.trim) == ["121 80", "122 60", "205 30"])
    }

    @Test func emptySetExportsJustTheHeader() {
        #expect(GoalFileWriter.format(GoalSet.empty()) == ["Type=GOAL  SubType="])
    }

    @Test func configRoundTripKeepsTheSet() {
        let original = GoalSet.of([121: 80, 205: 30])

        let stored: [String: Int] = GoalFileWriter.toConfigMap(original)

        #expect(stored == ["121": 80, "205": 30])
        #expect(original.entries == GoalFileWriter.fromConfigMap(stored).entries)
    }

    @Test func corruptedConfigKeyIsSkippedRatherThanCrashing() {
        // A hand-edited config.json must not bring the application down.
        let back = GoalFileWriter.fromConfigMap(["121": 80, "nesmysl": 10])

        #expect(back.entries == [121: 80])
    }

    @Test func missingConfigMapGivesEmptySet() {
        #expect(GoalFileWriter.fromConfigMap(nil).isEmpty)
        #expect(GoalFileWriter.fromConfigMap([:]).isEmpty)
    }
}
