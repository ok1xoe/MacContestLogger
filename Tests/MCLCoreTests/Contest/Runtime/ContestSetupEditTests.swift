import Foundation
import Testing
@testable import MCLCore

/// The contest setup of an open log (File → Contest setup), N1MM „Populate all from last log", „Update Ops from
/// Log", deleting a contest and the exchange abbreviations.
@Suite struct ContestSetupEditTests {

    private static func definition() throws -> ContestDefinition {
        try SessionFixture.definition("@cq-ww-cw.yaml")
    }

    @Test func editingKeepsTheStoredValuesAndTheExtras() throws {
        var stored = ContestSetup()
        stored.category = ["OPERATOR": "MULTI-OP", "POWER": "HIGH"]
        stored.sentExchange = [:]
        stored.operators = "OK1XOE OK1ABC"
        stored.tour = "1200/30"
        stored.bonusStations = ["W1AW"]
        stored.firstSerial = 50
        stored.scpFile = "/tmp/x.scp"
        stored.goalFile = "/tmp/goals.txt"
        var form = NewContestForm.editing(definition: try Self.definition(), setup: stored)
        #expect(form.category["POWER"] == "HIGH")
        #expect(form.sentExchange["zone"] == "")
        #expect(form.firstSerial == 50)
        form.soapbox = "Nice"
        form.firstSerial = 0
        let out = form.applied(to: stored)
        #expect(out.soapbox == "Nice")
        #expect(out.tour == "1200/30")
        #expect(out.bonusStations == ["W1AW"])
        #expect(out.firstSerial == 1)
        #expect(out.scpFile == "/tmp/x.scp")
        #expect(out.goalFile == "/tmp/goals.txt")
    }

    @Test func populateFromTheLastLog() {
        var last = ContestSetup()
        last.category = ["OPERATOR": "SINGLE-OP", "POWER": "QRP", "MODE": "RTTY", "BAND": "20M"]
        last.operators = "OK1XOE"
        var form = NewContestForm(category: ["MODE": "CW", "BAND": "ALL", "POWER": "LOW"])
        form.populate(from: last, bandOptions: ["ALL", "20M"], modeOptions: ["CW"])
        #expect(form.category["POWER"] == "QRP")
        #expect(form.category["MODE"] == "CW", "a mode the contest does not offer stays")
        #expect(form.category["BAND"] == "20M")
        #expect(form.operators == "OK1XOE")
    }

    @Test func operatorsFromTheLog() {
        #expect(NewContestForm.operators(fromLog: ["ok1xoe", "", "OK1ABC", "OK1XOE ", "OK2XYZ"])
            == "OK1XOE OK1ABC OK2XYZ")
        #expect(NewContestForm.operators(fromLog: [" "]) == "")
    }

    @Test func abbreviations() {
        let table = ExchangeAbbreviations.parse("""
            # comment
            ALA=AL
            ont, on
            QUE\tQC   # inline comment
            BAD
            AL=AL
            """)
        #expect(table.table == ["ALA": "AL", "ONT": "ON", "QUE": "QC"])
        let fields: [ContestDefinition.ExchangeField] = [
            ContestDefinition.ExchangeField(id: "rst", type: .RST, required: true, source: nil, appliesWhen: nil,
                                            validation: nil),
            ContestDefinition.ExchangeField(id: "state", type: .STATE, required: true, source: nil, appliesWhen: nil,
                                            validation: nil),
        ]
        let out = table.apply(JavaLinkedMap([("rst", "599"), ("state", "ala")]), fields: fields)
        #expect(out["state"] == "AL")
        #expect(out["rst"] == "599")
    }

    @Test func abbreviationsFileIsReadAgainWhenItChanges() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-abbr-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(ExchangeAbbreviations.load(dataDir: dir).table.isEmpty)
        let file = dir.appendingPathComponent(ExchangeAbbreviations.fileName)
        try Data("ALA=AL\n".utf8).write(to: file)
        #expect(ExchangeAbbreviations.load(dataDir: dir).table == ["ALA": "AL"])
        try Data("ONT=ON\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: file.path)
        #expect(ExchangeAbbreviations.load(dataDir: dir).table == ["ONT": "ON"])
    }

    @Test func deletingAContestRemovesItsQsosAndQtcs() throws {
        let repository = try LogbookRepository.inMemory()
        defer { repository.close() }
        let store = try ContestStore(repository)
        for id in ["c1", "c2"] {
            try store.insert(ContestStore.ContestRow(contestId: id, definitionId: "d", name: id, startedAt: 0,
                                                     endedAt: nil, definitionYaml: "id: d", setupJson: nil,
                                                     stationJson: nil))
            var qso = Qso()
            qso.timestampUtc = Date(timeIntervalSince1970: 1_795_867_200)
            qso.call = "DL1ABC"
            qso.freqHz = 14_025_000
            qso.mode = .cw
            qso.contestId = id
            try repository.insert(&qso)
        }
        #expect(try store.delete(contestId: "c1") == 1)
        #expect(try store.find("c1") == nil)
        #expect(try repository.count(contestId: "c1") == 0)
        #expect(try repository.count(contestId: "c2") == 1)
        #expect(try store.delete(contestId: "c1") == nil)
    }
}
