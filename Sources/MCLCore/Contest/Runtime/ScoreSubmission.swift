import Foundation

/// The result of a contest as the form of 3830scores.com asks for it (N1MM „Report Score to 3830"): the lines to copy
/// into the site's score form. The site has one form per contest, with an opaque address and no documented way to prefill
/// it and no API, so nothing is posted from here: the logger shows these lines, copies them and opens the site.
public struct ScoreSubmission: Equatable, Sendable {

    /// Where the contests' score forms are listed (left navigation).
    public static let siteUrl = "https://www.3830scores.com/"

    public struct Line: Equatable, Sendable {
        public let label: String
        public let value: String
    }

    public let lines: [Line]

    /// - Parameters:
    ///   - category: the contest setup's category (`OPERATOR`, `BAND`, `POWER`…), shown sorted by name.
    ///   - score: the claimed score of the whole log; `nil` = not known (no contest).
    ///   - label: translates a label (the lines' labels are texts of the UI).
    public init(call: String, contestName: String, category: [String: String], operators: String, grid: String,
                score: ScoreState?, soapbox: String, label: (String) -> String = { $0 }) {
        var out: [Line] = []
        func add(_ key: String, _ value: String) {
            out.append(Line(label: label(key), value: value))
        }
        add("Volačka", call)
        add("Závod", contestName)
        let categoryText: String = category.sorted { $0.key < $1.key }
            .filter { !$0.value.isEmpty }.map { $0.key + ": " + $0.value }.joined(separator: ", ")
        if !categoryText.isEmpty {
            add("Kategorie", categoryText)
        }
        if !operators.trimmingCharacters(in: .whitespaces).isEmpty {
            add("Operátoři", operators)
        }
        if !grid.isEmpty {
            add("Lokátor", grid)
        }
        if let score {
            add("QSO", String(score.qsoCount))
            add("Body za QSO", String(score.qsoPoints))
            add("Násobiče", String(score.multTotal))
            for (key, value) in score.multByGroup.entries {
                guard let key, let value, score.multByGroup.count > 1 else { continue }
                add("  " + key, String(value))
            }
            if score.bonusPoints != 0 {
                add("Bonus", String(score.bonusPoints))
            }
            if score.qtcPoints != 0 {
                add("Body za QTC", String(score.qtcPoints))
            }
            add("Celkové skóre", String(score.total))
        }
        if !soapbox.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("Soapbox", soapbox)
        }
        lines = out
    }

    /// `Label: value` lines, one per line (the soapbox's own line breaks kept).
    public var text: String {
        lines.map { $0.label + ": " + $0.value }.joined(separator: "\n")
    }
}
