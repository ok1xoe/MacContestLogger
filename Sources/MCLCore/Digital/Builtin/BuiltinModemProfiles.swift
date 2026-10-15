import Foundation

/// A named setup of the built-in RTTY modem (MMTTY's profiles, `UserPara.ini`; RYRY's 16 slots): shift, speed,
/// demodulator, AFC/NET, filters… — every modem parameter except the TX echo. Applied to one receiver.
public struct BuiltinModemProfile: Codable, Equatable, Sendable {

    /// A parameter's value.
    public enum Value: Codable, Equatable, Sendable {
        case number(Double)
        case flag(Bool)
        case choice(String)
    }

    public var name: String
    public var values: [String: Value]

    public init(name: String, values: [String: Value]) {
        self.name = name
        self.values = values
    }
}

/// The 16 profile slots in `RttyProfiles.json` of the data folder. An unreadable file is never overwritten.
public final class BuiltinModemProfiles: Sendable {

    public static let slotCount = 16
    public static let fileName = "RttyProfiles.json"

    public enum Failure: Error, Equatable {
        /// The file exists but cannot be read: it is not overwritten.
        case unreadable
        case badSlot(Int)
        case io(String)
    }

    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent(Self.fileName)
    }

    private struct File: Codable {
        var slots: [BuiltinModemProfile?]
    }

    /// `nil` = the file exists but cannot be read.
    private func readChecked() -> [BuiltinModemProfile?]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else {
            return nil
        }
        return file.slots
    }

    /// The slots (always `slotCount`; empty = `nil`).
    public func load() -> [BuiltinModemProfile?] {
        var slots: [BuiltinModemProfile?] = readChecked() ?? []
        if slots.count < Self.slotCount {
            slots += [BuiltinModemProfile?](repeating: nil, count: Self.slotCount - slots.count)
        }
        return Array(slots.prefix(Self.slotCount))
    }

    /// Stores (or with `nil` clears) a slot.
    public func save(_ profile: BuiltinModemProfile?, slot: Int) throws(Failure) {
        guard (0..<Self.slotCount).contains(slot) else { throw .badSlot(slot) }
        guard readChecked() != nil else { throw .unreadable }
        var slots: [BuiltinModemProfile?] = load()
        slots[slot] = profile
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(File(slots: slots)).write(to: url, options: .atomic)
        } catch {
            throw .io(error.localizedDescription)
        }
    }
}
