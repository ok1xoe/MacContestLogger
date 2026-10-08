import Foundation

/// The user's own call → DXCC entity list (N1MM „Add call to country"): a callsign the country files get wrong or do
/// not know, assigned to an entity by hand. Kept in `<data dir>/dxcc-overrides.json`.
///
/// One store is shared by the DXCC lookup (`DxccOverrideLookup`, asked before Club Log's `cty.xml` and the
/// `dxcc-json` data) and the window that edits it, so a change is seen by the next lookup at once, without reloading
/// the contest data. A change only affects lookups made afterwards (new QSOs, spots, a rescore, „Přepočítat DXCC v
/// deníku"); QSOs already stored keep the country they were logged with until then.
public final class DxccOverrideStore: @unchecked Sendable {

    /// One assignment. `dxcc` is the entity's ADIF/DXCC number; `name` is only what the list shows when the country
    /// data no longer knows that number.
    public struct Entry: Codable, Equatable, Sendable {
        public var call: String
        public var dxcc: Int
        public var name: String

        public init(call: String, dxcc: Int, name: String) {
            self.call = call
            self.dxcc = dxcc
            self.name = name
        }
    }

    private struct FileContent: Codable {
        var version: Int = 1
        var overrides: [Entry] = []
    }

    public static let fileName = "dxcc-overrides.json"

    private let file: URL?
    private let lock = NSLock()
    private var entries: [Entry] = []
    /// Bumped by every change (a lookup caches nothing, a view re-reads on it).
    private var revisionValue: Int = 0

    /// A store over `file` (`nil` = in memory only); the file is read by `load()`.
    public init(file: URL?) {
        self.file = file
    }

    /// `<dataDir>/dxcc-overrides.json`.
    public static func file(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent(fileName)
    }

    /// The callsign as stored and compared: trimmed, upper case.
    public static func normalize(_ call: String) -> String {
        JavaText.trim(call).uppercased()
    }

    /// Portable suffixes that do not change the country of the call they follow.
    private static let neutralSuffixes: [String] = ["/P", "/M", "/QRP"]

    // MARK: - reading and writing the file

    /// Reads the file; a missing, empty or damaged file is an empty list. Blocking.
    public func load() {
        var read: [Entry] = []
        if let file, let data = try? Data(contentsOf: file),
           let content = try? JSONDecoder().decode(FileContent.self, from: data) {
            var seen: Set<String> = []
            for var entry in content.overrides {
                entry.call = Self.normalize(entry.call)
                if !entry.call.isEmpty, seen.insert(entry.call).inserted {
                    read.append(entry)
                }
            }
        }
        lock.lock()
        entries = read
        revisionValue += 1
        lock.unlock()
    }

    /// Writes the list (atomically). Blocking.
    public func save() throws {
        guard let file else { return }
        lock.lock()
        let snapshot: [Entry] = entries
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(FileContent(version: 1, overrides: snapshot))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    // MARK: - the list

    public var all: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public var revision: Int {
        lock.lock()
        defer { lock.unlock() }
        return revisionValue
    }

    /// Adds the assignment, or replaces the one of the same call. A blank call changes nothing.
    /// - Returns: the stored call, `nil` when it was blank.
    @discardableResult
    public func set(call: String, dxcc: Int, name: String) -> String? {
        let key: String = Self.normalize(call)
        guard !key.isEmpty else { return nil }
        lock.lock()
        if let index = entries.firstIndex(where: { $0.call == key }) {
            entries[index] = Entry(call: key, dxcc: dxcc, name: name)
        } else {
            entries.append(Entry(call: key, dxcc: dxcc, name: name))
        }
        revisionValue += 1
        lock.unlock()
        return key
    }

    /// Removes the assignment of `call`; `true` when there was one.
    @discardableResult
    public func remove(call: String) -> Bool {
        let key: String = Self.normalize(call)
        lock.lock()
        defer { lock.unlock() }
        guard let index = entries.firstIndex(where: { $0.call == key }) else { return false }
        entries.remove(at: index)
        revisionValue += 1
        return true
    }

    /// The DXCC number assigned to `call`: the exact call, else the call without a trailing `/P`, `/M` or `/QRP`.
    public func number(for call: String?) -> Int? {
        guard let call else { return nil }
        var key: String = Self.normalize(call)
        guard !key.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let hit = entries.first(where: { $0.call == key }) {
            return hit.dxcc
        }
        for suffix in Self.neutralSuffixes where key.hasSuffix(suffix) {
            key = String(key.dropLast(suffix.count))
            return entries.first(where: { $0.call == key })?.dxcc
        }
        return nil
    }
}

/// A DXCC lookup that asks the user's overrides first and the wrapped lookup (Club Log, `cty.dat`, `dxcc.json`) for
/// everything else. An override naming a number the wrapped data has no entity for is ignored.
public struct DxccOverrideLookup: DxccLookup {

    /// The lookup asked when no override applies.
    public let base: any DxccLookup
    private let store: DxccOverrideStore
    private let byNumber: [Int: DxccEntity]

    public init(_ base: any DxccLookup, store: DxccOverrideStore) {
        self.base = base
        self.store = store
        var index: [Int: DxccEntity] = [:]
        for entity in base.entities() {
            let number: Int = entity.adifDxcc ?? entity.entityCode
            if index[number] == nil {
                index[number] = entity
            }
        }
        byNumber = index
    }

    public func resolve(_ callsign: String?) -> DxccEntity? {
        if let number = store.number(for: callsign), let entity = byNumber[number] {
            return entity
        }
        return base.resolve(callsign)
    }

    public func resolve(_ callsign: String?, at date: Date?) -> DxccEntity? {
        if let number = store.number(for: callsign), let entity = byNumber[number] {
            return entity
        }
        return base.resolve(callsign, at: date)
    }

    public func entities() -> [DxccEntity] {
        base.entities()
    }

    /// The entity of a DXCC number in the wrapped data (what the override window lists and shows).
    public func entity(number: Int) -> DxccEntity? {
        byNumber[number]
    }
}
