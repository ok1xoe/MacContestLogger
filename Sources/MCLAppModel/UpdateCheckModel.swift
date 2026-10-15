import Foundation
import MCLCore
import Observation

/// N1MM „Check for New Program Version" (Tools and Help): one GET of the project's latest release, compared with the
/// running version. It runs only when the user asks (the menu item) or — opted in through „Kontrolovat novou verzi
/// při spuštění", off by default — once at start; with `MCL_INERT_NETWORK` it never connects. A newer release is
/// offered in an alert whose button opens its page; nothing is downloaded or installed.
@Observable @MainActor
public final class UpdateCheckModel {

    /// What the alert shows.
    public enum Notice: Equatable, Sendable {
        case newer(UpdateCheck.Release, current: String)
        case upToDate(current: String)
        case failed(ContestMessage)
        /// The PDF or HTML manual could not be downloaded (why); the alert offers the online documentation.
        case manualFailed(ContestMessage, ManualDownload.Format)
    }

    /// The alert of the main window (`nil` = none).
    public var notice: Notice?
    /// A check is in flight.
    public private(set) var isChecking = false
    /// The manual (PDF or HTML) is being downloaded.
    public private(set) var isDownloadingManual = false

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let network: NetworkPorts
    @ObservationIgnored private let appVersion: String?
    /// The API address (tests may point it at a local server).
    @ObservationIgnored var url: String = UpdateCheck.latestReleaseUrl
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The manual's address per release asset name (tests may point it at a local server).
    @ObservationIgnored var manualUrls: [String: String] = Dictionary(uniqueKeysWithValues:
        ManualDownload.Format.allCases.flatMap { format in
            ManualDownload.Language.allCases.map { (format.assetName($0), format.latestUrl($0)) }
        })
    @ObservationIgnored private var manualTask: Task<Void, Never>?

    init(config: ConfigModel, status: StatusModel, network: NetworkPorts, appVersion: String?) {
        self.config = config
        self.status = status
        self.network = network
        self.appVersion = appVersion
    }

    /// The running version as shown (`?` when the bundle has none, a development build).
    public var currentVersion: String {
        guard let appVersion, !appVersion.isEmpty else { return "?" }
        return appVersion
    }

    /// „Kontrolovat novou verzi při spuštění" (off by default).
    public var checksAtStart: Bool {
        get { config.config.checkUpdatesAtStart }
        set {
            config.config.checkUpdatesAtStart = newValue
            config.save(failureKey: "Uložení nastavení selhalo (%s)")
        }
    }

    /// The menu item: always answers (newer, up to date, or why it failed).
    public func checkNow() {
        run(manual: true)
    }

    /// At start: only with the user's opt-in, and quiet unless a newer release exists.
    public func checkAtStartIfEnabled() {
        guard config.config.checkUpdatesAtStart, !network.isInert else { return }
        run(manual: false)
    }

    /// „Otevřít stránku vydání".
    public func openReleasePage(_ release: UpdateCheck.Release) {
        let opener: UrlOpener = network.urlOpener
        let page: String = release.pageUrl
        notice = nil
        Task.detached {
            opener.open(page)
        }
    }

    private func run(manual: Bool) {
        guard !isChecking else { return }
        guard !network.isInert else {
            if manual {
                status.show("Síť je vypnutá (MCL_INERT_NETWORK)")
            }
            return
        }
        isChecking = true
        if manual {
            status.show("Hledám novou verzi programu…")
        }
        let http: any HttpGetter = network.http
        let address: String = url
        let current: String? = appVersion
        task = Task { [weak self] in
            let outcome: UpdateCheck.Outcome?
            let failure: String?
            do {
                let response: HttpGetResponse = try await BlockingQueue.run { try http.get(address) }
                outcome = UpdateCheck.evaluate(status: response.status, body: response.body, current: current)
                failure = nil
            } catch let error as HttpGetFailure {
                outcome = nil
                failure = error.message ?? error.javaClass
            } catch {
                outcome = nil
                failure = ErrorText.message(error)
            }
            self?.finish(outcome, failure: failure, manual: manual)
        }
    }

    private func finish(_ outcome: UpdateCheck.Outcome?, failure: String?, manual: Bool) {
        isChecking = false
        let current: String = currentVersion
        switch outcome {
        case .newer(let release)?:
            status.show("Je k dispozici nová verze %s (máte %s)", .string(release.version), .string(current))
            notice = .newer(release, current: current)
        case .upToDate?:
            guard manual else { return }
            status.show("Máte nejnovější verzi (%s)", .string(current))
            notice = .upToDate(current: current)
        case .failed(let code)?:
            guard manual else { return }
            let reason: ContestMessage = code.map { ContestMessage.verbatim("HTTP " + String($0)) }
                ?? ContestMessage("neočekávaná odpověď")
            fail(reason)
        case nil:
            guard manual else { return }
            fail(.verbatim(failure ?? ""))
        }
    }

    private func fail(_ reason: ContestMessage) {
        let text = ContestMessage("Kontrola nové verze selhala: %s", parts: [.message(reason)])
        status.show(text)
        notice = .failed(text)
    }

    /// Waits for the check and the manual download in flight (tests).
    func settle() async {
        await task?.value
        await manualTask?.value
    }

    // MARK: - the PDF and HTML manual

    /// N1MM „Download latest PDF manual" (and its HTML sibling) before the save panel: refused (with the reason in the
    /// status line) under `MCL_INERT_NETWORK` or while a download runs.
    public func canDownloadManual() -> Bool {
        guard !network.isInert else {
            status.show("Síť je vypnutá (MCL_INERT_NETWORK)")
            return false
        }
        return !isDownloadingManual
    }

    /// Downloads the manual of the newest release in `format` and `language` and saves it to `file` (chosen by the
    /// user in the save panel). Nothing is written unless the answer is a file of that format within the size limit.
    /// A release without the Czech guide (published before it existed) answers 404 for it: the English one is
    /// downloaded instead, under the same rules.
    public func downloadManual(to file: URL, format: ManualDownload.Format = .pdf,
                               language: ManualDownload.Language = .en) {
        guard canDownloadManual() else { return }
        isDownloadingManual = true
        status.show(format == .html ? ContestMessage("Stahuji HTML manuál…") : ContestMessage("Stahuji PDF manuál…"))
        let fetch: ManualFetcher = network.fetchManual
        let address: String = manualUrl(format, language)
        let fallback: String? = language == .en ? nil : manualUrl(format, .en)
        manualTask = Task { [weak self] in
            var outcome: ManualDownload.Outcome = await fetch(address, format)
            if outcome == .notPublished, let fallback {
                outcome = await fetch(fallback, format)
            }
            self?.finishManual(outcome, file: file, format: format)
        }
    }

    private func manualUrl(_ format: ManualDownload.Format, _ language: ManualDownload.Language) -> String {
        manualUrls[format.assetName(language)] ?? format.latestUrl(language)
    }

    private func finishManual(_ outcome: ManualDownload.Outcome, file: URL, format: ManualDownload.Format) {
        isDownloadingManual = false
        let html: Bool = format == .html
        let reason: ContestMessage
        switch outcome {
        case .file(let data):
            do {
                try data.write(to: file, options: .atomic)
                if html {
                    status.show("HTML manuál uložen: %s", .string(file.path))
                } else {
                    status.show("PDF manuál uložen: %s", .string(file.path))
                }
                return
            } catch {
                let detail: [ContestMessage.Part] = [.value(.string(ErrorText.message(error)))]
                let text = html ? ContestMessage("Uložení HTML manuálu selhalo: %s", parts: detail)
                    : ContestMessage("Uložení PDF manuálu selhalo: %s", parts: detail)
                status.show(text)
                notice = .failed(text)
                return
            }
        case .notPublished:
            reason = html ? ContestMessage("nejnovější vydání HTML manuál nemá")
                : ContestMessage("nejnovější vydání PDF manuál nemá")
        case .httpStatus(let code):
            reason = .verbatim("HTTP " + String(code))
        case .tooLarge:
            reason = ContestMessage("soubor je větší, než manuál může být")
        case .wrongFormat:
            reason = html ? ContestMessage("stažený soubor není HTML") : ContestMessage("stažený soubor není PDF")
        case .redirectRefused(let host):
            reason = ContestMessage("přesměrování mimo GitHub (%s) odmítnuto", parts: [.value(.string(host))])
        case .failed(let text):
            reason = .verbatim(text)
        }
        let text = html ? ContestMessage("HTML manuál nejde stáhnout: %s", parts: [.message(reason)])
            : ContestMessage("PDF manuál nejde stáhnout: %s", parts: [.message(reason)])
        status.show(text)
        notice = .manualFailed(text, format)
    }

    /// „Otevřít dokumentaci online" of the failure alert.
    public func openOnlineDocs() {
        let opener: UrlOpener = network.urlOpener
        notice = nil
        Task.detached {
            opener.open(ManualDownload.docsUrl)
        }
    }
}
