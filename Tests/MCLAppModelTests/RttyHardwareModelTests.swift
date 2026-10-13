import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// RTTY through hardware (N1MM „Default RTTY Interface"): TinyFSK and a TU/TNC on fake serial ports, WinKeyer 3.1
/// through the fake keyer; the lamp, Esc and a TNC's decoded text in the Digital Interface. Nothing real is opened.
@MainActor @Suite struct RttyHardwareModelTests {

    /// An in-memory serial port: records writes, `read` waits for fed bytes or the close.
    final class FakeSerial: ByteTransport, @unchecked Sendable {
        private let condition = NSCondition()
        private var incoming: [UInt8] = []
        private var written: [UInt8] = []
        private var closed = false

        var sent: [UInt8] { condition.withLock { written } }

        func feed(_ text: String) {
            condition.withLock {
                incoming += Array(text.utf8)
                condition.broadcast()
            }
        }

        func read() throws -> Int {
            condition.lock()
            defer { condition.unlock() }
            while incoming.isEmpty && !closed {
                condition.wait()
            }
            if closed {
                return -1
            }
            return Int(incoming.removeFirst())
        }

        func write(_ bytes: [UInt8]) throws {
            condition.withLock { written += bytes }
        }

        func close() throws {
            condition.withLock {
                closed = true
                condition.broadcast()
            }
        }
    }

    final class Ports: @unchecked Sendable {
        let serial = FakeSerial()
        private let lock = NSLock()
        private var opened: [String] = []
        var paths: [String] { lock.withLock { opened } }
        func open(_ path: String) -> FakeSerial {
            precondition(path.hasPrefix("/dev/fake-"), "tests open fake ports only")
            lock.withLock { opened.append(path) }
            return serial
        }
    }

    private static func make(_ ports: Ports, configure: @escaping (inout AppConfig) -> Void) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            config.station.call = "OK1XOE"
            winkeyerConfig(&config)
            config.digital.runMessages[0] = FunctionKeyMessage(label: "CQ", text: "CQ TEST *")
            config.digital.spMessages[0] = FunctionKeyMessage(label: "CQ", text: "CQ TEST *")
            configure(&config)
        }, adjust: { environment in
            environment.hardware.openSerial = { path, _ in ports.open(path) }
        })
        app.entry.setMode(.rtty)
        app.entry.setFrequency("14080")
        return app
    }

    @Test func tinyFskFramesTheMessageAndEscAborts() async throws {
        let ports = Ports()
        let app = try await Self.make(ports) { config in
            config.digital.rttyInterface = RttyInterface.tinyFsk.rawValue
            config.digital.tinyFskPort = "/dev/fake-tinyfsk"
        }
        #expect(app.entry.digitalReady, "RTTY through TinyFSK needs no fldigi")
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        #expect(String(decoding: ports.serial.sent, as: UTF8.self) == "[ CQ TEST OK1XOE ]")
        #expect(app.keyer.digitalSending)
        #expect(app.entry.stopSending())
        await app.settle()
        #expect(ports.serial.sent.last == TinyFsk.abort)
        #expect(!app.keyer.digitalSending)
        // A message runs out by the estimate (the keyer does not report its end).
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        #expect(app.keyer.digitalSending)
        app.clock.advance(by: BaudotText.durationMs(" CQ TEST OK1XOE "))
        await app.settle()
        #expect(!app.keyer.digitalSending)
        #expect(ports.paths == ["/dev/fake-tinyfsk"])
    }

    @Test func tncWrapsWithItsCommandsAndDecodes() async throws {
        let ports = Ports()
        let app = try await Self.make(ports) { config in
            config.digital.rttyInterface = RttyInterface.tnc.rawValue
            config.digital.tncType = TncType.pk232.rawValue
            config.digital.tncPort = "/dev/fake-pk232"
        }
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        #expect(ports.serial.sent == [0x58, 0x0D] + Array(" CQ TEST OK1XOE ".utf8) + [0x04])
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        ports.serial.feed("CQ DE DL1ABC DL1ABC K\r\n")
        // The reader thread takes the bytes in its own time: poll until they are shown (no clock involved).
        for _ in 0..<2_000 where !digital.text.contains("DL1ABC") {
            app.radioClock.advance(by: 300)
            await app.settle()
            await Task.yield()
        }
        #expect(digital.text.contains("DL1ABC"))
        #expect(digital.status == "TNC · /dev/fake-pk232")
        #expect(app.entry.stopSending())
        await app.settle()
        #expect(Array(ports.serial.sent.suffix(6)) == TncCommands.bytes("{CTRL-C}R{ENTER}TC{ENTER}"))
        digital.close()
    }

    @Test func winkeyerSendsRtty() async throws {
        let ports = Ports()
        let app = try await Self.make(ports) { config in
            config.digital.rttyInterface = RttyInterface.winkeyer.rawValue
        }
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        #expect(app.keying.lastKeyer?.events.contains("rtty CQ TEST OK1XOE") == true)
        #expect(app.entry.stopSending())
        await app.settle()
        #expect(app.keying.lastKeyer?.events.last == "rtty raw 5C")
        #expect(ports.paths.isEmpty)
    }
}
