import Foundation

/// N1MM's transaction file (`.TRN`): every write to the QSO table is appended as one line of text (JSON) to a file next
/// to the database, `<database>.trn`. The database can be lost or damaged; the file is a separate, append-only record
/// from which the QSOs are rebuilt (`replay`) and imported again.
///
/// Not thread-safe: the repository calls it on its connection's queue. A write that fails is dropped — the journal
/// never stops a QSO from being logged.
public final class TransactionJournal {

    /// The kind of a transaction.
    public enum Operation: String, Codable, Sendable {
        case insert
        case update
        case delete
        case deleteAll
    }

    /// One line of the file.
    public struct Entry: Codable, Equatable, Sendable {
        /// The moment of the write, seconds since 1970.
        public let at: Double
        public let op: Operation
        /// The row id (`insert`, `update`, `delete`).
        public let id: Int64?
        /// The stored QSO (`insert`, `update`).
        public let qso: JournalQso?

        public init(at: Double, op: Operation, id: Int64?, qso: JournalQso?) {
            self.at = at
            self.op = op
            self.id = id
            self.qso = qso
        }
    }

    /// The journal file of a database file (`Contest.sqlite` → `Contest.sqlite.trn`).
    public static func fileURL(forDatabase url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".trn")
    }

    public let url: URL
    private let now: () -> Date
    private var handle: FileHandle?
    private var failed = false

    public init(url: URL, now: @escaping () -> Date = Date.init) {
        self.url = url
        self.now = now
    }

    deinit {
        try? handle?.close()
    }

    /// Appends one transaction.
    public func record(_ op: Operation, id: Int64? = nil, qso: Qso? = nil) {
        let entry = Entry(at: now().timeIntervalSince1970, op: op, id: id, qso: qso.map(JournalQso.init))
        guard let line = Self.line(entry) else { return }
        append(Data((line + "\n").utf8))
    }

    /// Closes the file (the repository is closing).
    public func close() {
        try? handle?.close()
        handle = nil
    }

    private func append(_ data: Data) {
        if handle == nil && !failed {
            let path: String = url.path
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            handle = FileHandle(forWritingAtPath: path)
            if handle == nil {
                failed = true
            }
            _ = try? handle?.seekToEnd()
        }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            try? handle.close()
            self.handle = nil
        }
    }

    // MARK: - text

    /// One entry as a line of JSON (keys sorted, no line breaks).
    public static func line(_ entry: Entry) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entry) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The entries of a file's text; `unreadable` = lines that are not an entry (a line cut short by a crash).
    public static func parse(_ text: String) -> (entries: [Entry], unreadable: Int) {
        let decoder = JSONDecoder()
        var entries: [Entry] = []
        var unreadable: Int = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            let line: Substring = raw
            if line.allSatisfy(\.isWhitespace) { continue }
            if let entry = try? decoder.decode(Entry.self, from: Data(line.utf8)) {
                entries.append(entry)
            } else {
                unreadable += 1
            }
        }
        return (entries, unreadable)
    }

    /// The QSO table rebuilt from the transactions, in row-id order: inserts and updates set a row, a delete removes
    /// it, `deleteAll` empties the table. Tombstones (deleted in the network log) are left out.
    public static func replay(_ entries: [Entry]) -> [Qso] {
        var rows: [Int64: Qso] = [:]
        for entry in entries {
            switch entry.op {
            case .insert, .update:
                guard let id = entry.id, let qso = entry.qso else { continue }
                var row: Qso = qso.qso
                row.id = id
                rows[id] = row
            case .delete:
                if let id = entry.id {
                    rows[id] = nil
                }
            case .deleteAll:
                rows.removeAll()
            }
        }
        return rows.keys.sorted().compactMap { rows[$0] }.filter { !$0.deleted }
    }

    /// The QSOs to recover into the open contest: those of the open contest when the file has any, otherwise those of
    /// the contest the file's last QSO belongs to (the log worked when the database was lost).
    public static func recoverable(_ qsos: [Qso], activeContestId: String) -> [Qso] {
        let own: [Qso] = qsos.filter { $0.contestId == activeContestId }
        if !own.isEmpty {
            return own
        }
        guard let last = qsos.last else { return [] }
        return qsos.filter { $0.contestId == last.contestId }
    }
}

/// A QSO as the journal stores it: every column of the table.
public struct JournalQso: Codable, Equatable, Sendable {
    public var time: Double?
    public var call: String
    public var freqHz: Int
    public var band: String?
    public var mode: String?
    public var rstSent: String
    public var rstRcvd: String
    public var exchangeSent: String
    public var exchangeRcvd: String
    public var serialSent: Int?
    public var serialRcvd: Int?
    public var points: Int
    public var multiplier: Bool
    public var runMode: String
    public var `operator`: String
    public var comment: String
    public var dxccEntity: Int?
    public var dxccName: String
    public var continent: String
    public var uuid: String
    public var stationId: String
    public var version: Int64
    public var updatedAt: Double?
    public var deleted: Bool
    public var xqso: Bool
    public var contestId: String

    public init(_ q: Qso) {
        time = q.timestampUtc?.timeIntervalSince1970
        call = q.call
        freqHz = q.freqHz
        band = q.band?.rawValue
        mode = q.mode?.rawValue
        rstSent = q.rstSent
        rstRcvd = q.rstRcvd
        exchangeSent = q.exchangeSent
        exchangeRcvd = q.exchangeRcvd
        serialSent = q.serialSent
        serialRcvd = q.serialRcvd
        points = q.points
        multiplier = q.multiplier
        runMode = q.runMode.rawValue
        self.operator = q.operator
        comment = q.comment
        dxccEntity = q.dxccEntity
        dxccName = q.dxccName
        continent = q.continent
        uuid = q.uuid
        stationId = q.stationId
        version = q.version
        updatedAt = q.updatedAtUtc?.timeIntervalSince1970
        deleted = q.deleted
        xqso = q.xqso
        contestId = q.contestId
    }

    /// The QSO back (without its row id).
    public var qso: Qso {
        var q = Qso()
        q.timestampUtc = time.map { Date(timeIntervalSince1970: $0) }
        q.call = call
        q.freqHz = freqHz
        if let band, let value = Band(rawValue: band) {
            q.band = value
        }
        q.mode = mode.flatMap(Mode.init(rawValue:))
        q.rstSent = rstSent
        q.rstRcvd = rstRcvd
        q.exchangeSent = exchangeSent
        q.exchangeRcvd = exchangeRcvd
        q.serialSent = serialSent
        q.serialRcvd = serialRcvd
        q.points = points
        q.multiplier = multiplier
        q.runMode = RunMode(rawValue: runMode) ?? .run
        q.operator = self.operator
        q.comment = comment
        q.dxccEntity = dxccEntity
        q.dxccName = dxccName
        q.continent = continent
        q.uuid = uuid
        q.stationId = stationId
        q.version = version
        q.updatedAtUtc = updatedAt.map { Date(timeIntervalSince1970: $0) }
        q.deleted = deleted
        q.xqso = xqso
        q.contestId = contestId
        return q
    }
}
