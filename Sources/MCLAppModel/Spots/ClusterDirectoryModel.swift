import Foundation
import MCLCore
import Observation

/// Settings → DX Cluster → „Vybrat ze seznamu": the published list of public clusters (`ClusterDirectory`). It is
/// read from disk when the chooser opens (the downloaded copy, or the one shipped with the app when that is newer);
/// the network is used only when the user presses „Aktualizovat seznam z GitHubu", never by itself. Without a
/// fetcher (`MCL_INERT_NETWORK`, tests) the update reports that the network is off. A failed update keeps the copy
/// that was there.
@Observable @MainActor
public final class ClusterDirectoryModel {

    /// The list shown (`nil` until `load` ran, or when no copy can be read).
    public private(set) var directory: ClusterDirectory?
    /// Where `directory` came from.
    public private(set) var origin: ClusterDirectoryStore.Origin?
    /// An update is running (the button is off meanwhile).
    public private(set) var updating: Bool = false
    /// The result of the last update in this session.
    public private(set) var result: ContestMessage?

    @ObservationIgnored private let store: ClusterDirectoryStore
    @ObservationIgnored private let fetcher: (any DataFetcher)?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private let bundled: @Sendable () -> ClusterDirectory?

    public init(dataDir: URL, fetcher: (any DataFetcher)?, url: URL = ClusterDirectory.defaultURL,
                bundled: @escaping @Sendable () -> ClusterDirectory? = ClusterDirectoryStore.bundled) {
        store = ClusterDirectoryStore(dataDir: dataDir)
        self.fetcher = fetcher
        self.url = url
        self.bundled = bundled
    }

    /// Reads the list from disk (off the main thread).
    public func load() async {
        let store: ClusterDirectoryStore = self.store
        let bundled: @Sendable () -> ClusterDirectory? = self.bundled
        let loaded: (directory: ClusterDirectory, origin: ClusterDirectoryStore.Origin)? =
            (try? await BlockingQueue.run { store.load(bundled: bundled()) }) ?? nil
        directory = loaded?.directory
        origin = loaded?.origin
    }

    /// „Aktualizovat seznam z GitHubu": downloads the published list, checks it and stores it as the cached copy.
    public func update() async {
        guard !updating else { return }
        guard let fetcher else {
            result = ContestMessage("Síť je vypnutá (MCL_INERT_NETWORK)")
            return
        }
        updating = true
        defer { updating = false }
        let updater = ClusterDirectoryUpdater(fetcher: fetcher, url: url)
        do {
            let downloaded: (data: Data, directory: ClusterDirectory) = try await updater.download()
            let store: ClusterDirectoryStore = self.store
            let data: Data = downloaded.data
            let saved: ClusterDirectory.Failure? = try await BlockingQueue.run {
                do throws(ClusterDirectory.Failure) {
                    try store.save(data)
                    return nil
                } catch {
                    return error
                }
            }
            if let saved {
                throw saved
            }
            directory = downloaded.directory
            origin = .downloaded
            result = ContestMessage("Seznam clusterů aktualizován: %s clusterů (%s)",
                                    .int(downloaded.directory.clusters.count),
                                    .string(downloaded.directory.updated))
        } catch let failure as ClusterDirectory.Failure {
            result = ContestMessage("Aktualizace seznamu clusterů selhala: %s (zůstává dosavadní seznam)",
                                    parts: [.message(Self.text(failure))])
        } catch {
            result = ContestMessage("Aktualizace seznamu clusterů selhala: %s (zůstává dosavadní seznam)",
                                    parts: [.message(ContestMessage.verbatim(ErrorText.message(error)))])
        }
    }

    /// The line under the list: which copy it is and its date.
    public var statusLine: ContestMessage? {
        guard let directory, let origin else { return nil }
        let date: String = directory.updated.isEmpty ? "?" : directory.updated
        switch origin {
        case .bundled:
            return ContestMessage("Seznam dodaný s programem, aktualizován %s", .string(date))
        case .downloaded:
            return ContestMessage("Seznam stažený z GitHubu, aktualizován %s", .string(date))
        }
    }

    nonisolated static func text(_ failure: ClusterDirectory.Failure) -> ContestMessage {
        switch failure {
        case .tooLarge:
            return ContestMessage("soubor je příliš velký")
        case .notJSON:
            return ContestMessage("soubor není platný seznam clusterů")
        case .newerSchema:
            return ContestMessage("seznam je v novějším formátu, aktualizujte program")
        case .noClusters:
            return ContestMessage("seznam neobsahuje žádný platný cluster")
        case .http(let code):
            return ContestMessage.verbatim("HTTP " + String(code))
        case .transport(let text):
            return ContestMessage.verbatim(text)
        case .write(let text):
            return ContestMessage("nelze uložit: %s", .string(text))
        }
    }
}
