import Testing
@testable import MCLCore

@Suite struct ScoreSubmissionTests {

    private static func state(groups: [(String, Int32)] = []) -> ScoreState {
        var map = JavaLinkedMap<Int32>()
        for (key, value) in groups {
            map.put(key, value)
        }
        return ScoreState(qsoCount: 120, qsoPoints: 300, multTotal: 40, multByGroup: map, bonusPoints: 0,
                          qtcPoints: 0, total: 12_000)
    }

    @Test func theLinesFollowTheScoreForm() {
        let submission = ScoreSubmission(
            call: "OK1XOE", contestName: "CQ WW DX Contest — CW",
            category: ["POWER": "LOW", "OPERATOR": "SINGLE-OP", "BAND": ""], operators: "OK1XOE", grid: "JN79",
            score: Self.state(groups: [("zone", 25), ("country", 15)]), soapbox: "Fun test.\nTNX")
        #expect(submission.lines.map(\.label) == ["Volačka", "Závod", "Kategorie", "Operátoři", "Lokátor", "QSO",
                                                  "Body za QSO", "Násobiče", "  zone", "  country", "Celkové skóre",
                                                  "Soapbox"])
        #expect(submission.text == """
            Volačka: OK1XOE
            Závod: CQ WW DX Contest — CW
            Kategorie: OPERATOR: SINGLE-OP, POWER: LOW
            Operátoři: OK1XOE
            Lokátor: JN79
            QSO: 120
            Body za QSO: 300
            Násobiče: 40
              zone: 25
              country: 15
            Celkové skóre: 12000
            Soapbox: Fun test.
            TNX
            """)
    }

    @Test func emptyPartsAndASingleGroupAreLeftOut() {
        let submission = ScoreSubmission(call: "OK1XOE", contestName: "X", category: [:], operators: "  ", grid: "",
                                         score: Self.state(groups: [("country", 40)]), soapbox: " \n")
        #expect(submission.lines.map(\.label) == ["Volačka", "Závod", "QSO", "Body za QSO", "Násobiče",
                                                  "Celkové skóre"])
    }

    @Test func bonusAndQtcAppearWhenTheyScore() {
        let score = ScoreState(qsoCount: 1, qsoPoints: 2, multTotal: 3, multByGroup: JavaLinkedMap<Int32>(),
                               bonusPoints: 50, qtcPoints: 7, total: 99)
        let submission = ScoreSubmission(call: "A", contestName: "B", category: [:], operators: "", grid: "",
                                         score: score, soapbox: "")
        #expect(submission.lines.map(\.label).contains("Bonus"))
        #expect(submission.lines.map(\.label).contains("Body za QTC"))
    }

    @Test func labelsAreTranslated() {
        let submission = ScoreSubmission(call: "A", contestName: "B", category: [:], operators: "", grid: "",
                                         score: nil, soapbox: "", label: { "[" + $0 + "]" })
        #expect(submission.lines.map(\.label) == ["[Volačka]", "[Závod]"])
        #expect(ScoreSubmission.siteUrl == "https://www.3830scores.com/")
    }
}
