import Foundation
import MCLCore
import Observation

/// The „Zkopírovat závod do jiné databáze" window: one contest of the open database (or all of them) with its QSOs
/// copied into another existing database or a new one. The open database is only read (`ContestCopier`).
@Observable @MainActor
public final class CopyContestModel {

    /// The contests of the open database; `nil` while they are read.
    public private(set) var contests: [ContestBrowserRow]?
    /// The databases a copy can go to: every one but the open one; `nil` while they are read.
    public private(set) var databases: [String]?
    /// The contest to copy; `nil` = all contests (and the free-logging QSOs).
    public var selectedContest: String?
    /// The existing database chosen as the target.
    public var targetExisting: String = ""
    /// The name of a new database; when filled in it is the target instead of `targetExisting`.
    public var newName: String = ""
    public private(set) var isCopying: Bool = false

    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let database: DatabaseModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored var onFinished: (@MainActor () -> Void)?

    init(contest: ContestModel, database: DatabaseModel, status: StatusModel) {
        self.contest = contest
        self.database = database
        self.status = status
        selectedContest = contest.activeId
    }

    /// Reads the contests and the databases once, off the main thread.
    public func load() async {
        contests = await contest.browserRows()
        if let id = selectedContest, contests?.contains(where: { $0.contestId == id }) != true {
            selectedContest = nil
        }
        do {
            let current: String = database.currentName
            databases = try await database.list().filter { $0 != current }
        } catch {
            databases = []
            status.showVerbatim(ErrorText.message(error))
        }
        if targetExisting.isEmpty || databases?.contains(targetExisting) != true {
            targetExisting = databases?.first ?? ""
        }
    }

    /// The target the window means: a typed new name wins over the chosen existing database.
    public var targetName: String {
        let typed: String = KotlinStrings.trim(newName)
        return typed.isEmpty ? targetExisting : typed
    }

    public var canCopy: Bool {
        !isCopying && !targetName.isEmpty
    }

    /// Copies, then reports in the status line and closes the window; a refusal or a failure keeps it open.
    public func copy() async {
        let name: String = targetName
        guard !name.isEmpty else {
            status.show("Vyber cílovou databázi nebo zadej název nové")
            return
        }
        guard !name.contains("/"), !name.contains("\0") else {
            status.show("Název databáze nesmí obsahovat „/“")
            return
        }
        guard name != database.currentName else {
            status.show("Cílová databáze je ta otevřená")
            return
        }
        isCopying = true
        defer { isCopying = false }
        let ids: [String]? = selectedContest.map { [$0] }
        let dir: URL = database.databasesDir
        let handle: LogbookHandle = database.handle
        do {
            let summary: ContestCopier.Summary = try await handle.run { access in
                let target: URL = try DatabaseCatalog(databasesDir: dir).pathFor(name)
                return try ContestCopier.copy(contestIds: ids, source: access.repository,
                                              sourceContests: access.contests, sourceUrl: handle.url, target: target)
            }
            status.show(Self.report(summary, database: name))
            onFinished?()
        } catch let error as ContestCopier.CopyError {
            status.show(error.message)
        } catch {
            status.show("Kopírování do databáze %s selhalo: %s", .string(name), .string(ErrorText.message(error)))
        }
    }

    /// „Zkopírováno do databáze X: …".
    static func report(_ summary: ContestCopier.Summary, database: String) -> ContestMessage {
        ContestMessage("Zkopírováno do databáze %s: %s závodů, %s QSO (%s už tam bylo)",
                       .string(database), .int(summary.contestsAdded + summary.contestsPresent),
                       .int(summary.qsosAdded), .int(summary.qsosSkipped))
    }
}
