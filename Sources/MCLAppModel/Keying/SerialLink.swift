import Foundation
import MCLCore

/// A text serial device of the digital modes (an external TU/TNC, TinyFSK): writes on the keyer lane, and a reader
/// thread collects what the device sends (a TNC's decoded text) until `take()` drains it. Closing stops the reader.
final class SerialLink: @unchecked Sendable {

    /// A received text larger than this drops its oldest part (a chatty device must not grow memory).
    static let maxPending = 16 * 1024

    let path: String
    private let transport: any ByteTransport
    private let lock = NSLock()
    private var pending: [UInt8] = []
    private var closed = false

    init(path: String, transport: any ByteTransport) {
        self.path = path
        self.transport = transport
        let thread = Thread { [self] in readLoop() }
        thread.name = "digital-serial"
        thread.start()
    }

    func write(_ bytes: [UInt8]) throws {
        guard !bytes.isEmpty else { return }
        try transport.write(bytes)
    }

    /// What arrived since the last call, as text (CR LF → LF, other control characters dropped).
    func take() -> String {
        let bytes: [UInt8] = lock.withLock {
            let all = pending
            pending.removeAll()
            return all
        }
        var out: String = ""
        for byte in bytes {
            switch byte {
            case 0x0A: out.append("\n")
            case 0x20..<0x7F: out.append(Character(Unicode.Scalar(byte)))
            default: continue
            }
        }
        return out
    }

    func close() {
        lock.withLock { closed = true }
        try? transport.close()
    }

    private func readLoop() {
        while true {
            if lock.withLock({ closed }) {
                return
            }
            guard let byte = try? transport.read(), byte >= 0 else {
                return
            }
            lock.withLock {
                pending.append(UInt8(byte))
                if pending.count > Self.maxPending {
                    pending.removeFirst(pending.count - Self.maxPending)
                }
            }
        }
    }
}
