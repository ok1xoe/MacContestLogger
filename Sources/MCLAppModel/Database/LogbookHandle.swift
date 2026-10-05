import Foundation
import MCLCore
import os

/// One open logbook database: the repository, the service over it (active contest) and the contest registry, all on
/// one SQLite connection.
///
/// The core types are plain classes, not `Sendable`. All database work of a handle runs on its own **serial** queue
/// (`run`), in the order it was enqueued — never on the main thread, never in the cooperative pool. Order matters:
/// switching the active contest before an insert, a re-read after an insert, and the close after every job enqueued
/// before it. After `close` every access throws `LogbookHandle.closedError` instead of touching the freed connection.
public final class LogbookHandle: @unchecked Sendable {

    /// What the body of `withDatabase` may touch (valid only inside the body).
    public struct Access {
        public let repository: LogbookRepository
        public let service: LogbookService
        public let contests: ContestStore
    }

    /// Database name (file name without `.sqlite`).
    public let name: String
    /// The database file.
    public let url: URL

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var closed = false
    /// `closed` for readers that must not wait for a running job (the lock is held for a whole job).
    private let closedFlag = OSAllocatedUnfairLock(initialState: false)
    private let repository: LogbookRepository
    private let service: LogbookService
    private let contests: ContestStore

    private init(name: String, url: URL, repository: LogbookRepository) throws {
        self.name = name
        self.url = url
        self.repository = repository
        self.service = LogbookService(repository: repository)
        self.contests = try ContestStore(repository)
        self.queue = DispatchQueue(label: "cz.ok1xoe.maccontestlogger.logbook", qos: .userInitiated)
    }

    /// Opens (or creates) the database file. Blocking.
    public static func open(name: String, url: URL) throws -> LogbookHandle {
        try LogbookHandle(name: name, url: url, repository: LogbookRepository(url: url))
    }

    /// An in-memory database (tests).
    public static func inMemory(name: String = "memory") throws -> LogbookHandle {
        try LogbookHandle(name: name, url: URL(fileURLWithPath: "/dev/null"), repository: LogbookRepository.inMemory())
    }

    /// The error of every access after `close`.
    public var closedError: LogbookError {
        LogbookError("Databáze \(name) je zavřená.")
    }

    /// Whether `close` has run.
    public var isClosed: Bool {
        closedFlag.withLock { $0 }
    }

    /// Runs `body` with exclusive access on the calling thread; throws `closedError` after `close`. Blocking — from a job of
    /// this handle's queue, from the cluster's transport thread (a remote QSO state; the lock makes it exclusive with
    /// the jobs) or from a test; never from the main thread or the cooperative pool.
    public func withDatabase<T>(_ body: (Access) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if closed {
            throw closedError
        }
        return try body(Access(repository: repository, service: service, contests: contests))
    }

    /// Runs `body` on the handle's serial queue (after every job enqueued before it).
    public func run<T: Sendable>(_ body: @escaping @Sendable (Access) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
            queue.async {
                do {
                    continuation.resume(returning: try self.withDatabase(body))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Closes the connection (Kotlin `runCatching { repo.close() }`) after the jobs enqueued so far; later accesses
    /// throw. Closing twice is a no-op.
    public func close() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.lock.lock()
                if !self.closed {
                    self.closed = true
                    self.closedFlag.withLock { $0 = true }
                    self.repository.close()
                }
                self.lock.unlock()
                continuation.resume()
            }
        }
    }
}
