import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// N1MM „Download latest PDF manual" (Tools and Help → „Stáhnout nejnovější PDF manuál…", Help → „Stáhnout nejnovější
/// HTML manuál…"): only on the click, the save panel first, then one fetch of the newest release's manual in the
/// chosen format; a failure offers the online docs. The fetcher is a fake; nothing reaches the network.
@MainActor @Suite struct ManualDownloadMenuTests {

    final class Fetches: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [String] = []
        private var kinds: [ManualDownload.Format] = []
        var urls: [String] { lock.withLock { value } }
        var formats: [ManualDownload.Format] { lock.withLock { kinds } }
        func add(_ url: String, _ format: ManualDownload.Format = .pdf) {
            lock.withLock {
                value.append(url)
                kinds.append(format)
            }
        }
    }

    nonisolated static let pdf = Data("%PDF-1.7\nmanual\n%%EOF\n".utf8)
    nonisolated static let czechHtml = Data("<!DOCTYPE html>\n<html lang=\"cs\"><body>manuál</body></html>\n".utf8)
    nonisolated static let html = Data("<!DOCTYPE html>\n<html lang=\"en\"><body>manual</body></html>\n".utf8)

    static func app(_ fetches: Fetches, answer: ManualDownload.Outcome) async throws -> SpotApp {
        try await SpotApp.make(adjust: { environment in
            environment.network.fetchManual = { url, format in
                fetches.add(url, format)
                return answer
            }
        })
    }

    static func target() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mcl-manual-\(UUID().uuidString).pdf")
    }

    @Test func theItemsAskWhereToSaveBeforeAnyDownload() async throws {
        let fetches = Fetches()
        let spot = try await Self.app(fetches, answer: .file(Self.pdf))
        // The application is Czech: the Czech guide.
        #expect(spot.model.language.code == "cs")
        #expect(MenuActions.perform("help.pdfManual", app: spot.model)
                == .saveManual(suggestedName: "MacContestLogger-manual-cs.pdf", format: .pdf, language: .cs))
        #expect(MenuActions.perform("tools.pdfManual", app: spot.model)
                == .saveManual(suggestedName: "MacContestLogger-manual-cs.pdf", format: .pdf, language: .cs))
        #expect(MenuActions.perform("help.htmlManual", app: spot.model)
                == .saveManual(suggestedName: "MacContestLogger-manual-cs.html", format: .html, language: .cs))
        await spot.model.updates.settle()
        #expect(fetches.urls.isEmpty, "the menu item alone downloads nothing")
        let file: URL = Self.target()
        defer { try? FileManager.default.removeItem(at: file) }
        spot.model.updates.downloadManual(to: file)
        await spot.model.updates.settle()
        #expect(fetches.urls == [ManualDownload.latestUrl])
        #expect(fetches.formats == [.pdf])
        #expect(try Data(contentsOf: file) == Self.pdf)
        #expect(spot.model.status.message == spot.model.language.tr("PDF manuál uložen: %s", .string(file.path)))
        #expect(spot.model.updates.notice == nil)
        #expect(!spot.model.updates.isDownloadingManual)
        #expect(spot.opener.urls.isEmpty)
    }

    /// Any other language than Czech gets the English guide (under the original asset names).
    @Test func theItemsFollowTheApplicationLanguage() async throws {
        let fetches = Fetches()
        let spot = try await Self.app(fetches, answer: .file(Self.pdf))
        await spot.model.language.switchTo("en")
        #expect(spot.model.language.code == "en")
        #expect(MenuActions.perform("help.pdfManual", app: spot.model)
                == .saveManual(suggestedName: "MacContestLogger-manual.pdf", format: .pdf, language: .en))
        #expect(MenuActions.perform("help.htmlManual", app: spot.model)
                == .saveManual(suggestedName: "MacContestLogger-manual.html", format: .html, language: .en))
        #expect(ManualDownload.Language.forApp("de") == .en)
        #expect(ManualDownload.Language.forApp("CS") == .cs)
        #expect(ManualDownload.Format.pdf.latestUrl(.cs)
                == "https://github.com/ok1xoe/MacContestLogger/releases/latest/download/MacContestLogger-manual-cs.pdf")
        let file: URL = Self.target()
        defer { try? FileManager.default.removeItem(at: file) }
        spot.model.updates.downloadManual(to: file, format: .pdf, language: .cs)
        await spot.model.updates.settle()
        #expect(fetches.urls == [ManualDownload.Format.pdf.latestUrl(.cs)], "found: no fallback")
        #expect(try Data(contentsOf: file) == Self.pdf)
    }

    /// A release without the Czech guide (404) gives the English one; any other failure of the Czech one is reported.
    @Test func aMissingCzechGuideFallsBackToEnglish() async throws {
        let fetches = Fetches()
        let spot = try await SpotApp.make(adjust: { environment in
            environment.network.fetchManual = { url, format in
                fetches.add(url, format)
                return url.hasSuffix("-cs.pdf") ? .notPublished : .file(Self.pdf)
            }
        })
        let file: URL = Self.target()
        defer { try? FileManager.default.removeItem(at: file) }
        spot.model.updates.downloadManual(to: file, format: .pdf, language: .cs)
        await spot.model.updates.settle()
        #expect(fetches.urls == [ManualDownload.Format.pdf.latestUrl(.cs), ManualDownload.latestUrl])
        #expect(try Data(contentsOf: file) == Self.pdf)
        #expect(spot.model.updates.notice == nil)
        try FileManager.default.removeItem(at: file)
        let wrong = Fetches()
        let other = try await Self.app(wrong, answer: .wrongFormat)
        other.model.updates.downloadManual(to: file, format: .pdf, language: .cs)
        await other.model.updates.settle()
        #expect(wrong.urls == [ManualDownload.Format.pdf.latestUrl(.cs)], "only a 404 falls back")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(other.model.status.message == "PDF manuál nejde stáhnout: stažený soubor není PDF")
    }

    @Test func aFailureSavesNothingAndOffersTheOnlineDocs() async throws {
        let fetches = Fetches()
        let spot = try await Self.app(fetches, answer: .notPublished)
        let file: URL = Self.target()
        spot.model.updates.downloadManual(to: file)
        await spot.model.updates.settle()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        guard case .manualFailed(let text, .pdf)? = spot.model.updates.notice else {
            Issue.record("expected the manual failure, got \(String(describing: spot.model.updates.notice))")
            return
        }
        #expect(spot.model.language.text(text) == "PDF manuál nejde stáhnout: nejnovější vydání PDF manuál nemá")
        spot.model.updates.openOnlineDocs()
        await eventually("docs") { spot.opener.urls.count == 1 }
        #expect(spot.opener.urls == [ManualDownload.docsUrl])
        #expect(spot.model.updates.notice == nil)
        for (answer, reason) in [(ManualDownload.Outcome.wrongFormat, "stažený soubor není PDF"),
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
            ports.fetchManual = { url, format in
                fetches.add(url, format)
                return .file(Self.pdf)
            }
            environment.network = ports
        })
        #expect(MenuActions.perform("help.pdfManual", app: app.model) == nil)
        #expect(MenuActions.perform("help.htmlManual", app: app.model) == nil)
        #expect(app.model.status.message == app.model.language.tr("Síť je vypnutá (MCL_INERT_NETWORK)"))
        let file: URL = Self.target()
        app.model.updates.downloadManual(to: file)
        app.model.updates.downloadManual(to: file, format: .html)
        await app.model.updates.settle()
        #expect(fetches.urls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await NetworkPorts.inert.fetchManual(ManualDownload.latestUrl, .pdf) == .failed(NetworkPorts.disabledMessage))
        #expect(await NetworkPorts.inert.fetchManual(ManualDownload.Format.html.latestUrl, .html)
                == .failed(NetworkPorts.disabledMessage))
    }

    @Test func theHtmlManualIsSavedOnlyWhenItIsHtml() async throws {
        let fetches = Fetches()
        let spot = try await Self.app(fetches, answer: .file(Self.html))
        let file: URL = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-manual-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(at: file) }
        spot.model.updates.downloadManual(to: file, format: .html)
        await spot.model.updates.settle()
        #expect(fetches.urls == [ManualDownload.Format.html.latestUrl])
        #expect(fetches.formats == [.html])
        #expect(try Data(contentsOf: file) == Self.html)
        #expect(spot.model.status.message == spot.model.language.tr("HTML manuál uložen: %s", .string(file.path)))
        #expect(spot.model.updates.notice == nil)
        try FileManager.default.removeItem(at: file)
        for (answer, reason) in [(ManualDownload.Outcome.wrongFormat, "stažený soubor není HTML"),
                                 (.notPublished, "nejnovější vydání HTML manuál nemá"),
                                 (.tooLarge, "soubor je větší, než manuál může být")] {
            let other = try await Self.app(Fetches(), answer: answer)
            other.model.updates.downloadManual(to: file, format: .html)
            await other.model.updates.settle()
            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(other.model.status.message == "HTML manuál nejde stáhnout: " + reason)
            guard case .manualFailed(_, .html)? = other.model.updates.notice else {
                Issue.record("expected the HTML manual failure, got \(String(describing: other.model.updates.notice))")
                continue
            }
        }
    }

    /// The real downloader behind the HTML item, against a local server on 127.0.0.1: the HTML is saved, a PDF served
    /// in its place is not.
    @Test func theHtmlItemOverALocalServer() async throws {
        let server = try LocalHttpServer(routes: [
            "/latest/MacContestLogger-manual.html": .init(body: String(decoding: Self.html, as: UTF8.self)),
            "/wrong/MacContestLogger-manual.html": .init(body: String(decoding: Self.pdf, as: UTF8.self)),
        ])
        defer { server.stop() }
        let port: Int = server.port
        let spot = try await SpotApp.make(adjust: { environment in
            environment.network.fetchManual = { url, format in
                await ManualDownloader(allow: { $0.host == "127.0.0.1" && $0.port == port }, requestTimeout: 600,
                                       timeout: 900).fetch(url, format: format)
            }
        })
        let base = "http://127.0.0.1:\(port)/"
        spot.model.updates.manualUrls["MacContestLogger-manual.html"] = base + "latest/MacContestLogger-manual.html"
        let file: URL = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-manual-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(at: file) }
        spot.model.updates.downloadManual(to: file, format: .html)
        await spot.model.updates.settle()
        #expect(try Data(contentsOf: file) == Self.html)
        try FileManager.default.removeItem(at: file)
        spot.model.updates.manualUrls["MacContestLogger-manual.html"] = base + "wrong/MacContestLogger-manual.html"
        spot.model.updates.downloadManual(to: file, format: .html)
        await spot.model.updates.settle()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(spot.model.status.message == "HTML manuál nejde stáhnout: stažený soubor není HTML")
        #expect(server.requestedPaths == ["/latest/MacContestLogger-manual.html", "/wrong/MacContestLogger-manual.html"])
        // The Czech guide: served → saved; not in the release (404) → the English one.
        spot.model.updates.manualUrls["MacContestLogger-manual-cs.html"] = base + "latest/MacContestLogger-manual-cs.html"
        spot.model.updates.manualUrls["MacContestLogger-manual.html"] = base + "latest/MacContestLogger-manual.html"
        spot.model.updates.downloadManual(to: file, format: .html, language: .cs)
        await spot.model.updates.settle()
        #expect(try Data(contentsOf: file) == Self.html)
        #expect(server.requestedPaths.suffix(2)
                == ["/latest/MacContestLogger-manual-cs.html", "/latest/MacContestLogger-manual.html"])
        try FileManager.default.removeItem(at: file)
        let czech = try LocalHttpServer(routes: [
            "/latest/MacContestLogger-manual-cs.html": .init(body: String(decoding: Self.czechHtml, as: UTF8.self)),
        ])
        defer { czech.stop() }
        let czechPort: Int = czech.port
        let local = try await SpotApp.make(adjust: { environment in
            environment.network.fetchManual = { url, format in
                await ManualDownloader(allow: { $0.host == "127.0.0.1" && $0.port == czechPort }, requestTimeout: 600,
                                       timeout: 900).fetch(url, format: format)
            }
        })
        local.model.updates.manualUrls["MacContestLogger-manual-cs.html"] =
            "http://127.0.0.1:\(czechPort)/latest/MacContestLogger-manual-cs.html"
        local.model.updates.downloadManual(to: file, format: .html, language: .cs)
        await local.model.updates.settle()
        #expect(try Data(contentsOf: file) == Self.czechHtml)
        #expect(czech.requestedPaths == ["/latest/MacContestLogger-manual-cs.html"])
    }
}
