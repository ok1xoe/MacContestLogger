import Foundation

/// Persistence of unacknowledged outgoing QoS 1 across an application restart (Paho's
/// `MqttDefaultFilePersistence` function, custom format). A message is written **before sending** and deleted after PUBACK; a new
/// client with the same Client ID and broker resends them with DUP after CONNACK.
///
/// Format: directory `<persistenceDir>/mcl-outbox/<key>/`, where the key is `<clientId>-<serverURI>` and in both parts
/// every UTF-8 byte outside `[A-Za-z0-9]` is written as `%XX` (an unambiguous, safe name). One message = one file
/// `<16-digit sequence>-<packet number>.publish`, content = the whole PUBLISH packet in MQTT 5 encoding (without DUP); written
/// through a temporary file and a rename. Paho files (`<persistenceDir>/<clientId>-<server>/*.msg`) are neither read
/// nor deleted (a deliberate divergence from Java v1.1.1). An unreadable file is skipped on load (and left in place).
public final class MqttOutbox: @unchecked Sendable {

    public let directory: URL
    private let lock = NSLock()
    private var sequence: UInt64 = 0
    private var files: [UInt16: URL] = [:]

    static let subdirectory = "mcl-outbox"
    static let suffix = ".publish"

    public init(persistenceDir: URL, clientId: String, serverUri: String) {
        let key = "\(Self.key(clientId))-\(Self.key(serverUri))"
        directory = persistenceDir.appendingPathComponent(Self.subdirectory, isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
        // The sequence continues after existing files even without `load` (otherwise a new write would get an old sequence number).
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(Self.suffix) {
            if let head = name.split(separator: "-").first, let order = UInt64(head) {
                sequence = max(sequence, order)
            }
        }
    }

    /// Directory name: UTF-8 bytes outside `[A-Za-z0-9]` as `%XX`.
    static func key(_ text: String) -> String {
        var out = ""
        for byte in text.utf8 {
            let safe: Bool = (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
            if safe {
                out.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                out += String(format: "%%%02X", Int(byte))
            }
        }
        return out
    }

    /// Loads stored messages in storage order (Paho `restoreState`).
    public func load() -> [MqttPublish] {
        lock.lock()
        defer { lock.unlock() }
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var entries: [(order: UInt64, url: URL, message: MqttPublish)] = []
        for name in names where name.hasSuffix(Self.suffix) {
            let stem: Substring = name.dropLast(Self.suffix.count)
            let parts: [Substring] = stem.split(separator: "-")
            guard parts.count == 2, let order = UInt64(parts[0]) else { continue }
            let url: URL = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            guard case .publish(let message)? = try? MqttPacket.decode([UInt8](data)) else { continue }
            guard message.qos == 1, message.packetId != nil else { continue }
            entries.append((order, url, message))
        }
        entries.sort { $0.order < $1.order }
        files.removeAll()
        for entry in entries {
            if let id = entry.message.packetId {
                files[id] = entry.url
            }
            sequence = max(sequence, entry.order)
        }
        return entries.map(\.message)
    }

    /// Stores a message before sending (Paho `persistence.put`). Failure = Java `MqttPersistenceException`.
    public func put(_ message: MqttPublish) throws(MqttClientError) {
        guard let id = message.packetId else { return }
        var plain = message
        plain.dup = false
        let bytes: [UInt8]
        do {
            bytes = try MqttPacket.publish(plain).encode()
        } catch {
            throw MqttClientError(code: 0, cause: "\(error)")
        }
        lock.lock()
        defer { lock.unlock() }
        sequence += 1
        let name = String(format: "%016llu-%u", sequence, UInt32(id)) + Self.suffix
        let url: URL = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(bytes).write(to: url, options: .atomic)
        } catch {
            throw MqttClientError(code: 0, cause: error.localizedDescription)
        }
        if let previous = files[id], previous != url {
            try? FileManager.default.removeItem(at: previous)
        }
        files[id] = url
    }

    /// Deletes a message after PUBACK (Paho `persistence.remove`); a missing file is fine.
    public func remove(_ id: UInt16) {
        lock.lock()
        let url: URL? = files.removeValue(forKey: id)
        lock.unlock()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
