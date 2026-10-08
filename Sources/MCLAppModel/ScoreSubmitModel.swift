import Foundation
import MCLCore
import Observation

/// „Odeslat výsledek na 3830…" (N1MM „Report Score to 3830"): the result of the active contest as the lines of the
/// 3830scores.com form, with an editable soapbox. 3830scores.com has a form per contest with an opaque address, no
/// documented prefill and no API, so **nothing is posted and no credentials are kept**: the window copies the lines
/// and opens the site, where the operator picks the contest's form and pastes.
@Observable @MainActor
public final class ScoreSubmitModel {

    /// The soapbox to post; starts as the contest setup's own (not written back).
    public var soapbox: String

    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let callbook: CallbookModel

    init(contest: ContestModel, config: ConfigModel, language: LanguageModel, callbook: CallbookModel) {
        self.contest = contest
        self.config = config
        self.language = language
        self.callbook = callbook
        soapbox = contest.activeSetup?.soapbox ?? ""
    }

    /// The preview, read live (the score follows the log).
    public var submission: ScoreSubmission {
        let station: StationConfig = config.config.station
        let language: LanguageModel = self.language
        return ScoreSubmission(
            call: station.call, contestName: contest.definition?.metadata?.name ?? "",
            category: contest.activeSetup?.category ?? [:], operators: contest.activeSetup?.operators ?? "",
            grid: station.gridSquare, score: contest.score, soapbox: soapbox, label: { language.tr($0) })
    }

    /// What „Zkopírovat" puts on the pasteboard.
    public var text: String {
        submission.text
    }

    public var hasContest: Bool {
        contest.isActive
    }

    /// Opens 3830scores.com in the browser (the URL port: inert under `MCL_INERT_NETWORK`).
    public func openSite() {
        callbook.openUrl(ScoreSubmission.siteUrl)
    }
}
