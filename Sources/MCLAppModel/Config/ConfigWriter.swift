import Dispatch
import Foundation
import MCLCore
import Observation

/// Writes `config.json` snapshots on one serial queue, in the order they were enqueued.
///
/// Kotlin saves the shared config synchronously on the UI thread (`saveConfig()`), which serializes writes from all
/// windows. Here the main thread enqueues an `AppConfig` value and the write runs on this queue: never on the main
/// thread and never in the cooperative pool. The bytes are those of `ConfigStore.save` (pretty-printed, sorted keys),
/// but an error is reported instead of swallowed, because Kotlin shows it in the status line.
public final class ConfigWriter: Sendable {

    private let queue = DispatchQueue(label: "cz.ok1xoe.maccontestlogger.config-writer", qos: .userInitiated)
    private let write: @Sendable (AppConfig) throws -> Void

    /// Writes to `file`.
    public convenience init(file: URL) {
        self.init { config in
            try Self.writeFile(config, to: file)
        }
    }

    /// Writes through `write` (tests inject a failing writer).
    public init(write: @escaping @Sendable (AppConfig) throws -> Void) {
        self.write = write
    }

    /// Enqueues a snapshot; `completion` runs on the writer queue with the error or `nil`.
    public func enqueue(_ config: AppConfig, completion: @escaping @Sendable ((any Error)?) -> Void) {
        let write = self.write
        queue.async {
            do {
                try write(config)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    /// Waits until every snapshot enqueued so far is written.
    public func flush() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                continuation.resume()
            }
        }
    }

    /// `ConfigStore.save` with errors: the same encoder, the directory created when missing. The bytes go to a
    /// temporary file in the same directory that then replaces `config.json` (`.atomic`): an exit in the middle of a
    /// write (a second signal, a crash) leaves the old file whole, never a truncated one (Java `writeValue` writes in
    /// place — a safety divergence). Two things follow from replacing the file instead of writing into it, and both
    /// are handled: a symbolic link `config.json` is resolved first (the target is replaced, the link stays), and the
    /// permissions of the file being replaced are put back on the new one.
    public static func writeFile(_ config: AppConfig, to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data = try encoder.encode(config)
        let files = FileManager.default
        let target: URL = resolvingLinks(file)
        try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let permissions: Any? = (try? files.attributesOfItem(atPath: target.path))?[.posixPermissions]
        try data.write(to: target, options: .atomic)
        if let permissions {
            try? files.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }
    }

    /// Follows a chain of symbolic links to the file they name (also a dangling one: the write then creates the
    /// file the link points at). A chain longer than 16 hops is not followed further.
    static func resolvingLinks(_ file: URL) -> URL {
        let files = FileManager.default
        var current: URL = file
        for _ in 0..<16 {
            guard let destination = try? files.destinationOfSymbolicLink(atPath: current.path) else {
                return current
            }
            current = URL(fileURLWithPath: destination, relativeTo: current.deletingLastPathComponent())
                .standardizedFileURL
        }
        return current
    }
}

/// The shared configuration (Kotlin `AppState.config`, one mutable object read by every window) and its saving.
@Observable @MainActor
public final class ConfigModel {

    public var config: AppConfig
    /// Kotlin `configRevision`: raised after a Settings commit or a profile load, so the views that read the
    /// configuration directly redraw (the map, the windows that read it without a model of their own).
    public private(set) var revision: Int = 0
    /// Store for the setup/station JSON snapshots of contests (`ConfigStore.toJSON`/`fromJSON`).
    public let store: ConfigStore
    @ObservationIgnored let writer: ConfigWriter
    @ObservationIgnored private let status: StatusModel

    public init(config: AppConfig, store: ConfigStore, writer: ConfigWriter, status: StatusModel) {
        self.config = config
        self.store = store
        self.writer = writer
        self.status = status
    }

    /// Kotlin `runCatching { saveConfig() }.onFailure { statusMessage = tr(failureKey, it.message) }`: saves the
    /// current snapshot; a failure shows `failureKey` (a Czech key with one `%s`) in the status line.
    ///
    /// This writer only writes the file; the side effects of Kotlin `saveConfig` (parallel clusters, footswitch, SCP and
    /// call history reload) belong to those services.
    public func save(failureKey: String) {
        let status = self.status
        writer.enqueue(config) { error in
            guard let error else { return }
            let text: String = ErrorText.message(error)
            MainHop.post {
                status.show(ContestMessage(failureKey, .string(text)))
            }
        }
    }

    /// Kotlin `runCatching { configStore.save(config) }`: saves the current snapshot and ignores a failure.
    public func saveSilently() {
        writer.enqueue(config) { _ in }
    }

    /// Kotlin `configStore.save(config)` with its exception (the Settings commit and the profile load): writes
    /// `snapshot` after the writes enqueued before it and waits for the result. The error is returned, not shown;
    /// the caller decides the text. The live `config` is not touched (the atomic commit).
    public func saveNow(_ snapshot: AppConfig) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            writer.enqueue(snapshot) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// `configRevision++`.
    public func bumpRevision() {
        revision += 1
    }

    /// Waits for the enqueued writes.
    public func flush() async {
        await writer.flush()
    }
}
