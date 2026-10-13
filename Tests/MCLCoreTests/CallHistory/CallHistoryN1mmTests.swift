import Foundation
import Testing
@testable import MCLCore

/// The N1MM+ call history features beyond Java v1.1.1: directives, the `;` delimiter, merging files, the Loc1/Loc2
/// alternate grid and the `#CONTEST` association.
@Suite struct CallHistoryN1mmTests {

    // MARK: - delimiter and directives

    @Test func semicolonOrderLineMakesSemicolonTheDelimiter() {
        let ch = CallHistory.parse(["!!Order!!;Call;Name;State", "W1AW;Hiram;CT", "K1AB;Bob;MA"])
        #expect(ch.columns == ["call", "name", "state"])
        #expect(ch.lookup("W1AW")?["state"] == "CT")
        #expect(ch.lookup("K1AB")?["name"] == "Bob")
    }

    @Test func commaFilesStillSplitOnCommasOnly() {
        let ch = CallHistory.parse(["!!Order!!,Call,Name", "W1AW,Hi;ram"])
        #expect(ch.lookup("W1AW")?["name"] == "Hi;ram")
    }

    @Test func directiveLinesAreNotRecordsAndSetTheOptions() {
        let ch = CallHistory.parse([
            "!!MapStateToSect!!;!!FourCharGridSq!!", "!!NoAppendUserText!!, !!NoLoc2AltGrid!!",
            "!!Order!!,Call,State,Sect,Loc1", "W1AW,CT,,FN31PR",
        ])
        #expect(ch.size == 1)
        #expect(ch.options.mapStateToSect && ch.options.fourCharGrid)
        #expect(!ch.options.appendUserText && !ch.options.loc2AltGrid)
        #expect(ch.options.directives == ["MapStateToSect", "FourCharGridSq", "NoAppendUserText", "NoLoc2AltGrid"])
        #expect(ch.lookup("W1AW")?["sect"] == "CT")
        #expect(ch.lookup("W1AW")?["loc1"] == "FN31")
    }

    @Test func validate50StateDropsOtherStates() {
        let ch = CallHistory.parse(["!!Validate50State!!", "!!Order!!,Call,State", "W1AW,CT", "VE3XX,ON", "K3DC,DC"])
        #expect(ch.lookup("W1AW")?["state"] == "CT")
        #expect(ch.lookup("VE3XX")?["state"] == nil)
        #expect(ch.lookup("K3DC")?["state"] == nil, "DC is not one of the 50 states")
    }

    @Test func mapOnSectionAndValidateArrlSection() {
        let mapped = CallHistory.parse(["!!MapOnSection!!", "!!Order!!,Call,Sect", "VE3A,ONN", "VE3B,GTE", "W1AW,CT"])
        #expect(mapped.lookup("VE3A")?["sect"] == "ON")
        #expect(mapped.lookup("VE3B")?["sect"] == "ON")
        #expect(mapped.lookup("W1AW")?["sect"] == "CT")
        let validated = CallHistory.parse(["!!ValidateArrlSection!!", "!!Order!!,Call,Sect",
                                           "VE3A,ON", "KP4A,PR", "W1AW,EMA", "X1X,XYZ"])
        #expect(validated.lookup("VE3A")?["sect"] == nil, "ON is not an ARRL section")
        #expect(validated.lookup("KP4A")?["sect"] == "PR")
        #expect(validated.lookup("W1AW")?["sect"] == "EMA")
        #expect(validated.lookup("X1X")?["sect"] == nil)
    }

    @Test func plainFileRepeatedCallReplacesTheRecordLikeJava() {
        let ch = CallHistory.parse(["!!Order!!,Call,Name,Loc1,UserText", "W1AW,Hiram,FN31,a", "W1AW,,FN42,b"])
        #expect(ch.lookup("W1AW")?["name"] == nil)
        #expect(ch.lookup("W1AW")?["loc1"] == "FN42")
        #expect(ch.lookup("W1AW")?["loc2"] == nil)
        #expect(ch.lookup("W1AW")?["usertext"] == "b")
    }

    @Test func fileWithDirectivesOverlaysRepeatedCalls() {
        let ch = CallHistory.parse(["!!AppendUserText!!", "!!Order!!,Call,Name,Loc1,UserText",
                                    "W1AW,Hiram,FN31,first", "W1AW,,FN42,second"])
        let record = ch.lookup("W1AW")
        #expect(record?["name"] == "Hiram", "an empty field does not overwrite")
        #expect(record?["loc1"] == "FN42")
        #expect(record?["loc2"] == "FN31", "the alternate grid")
        #expect(record?["usertext"] == "first second")
        #expect(ch.columns.contains("loc2"))
    }

    @Test func noAppendAndNoLoc2AltGridReplace() {
        let ch = CallHistory.parse(["!!NoAppendUserText!!,!!NoLoc2AltGrid!!", "!!Order!!,Call,Loc1,UserText",
                                    "W1AW,FN31,first", "W1AW,FN42,second"])
        #expect(ch.lookup("W1AW")?["usertext"] == "second")
        #expect(ch.lookup("W1AW")?["loc1"] == "FN42")
        #expect(ch.lookup("W1AW")?["loc2"] == nil)
    }

    @Test func savedFileKeepsCommentsAndDirectives() {
        let ch = CallHistory.parse(["# CQWWCW", "!!MapStateToSect!!", "!!Order!!,Call,State", "W1AW,CT"])
        #expect(ch.toLines() == [CallHistory.savedHeader, "!!Order!!,Call,State,Sect", "W1AW,CT,CT"],
                "Java's lines by default")
        let lines = ch.toLines(keepingFileLines: true)
        #expect(lines[0] == CallHistory.savedHeader)
        #expect(lines[1] == "# CQWWCW")
        #expect(lines[2] == "!!MapStateToSect!!")
        let again = CallHistory.parse(lines)
        #expect(again.contestTags == ["CQWWCW"])
        #expect(again.options.mapStateToSect)
        // A saved file read and saved again does not repeat its own header.
        #expect(again.toLines(keepingFileLines: true) == lines)
    }

    // MARK: - merging

    @Test func mergingOverlaysFieldsAndAppendsUserText() {
        let first = CallHistory.parse(["!!Order!!,Call,Name,Loc1,UserText", "W1AW,Hiram,FN31,club", "K1AB,Bob,,"])
        let second = CallHistory.parse(["!!Order!!,Call,Loc1,CQZone,UserText", "W1AW,FN42,5,dxer", "N1XX,FN20,5,"])
        let merged = first.merging(second)
        #expect(merged.size == 3)
        #expect(merged.columns == ["call", "name", "loc1", "usertext", "cqzone", "loc2"])
        let w1aw = merged.lookup("W1AW")
        #expect(w1aw?["name"] == "Hiram")
        #expect(w1aw?["loc1"] == "FN42")
        #expect(w1aw?["loc2"] == "FN31")
        #expect(w1aw?["cqzone"] == "5")
        #expect(w1aw?["usertext"] == "club dxer")
        #expect(merged.lookup("N1XX")?["loc1"] == "FN20")
    }

    @Test func mergingWithNoAppendReplacesUserText() {
        let first = CallHistory.parse(["!!Order!!,Call,UserText", "W1AW,club"])
        let second = CallHistory.parse(["!!NoAppendUserText!!", "!!Order!!,Call,UserText", "W1AW,dxer"])
        #expect(first.merging(second).lookup("W1AW")?["usertext"] == "dxer")
    }

    @Test func loadMergesTheExtraFiles() throws {
        try CallHistoryTestSupport.withTemporaryDirectory { dir in
            let primary = dir + "/a.txt"
            let extra = dir + "/b.txt"
            try "!!Order!!,Call,Name\nW1AW,Hiram\n".write(toFile: primary, atomically: true, encoding: .utf8)
            try "!!Order!!;Call;State\nW1AW;CT\nK1AB;MA\n".write(toFile: extra, atomically: true, encoding: .utf8)
            let ch = CallHistory.load(primary: primary, extras: [extra, dir + "/missing.txt"])
            #expect(ch.size == 2)
            #expect(ch.lookup("W1AW")?["name"] == "Hiram")
            #expect(ch.lookup("W1AW")?["state"] == "CT")
        }
    }

    // MARK: - grid rotation (update from the log)

    @Test func updateMovesADifferentGridToLoc2() {
        let ch = CallHistory.parse(["!!Order!!,Call,Loc1,Loc2", "W1AW,FN31,FN20"])
        let java = ch.withUpdates(JavaLinkedMap([("W1AW", JavaLinkedMap([("loc1", "FN42")]))]))
        #expect(java.lookup("W1AW")?["loc2"] == "FN20", "Java's update overwrites Loc1 only")
        let updated = ch.withUpdates(JavaLinkedMap([("W1AW", JavaLinkedMap([("loc1", "FN42")]))]), rotatingGrids: true)
        #expect(updated.lookup("W1AW")?["loc1"] == "FN42")
        #expect(updated.lookup("W1AW")?["loc2"] == "FN31", "the oldest grid is dropped")
    }

    @Test func updateUpgradesAFourCharacterGridInPlace() {
        let ch = CallHistory.parse(["!!Order!!,Call,Loc1,Loc2", "W1AW,FN31,FN20"])
        let longer = ch.withUpdates(JavaLinkedMap([("W1AW", JavaLinkedMap([("loc1", "FN31PR")]))]), rotatingGrids: true)
        #expect(longer.lookup("W1AW")?["loc1"] == "FN31PR")
        #expect(longer.lookup("W1AW")?["loc2"] == "FN20")
        let shorter = longer.withUpdates(JavaLinkedMap([("W1AW", JavaLinkedMap([("loc1", "fn31")]))]), rotatingGrids: true)
        #expect(shorter.lookup("W1AW")?["loc1"] == "FN31PR", "a 4-character grid does not replace its 6-character one")
    }

    @Test func updateAddsLoc2ColumnAndHonoursNoLoc2AltGrid() {
        let plain = CallHistory.parse(["!!Order!!,Call,Loc1", "W1AW,FN31"])
        let rotated = plain.withUpdates(JavaLinkedMap([("W1AW", JavaLinkedMap([("loc1", "FN42")]))]), rotatingGrids: true)
        #expect(rotated.columns == ["call", "loc1", "loc2"])
        #expect(rotated.lookup("W1AW")?["loc2"] == "FN31")
        let off = CallHistory.parse(["!!NoLoc2AltGrid!!", "!!Order!!,Call,Loc1", "W1AW,FN31"])
        let replaced = off.withUpdates(JavaLinkedMap([("W1AW", JavaLinkedMap([("loc1", "FN42")]))]), rotatingGrids: true)
        #expect(replaced.lookup("W1AW")?["loc1"] == "FN42")
        #expect(replaced.lookup("W1AW")?["loc2"] == nil)
    }

    // MARK: - #CONTEST

    @Test func contestTagsAreNormalisedComments() {
        let ch = CallHistory.parse(["#NAQPCW", "# naqpssb", "# QSO Party PA", "#cq-ww-cw", "#", "!!Order!!,Call"])
        #expect(ch.contestTags == ["NAQPCW", "NAQPSSB", "QSOPARTYPA", "CQWWCW"])
        #expect(CallHistory.contestKey("CQ WW DX Contest — CW") == "CQWWDXCONTESTCW")
    }

    @Test func lookupDecisionFollowsTheKnownContests() {
        let known: Set<String> = ["CQWWCW", "CQWWSSB", "IARUHF"]
        #expect(CallHistory.lookupDecision(tags: ["CQWWCW", "MYNOTES"], contest: ["CQWWCW"], known: known) == true)
        #expect(CallHistory.lookupDecision(tags: ["CQWWSSB"], contest: ["CQWWCW"], known: known) == false)
        #expect(CallHistory.lookupDecision(tags: ["MYNOTES"], contest: ["CQWWCW"], known: known) == nil,
                "no known contest named: the switch is left alone")
        #expect(CallHistory.lookupDecision(tags: [], contest: ["CQWWCW"], known: known) == nil)
    }
}

/// A contest's own call history file (N1MM Associated Files) in its setup and the New contest form.
@Suite struct ContestCallHistoryFileTests {

    @Test func anEmptyFileIsNotWrittenAndASetOneRoundTrips() throws {
        let empty = String(decoding: try JSONEncoder().encode(ContestSetup()), as: UTF8.self)
        #expect(!empty.contains("callHistoryFile"))
        var setup = ContestSetup()
        setup.callHistoryFile = "/data/naqp.txt"
        let data = try JSONEncoder().encode(setup)
        #expect(String(decoding: data, as: UTF8.self).contains("callHistoryFile"))
        #expect(try JSONDecoder().decode(ContestSetup.self, from: data) == setup)
        #expect(try JSONDecoder().decode(ContestSetup.self, from: Data("{}".utf8)).callHistoryFile == "")
    }

    @Test func theNewContestFormPrefillsAndSavesTheFile() throws {
        let definition: ContestDefinition = try NewContestFormTests.definition("cq-ww-cw")
        var saved = ContestSetup()
        saved.callHistoryFile = "/data/x.txt"
        var form = NewContestForm.prefill(definition: definition, saved: saved, stationCall: "OK1XOE", now: Date())
        #expect(form.callHistoryFile == "/data/x.txt")
        form.callHistoryFile = "  /data/y.txt "
        #expect(form.setup().callHistoryFile == "/data/y.txt")
        #expect(NewContestForm.prefill(definition: definition, saved: nil, stationCall: "", now: Date())
            .callHistoryFile == "")
    }
}
