import Foundation
@testable import MCLCore

/// The format of the maintainer-only probe (`RadioIoProbeRows`): values escaped
/// by UTF-16 (`\uXXXX` outside printable ASCII and for `\`), exceptions `EXC <Java class>: <message>`.
enum RadioIoProbe {

    static func row(_ key: String) -> String? {
        RadioIoProbeRows.rows[key]
    }

    static func esc(_ text: String) -> String {
        var out = ""
        for unit in text.utf16 {
            if unit >= 0x20 && unit < 0x7F && unit != 0x5C {
                out += String(UnicodeScalar(UInt8(unit)))
            } else {
                out += "\\u" + String(format: "%04X", Int(unit))
            }
        }
        return out
    }

    /// Java `"EXC " + getClass().getName() + ": " + getMessage()`. Swift errors do not carry the cause (`<- …`) —
    /// the probe row is compared without it (`withoutCause`).
    static func exc(_ error: any Error) -> String {
        switch error {
        case let e as JavaSocketError:
            return "EXC " + e.javaClass + ": " + (e.message ?? "null")
        case let e as JavaIOError:
            return "EXC " + e.javaClass + ": " + (e.message ?? "null")
        case let e as JavaIllegalArgumentError:
            return "EXC java.lang.IllegalArgumentException: " + e.message
        case let e as JavaNumberFormatError:
            return "EXC java.lang.NumberFormatException: " + e.message
        case let e as XmlRpc.Failure:
            return "EXC java.lang.IllegalStateException: " + e.message
        case let e as CwKeyerError:
            return "EXC java.io.IOException: " + e.message
        case let e as SerialPortInvalidPortError:
            return "EXC com.fazecast.jSerialComm.SerialPortInvalidPortException: " + e.message
        default:
            return "EXC " + String(describing: error)
        }
    }

    /// The result of an action as the probe (`ok` for `Void`, otherwise the value, on error `exc`).
    static func result(_ action: () throws -> String) -> String {
        do {
            return try action()
        } catch {
            return exc(error)
        }
    }

    /// A probe row without ` <- cause`.
    static func withoutCause(_ row: String?) -> String? {
        guard let row else { return nil }
        guard let range = row.range(of: " <- ") else { return row }
        return String(row[..<range.lowerBound])
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}
