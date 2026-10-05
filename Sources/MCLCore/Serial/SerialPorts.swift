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
