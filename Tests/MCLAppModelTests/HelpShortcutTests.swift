import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Alt+H (`AppState.openHelp`): the documentation page opens through the URL port; the inert
/// port opens nothing and the action is no longer "unavailable".
@MainActor @Suite struct HelpShortcutTests {

    @Test func theLivePortGetsTheKotlinUrl() async throws {
        let spot = try await SpotApp.make()
        spot.model.entry.runShortcut(.help)
        await spot.model.callbook.settle()
        #expect(spot.opener.urls == ["https://github.com/ok1xoe/MacContestLogger/tree/main/docs"])
        #expect(spot.model.status.message != EntryTexts.unavailable)
    }

    /// A recording opener behind `NetworkPorts.production`: `MCL_INERT_NETWORK=1` never reaches it, `"0"` does.
    @Test(arguments: [("1", 0), ("0", 1)]) func theInertSwitchDecidesWhetherTheOpenerIsReached(
        value: String, expected: Int) async throws {
        let recording = RecordingUrlOpener()
        var live: NetworkPorts = .inert
        live.urlOpener = recording.opener
        live.isInert = false
        let ports: NetworkPorts = NetworkPorts.production(environment: ["MCL_INERT_NETWORK": value], live: live)
        let app = try await SpotApp.make(adjust: { $0.network = ports })
        app.model.entry.runShortcut(.help)
        await app.model.callbook.settle()
        #expect(recording.urls.count == expected)
        #expect(app.model.status.message != EntryTexts.unavailable)
    }
}
