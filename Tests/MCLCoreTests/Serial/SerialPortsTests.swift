import Testing
@testable import MCLCore

/// `SerialPorts.available()` only reads the IOKit registry. This Mac's device names are written nowhere — the test
/// verifies only the shape (full paths, per `cu` device and right after it `tty` of the same name).
@Suite struct SerialPortsTests {

    @Test func listingHasCalloutDialinPairs() {
        let ports = SerialPorts.available()
        #expect(ports.count % 2 == 0)
        for i in stride(from: 0, to: ports.count - 1, by: 2) {
            let cu = ports[i]
            let tty = ports[i + 1]
            #expect(cu.hasPrefix("/dev/cu."))
            #expect(tty.hasPrefix("/dev/tty."))
            #expect(cu.dropFirst("/dev/cu.".count) == tty.dropFirst("/dev/tty.".count))
        }
    }
}
