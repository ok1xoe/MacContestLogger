import Foundation
import IOKit
import IOKit.serial

/// Enumeration of the system's serial ports (Java `cat/SerialPorts` over jSerialComm `getCommPorts()`): full paths
/// `/dev/…` (a bare name would be taken by `rigctld` as a network address). IOKit `kIOSerialBSDServiceValue` (all
/// types), per device in IOKit order and for each **`cu` (callout), then `tty` (dialin)** — the shape measured on
/// jSerialComm 2.11 (`[…/cu.X, …/tty.X, …/cu.Y, …/tty.Y]`). Only reads the registry, opens nothing.
public enum SerialPorts {

    public static func available() -> [String] {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else {
            return []
        }
        let dict = matching as NSMutableDictionary
        dict[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var paths: [String] = []
        while true {
            let service: io_object_t = IOIteratorNext(iterator)
            if service == 0 {
                break
            }
            if let callout = property(service, kIOCalloutDeviceKey) {
                paths.append(callout)
            }
            if let dialin = property(service, kIODialinDeviceKey) {
                paths.append(dialin)
            }
            IOObjectRelease(service)
        }
        return paths
    }

    private static func property(_ service: io_object_t, _ key: String) -> String? {
        let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? String
    }
}

/// N1MM's COM port list marks a port that was configured but cannot be found now (an unplugged USB adapter, a
/// virtual port whose software is not running) with an asterisk.
public enum SerialPortChoice {

    /// `port` is set but not among the `available` ones.
    public static func isMissing(_ port: String, available: [String]) -> Bool {
        let trimmed: String = port.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !available.contains(trimmed)
    }

    /// The drop-down label: `* <port>` for a missing port, otherwise the port.
    public static func label(_ port: String, available: [String]) -> String {
        isMissing(port, available: available) ? "* " + port : port
    }
}
