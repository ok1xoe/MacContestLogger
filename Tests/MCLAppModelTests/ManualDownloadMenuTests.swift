import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// N1MM „Download latest PDF manual" (Tools and Help → „Stáhnout nejnovější PDF manuál…"): only on the click, the
/// save panel first, then one fetch of the newest release's manual; a failure offers the online docs. The fetcher
/// is a fake; nothing reaches the network.
@MainActor @Suite struct ManualDownloadMenuTests {

    final class Fetches: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [String] = []
        var urls: [String] { lock.withLock { value } }
        func add(_ url: String) { lock.withLock { value.append(url) } }
    }

    nonisolated static let pdf = Data("%PDF-1.7\nmanual\n%%EOF\n".utf8)

    static func app(_ fetches: Fetches, answer: ManualDownload.Outcome) async throws -> SpotApp {
        try await SpotApp.make(adjust: { environment in
            environment.network.fetchManual = { url in
                fetches.add(url)
                return answer
            }
        })
    }

    static func target() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mcl-manual-\(UUID().uuidString).pdf")
    }

    @Test func theItemsAskWhereToSaveBeforeAnyDownload() async throws {
        let fetches = Fetches()
        let spot = try await Self.app(fetches, answer: .pdf(Self.pdf))
        #expect(MenuActions.perform("help.pdfManual", app: spot.model) == .saveManual(suggestedName: "MacContestLogger-manual.pdf"))
        #expect(MenuActions.perform("tools.pdfManual", app: spot.model) == .saveManual(suggestedName: "MacContestLogger-manual.pdf"))
        await spot.model.updates.settle()
        #expect(fetches.urls.isEmpty, "the menu item alone downloads nothing")
        let file: URL = Self.target()
        defer { try? FileManager.default.removeItem(at: file) }
        spot.model.updates.downloadManual(to: file)
        await spot.model.updates.settle()
        #expect(fetches.urls == [ManualDownload.latestUrl])
        #expect(try Data(contentsOf: file) == Self.pdf)
        #expect(spot.model.status.message == spot.model.language.tr("PDF manuál uložen: %s", .string(file.path)))
        #expect(spot.model.updates.notice == nil)
        #expect(!spot.model.updates.isDownloadingManual)
        #expect(spot.opener.urls.isEmpty)
    }

    @Test func aFailureSavesNothingAndOffersTheOnlineDocs() async throws {
        let fetches = Fetches()
        let spot = try await Self.app(fetches, answer: .notPublished)
        let file: URL = Self.target()
        spot.model.updates.downloadManual(to: file)
        await spot.model.updates.settle()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        guard case .manualFailed(let text)? = spot.model.updates.notice else {
            Issue.record("expected the manual failure, got \(String(describing: spot.model.updates.notice))")
            return
        }
        #expect(spot.model.language.text(text) == "PDF manuál nejde stáhnout: nejnovější vydání PDF manuál nemá")
        spot.model.updates.openOnlineDocs()
        await eventually("docs") { spot.opener.urls.count == 1 }
        #expect(spot.opener.urls == [ManualDownload.docsUrl])
        #expect(spot.model.updates.notice == nil)
        for (answer, reason) in [(ManualDownload.Outcome.notPdf, "stažený soubor není PDF"),
                                 (.tooLarge, "soubor je větší, než manuál může být"),
                                 (.httpStatus(503), "HTTP 503"),
                                 (.redirectRefused("evil.example"), "přesměrování mimo GitHub (evil.example) odmítnuto")] {
            let other = try await Self.app(Fetches(), answer: answer)
            other.model.updates.downloadManual(to: file)
            await other.model.updates.settle()
            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(other.model.status.message == "PDF manuál nejde stáhnout: " + reason)
        }
    }

    @Test func theInertNetworkDownloadsNothing() async throws {
        let fetches = Fetches()
        let app = try await TestApp.make(adjust: { environment in
            var ports: NetworkPorts = NetworkPorts.inert
            ports.fetchManual = { url in
                fetches.add(url)
                return .pdf(Self.pdf)
            }
            environment.network = ports
        })
        #expect(MenuActions.perform("help.pdfManual", app: app.model) == nil)
        #expect(app.model.status.message == app.model.language.tr("Síť je vypnutá (MCL_INERT_NETWORK)"))
        let file: URL = Self.target()
        app.model.updates.downloadManual(to: file)
        await app.model.updates.settle()
        #expect(fetches.urls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await NetworkPorts.inert.fetchManual(ManualDownload.latestUrl) == .failed(NetworkPorts.disabledMessage))
    }
}
