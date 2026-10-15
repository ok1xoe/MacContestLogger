import Foundation
import Testing
@testable import MCLCore

/// The Winkeyer setup (`CwKeyingOptions.winkeyerCommands`), its persistence inside `CwKeyerConfig` and
/// `WinkeyerKeyer.configure` with the speed pot followed. In-memory transports only.
@Suite(.ioSafetyNet) struct WinkeyerSetupTests {

    // MARK: - commands

    @Test func nothingIsSentUnlessChosen() {
        var options = CwKeyingOptions()
        options.weight = 60
        options.wkKeyMode = .ultimatic
        #expect(options.winkeyerCommands().isEmpty)
    }

    @Test func defaultSetupBytes() {
        var options = CwKeyingOptions()
        options.wkSendSettings = true
        #expect(options.winkeyerCommands() == [
            0x0E, 0x00, // mode: iambic B, nothing else
            0x09, 0x07, // pins: hang 0, KEY 1, sidetone, PTT
            0x01, 0x07, // sidetone 4000/7 = 571 Hz
            0x03, 50, // weight
            0x04, 0, 0, // PTT lead / tail
            0x05, 10, 25, 0, // pot min / range
            0x10, 0, // first extension
            0x11, 0, // keying compensation
        ])
    }

    @Test func everyOptionReachesItsByte() {
        var options = CwKeyingOptions()
        options.wkSendSettings = true
        options.wkKeyMode = .iambicA
        options.wkSwapPaddles = true
        options.wkAutospace = true
        options.contestSpacing = true
        options.wkSidetone = false
        options.wkSidetonePaddleOnly = true
        options.wkSidetoneHz = 800
        options.wkPtt = false
        options.wkHangTime = 3
        options.weight = 65
        options.wkLeadMs = 40
        options.wkTailMs = 1_200
        options.wkPotMode = .follow
        options.wkPotMinWpm = 15
        options.wkPotRangeWpm = 20
        options.wkFirstExtensionMs = 12
        options.wkKeyCompensationMs = 7
        #expect(options.winkeyerCommands() == [
            0x0E, 0x1B,
            0x09, 0x34,
            0x01, 0x85,
            0x03, 65,
            0x04, 4, 120,
            0x05, 15, 20, 0,
            0x10, 12,
            0x11, 7,
            0x07, // the pot is followed: ask for its position
        ])
    }

    @Test func keyModesMapToModeBits() {
        var options = CwKeyingOptions()
        let bits: [UInt8] = WinkeyerKeyMode.allCases.map { mode in
            options.wkKeyMode = mode
            return options.winkeyerModeRegister
        }
        #expect(bits == [0x00, 0x10, 0x20, 0x30])
    }

    @Test func valuesAreNormalised() {
        var options = CwKeyingOptions()
        options.weight = 99
        options.wkSidetoneHz = 610
        options.wkLeadMs = 9_999
        options.wkTailMs = 37
        options.wkHangTime = 9
        options.wkFirstExtensionMs = -4
        options.wkPotRangeWpm = 80
        let n = options.normalized()
        #expect(n.weight == 70)
        #expect(n.wkSidetoneHz == 571)
        #expect(n.wkLeadMs == 2_550)
        #expect(n.wkTailMs == 30)
        #expect(n.wkHangTime == 3)
        #expect(n.wkFirstExtensionMs == 0)
        #expect(n.wkPotRangeWpm == 31)
        #expect(CwKeyingOptions.winkeyerSidetones == [400, 444, 500, 571, 667, 800, 1_000, 1_333, 2_000, 4_000])
    }

    // MARK: - persistence

    @Test func optionsAreStoredFlatAndOldConfigsLoad() throws {
        var config = CwKeyerConfig()
        config.options.weight = 55
        config.options.contestSpacing = true
        config.options.wkKeyMode = .bug
        let data = try JSONEncoder().encode(config)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["weight"] as? Int == 55)
        #expect(object["wkKeyMode"] as? String == "BUG")
        #expect(object["stackMessages"] as? Bool == false)
        #expect(try JSONDecoder().decode(CwKeyerConfig.self, from: data) == config)

        let old = Data(#"{"method":"WINKEYER","winkeyerPort":"/dev/x","speed":30}"#.utf8)
        let loaded = try JSONDecoder().decode(CwKeyerConfig.self, from: old)
        #expect(loaded.options == CwKeyingOptions())
        #expect(loaded.speed == 30)

        let bad = Data(#"{"weight":5,"wkKeyMode":"NOPE"}"#.utf8)
        let fixed = try JSONDecoder().decode(CwKeyerConfig.self, from: bad)
        #expect(fixed.options.weight == 30)
        #expect(fixed.options.wkKeyMode == .iambicB)
    }

    // MARK: - WinkeyerKeyer.configure

    private static func openKeyer(_ transport: any ByteTransport, _ pipe: PipeTransport) throws -> WinkeyerKeyer {
        let keyer = WinkeyerKeyer(transport: transport)
        pipe.feed([31])
        #expect(try keyer.hostOpen(timeoutMs: 30_000) == 31)
        pipe.resetSent()
        return keyer
    }

    @Test func configureWritesTheSetup() throws {
        let pipe = PipeTransport()
        let keyer = try Self.openKeyer(pipe, pipe)
        defer {
            keyer.close()
            pipe.finish()
        }
        try keyer.configure(CwKeyingOptions(), potSpeed: nil)
        #expect(pipe.sent.isEmpty)
        var options = CwKeyingOptions()
        options.wkSendSettings = true
        try keyer.configure(options, potSpeed: nil)
        #expect(pipe.sent == options.winkeyerCommands())
    }

    @Test func followedPotReportsItsSpeed() throws {
        let pipe = PipeTransport()
        let keyer = try Self.openKeyer(pipe, pipe)
        defer {
            keyer.close()
            pipe.finish()
        }
        let seen = SpeedLog()
        // Ignored pot: nothing reported.
        pipe.feed([0x85])
        #expect(pipe.waitUntilDrained())
        var options = CwKeyingOptions()
        options.wkSendSettings = true
        options.wkPotMode = .follow
        options.wkPotMinWpm = 12
        options.wkPotRangeWpm = 20
        try keyer.configure(options, potSpeed: { seen.add($0) })
        pipe.feed([0x85, 0xC4, 0xBF])
        #expect(pipe.waitUntilDrained())
        #expect(seen.values == [17, 32]) // 12 + 5, 12 + min(63, 20)
        #expect(keyer.isBusy())
    }

    @Test func followedPotKeepsReadingThroughTimeouts() throws {
        let pipe = PipeTransport()
        let timeouts = TimeoutFirstTransport(pipe)
        let keyer = try Self.openKeyer(timeouts, pipe)
        defer {
            keyer.close()
            pipe.finish()
        }
        var options = CwKeyingOptions()
        options.wkSendSettings = true
        options.wkPotMode = .follow
        let seen = SpeedLog()
        try keyer.configure(options, potSpeed: { seen.add($0) })
        timeouts.injectTimeouts(3)
        pipe.feed([0x82])
        #expect(pipe.waitUntilDrained())
        #expect(seen.values == [12])
        #expect(!keyer.hasReaderEnded)
    }

    @Test func withoutPotTheReaderStopsOnTimeoutAsBefore() throws {
        let pipe = PipeTransport()
        let timeouts = TimeoutFirstTransport(pipe)
        let keyer = try Self.openKeyer(timeouts, pipe)
        defer {
            keyer.close()
            pipe.finish()
        }
        timeouts.injectTimeouts(1)
        pipe.feed([0xC4])
        #expect(keyer.waitForReaderEnd(timeoutMs: 30_000))
    }

    @Test func potByteSpeed() {
        #expect(WinkeyerKeyer.potSpeed(0x80, min: 10, span: 25) == 10)
        #expect(WinkeyerKeyer.potSpeed(0x80 | 30, min: 10, span: 25) == 35)
    }
}

/// Speeds reported by the pot (any thread).
final class SpeedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Int] = []

    func add(_ wpm: Int) {
        lock.withLock { list.append(wpm) }
    }

    var values: [Int] {
        lock.withLock { list }
    }
}

/// A transport whose next reads fail with the serial port's read timeout, then go to the pipe.
final class TimeoutFirstTransport: ByteTransport, @unchecked Sendable {
    private let pipe: PipeTransport
    private let lock = NSLock()
    private var pending = 0

    init(_ pipe: PipeTransport) {
        self.pipe = pipe
    }

    /// The next `count` reads time out (taking effect at the reader's next read).
    func injectTimeouts(_ count: Int) {
        lock.withLock { pending = count }
        // Wake the reader blocked in the pipe so it comes back for a timed-out read.
        pipe.feed([0x40])
    }

    func read() throws -> Int {
        let fail: Bool = lock.withLock {
            if pending > 0 {
                pending -= 1
                return true
            }
            return false
        }
        if fail {
            throw ByteTransportError(SerialPort.timeoutMessage)
        }
        return try pipe.read()
    }

    func write(_ bytes: [UInt8]) throws {
        try pipe.write(bytes)
    }

    func close() throws {
        try pipe.close()
    }
}
