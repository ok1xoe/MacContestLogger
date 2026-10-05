import Foundation
import Testing
@testable import MCLCore

/// Port of `keyer/WinkeyerKeyerTest` (9) + `WK.bytes` measurements (maintainer-only probe) and `KWK.*`,
/// `KWKR.*`, `KWKE.*` (maintainer-only probe). The transport is the `PipeTransport` stand-in (a pair of pipes
/// like Java `PipedInputStream`/`ByteArrayOutputStream`); no serial port.
///
/// Without fixed time bounds: incoming bytes are awaited via `waitUntilDrained` /
/// `waitUntilEnded` of the stand-in (the state of the reader thread, not time). `hostOpen` has a timeout only as a guard
/// (generous where the version arrives; short only where the timeout is tested).
@Suite(.ioSafetyNet) struct WinkeyerKeyerTests {

    private static let ctx = CwMessageBuilder.Context(
        myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 7, rst: "599", exchange: "15",
        cutNumbers: false, leadingZeros: false)

    private static func build(_ template: String) -> CwMessage {
        CwMessageBuilder.build(template, ctx)
    }

    /// Java `setUp`/`tearDown`: the key over a pipe, at the end `close` (+ end of stream for the reader thread).
    private static func withKeyer(_ body: (PipeTransport, WinkeyerKeyer) throws -> Void) rethrows {
        let pipe = PipeTransport()
        let keyer = WinkeyerKeyer(transport: pipe)
        defer {
            keyer.close()
            pipe.finish()
        }
        try body(pipe, keyer)
    }

    /// Java `open()`: version 31 in the reply to host open, then clear the recorded bytes.
    private static func open(_ pipe: PipeTransport, _ keyer: WinkeyerKeyer) throws {
        pipe.feed([31])
        #expect(try keyer.hostOpen(timeoutMs: 30_000) == 31)
        pipe.resetSent()
    }

    private static func ascii(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    // MARK: - Port of WinkeyerKeyerTest

    @Test func hostOpenSendsAdminCommandAndReadsVersion() throws {
        try Self.withKeyer { pipe, keyer in
            pipe.feed([31])

            let version = try keyer.hostOpen(timeoutMs: 30_000)
            #expect(version == 31)
            #expect(pipe.sent == [0x00, 0x02])
            #expect(keyer.name() == "Winkeyer v31")
        }
    }

    /// The expiry of `hostOpen` (100 ms) is awaited on its own thread, not on a shared pool thread.
    @Test func silentKeyerFailsToOpen() async {
        let pipe = PipeTransport()
        let keyer = WinkeyerKeyer(transport: pipe)
        let result: Result<Int, any Error> = await onOwnThread("winkeyer-test") {
            Result { try keyer.hostOpen(timeoutMs: 100) }
        }
        keyer.close()
        pipe.finish()
        #expect(throws: CwKeyerError(.io, "Winkeyer neodpovídá (žádná verze po host open)")) {
            try result.get()
        }
    }

    @Test func plainTextIsSentAsAscii() throws {
        try Self.withKeyer { pipe, keyer in
            try Self.open(pipe, keyer)
            try keyer.send(Self.build("tu *"), wpm: 28)

            #expect(pipe.sent == Self.ascii("TU OK1XOE"))
        }
    }

    @Test func prosignIsMergedCharacterPair() throws {
        try Self.withKeyer { pipe, keyer in
            try Self.open(pipe, keyer)
            try keyer.send(Self.build("tu+"), wpm: 28)

            #expect(pipe.sent == [0x54, 0x55, 0x1B, 0x41, 0x52])
        }
    }

    @Test func speedChangesAreBufferedAndCancelledAtTheEnd() throws {
        try Self.withKeyer { pipe, keyer in
            try Self.open(pipe, keyer)
            try keyer.send(Self.build("<<5nn>>{EXCH}"), wpm: 28)

            let expected: [UInt8] = [0x1C, 30, 0x1C, 32, 0x35, 0x4E, 0x4E, 0x1C, 30, 0x1C, 28, 0x31, 0x35, 0x1E]
            #expect(pipe.sent == expected)
        }
    }

    @Test func speedAbortAndClose() throws {
        try Self.withKeyer { pipe, keyer in
            try Self.open(pipe, keyer)
            try keyer.setSpeed(32)
            try keyer.abort()
            keyer.close()

            #expect(pipe.sent == [0x02, 32, 0x0A, 0x00, 0x03])
        }
    }

    @Test func tuneUsesKeyImmediate() throws {
        try Self.withKeyer { pipe, keyer in
            try Self.open(pipe, keyer)
            try keyer.tune(true)
            try keyer.tune(false)

            #expect(pipe.sent == [0x0B, 1, 0x0B, 0])
        }
    }

    @Test func speedIsClampedToWinkeyerRange() {
        #expect(WinkeyerKeyer.clampWpm(1) == 5)
        #expect(WinkeyerKeyer.clampWpm(150) == 99)
    }

    @Test func statusByteTracksBusy() throws {
        try Self.withKeyer { pipe, keyer in
            try Self.open(pipe, keyer)
            pipe.feed([0xC4]) // status: transmitting
            #expect(pipe.waitUntilDrained())
            #expect(keyer.isBusy())
            pipe.feed([0x54]) // echo of a character does not change the status
            pipe.feed([0x9C]) // the potentiometer neither
            #expect(pipe.waitUntilDrained())
            #expect(keyer.isBusy())
            pipe.feed([0xC0]) // status: idle
            #expect(pipe.waitUntilDrained())
            #expect(!keyer.isBusy())
        }
    }

    // MARK: - Measurement: outgoing bytes

    /// The key over a pipe without incoming bytes (Java `ByteArrayInputStream(new byte[0])`): the reader thread ends
    /// at once, the version stays −1.
    private static func silentKeyer() -> (PipeTransport, WinkeyerKeyer) {
        let pipe = PipeTransport(endOfStream: true)
        return (pipe, WinkeyerKeyer(transport: pipe))
    }

    /// `WK.bytes` (research): `send`, then `setSpeed`, `tune(true)`, `abort`, `close`, `close` at 28/3/120 WPM —
    /// `1C` cumulatively with clamping 5–99 at each step, `1E` if the message has any change (even `<>`),
    /// an empty message nothing, a second `close` nothing.
    @Test func measuredResearchBytes() throws {
        let templates = ["tu *", "tu+", "<<5nn>>{EXCH}", "<", "{LOG}", "", String(repeating: ">", count: 80) + "x",
                         String(repeating: "<", count: 95) + "x", "]", "<>x"]
        var rows: [String] = []
        for template in templates {
            for wpm in [28, 3, 120] {
                let (pipe, keyer) = Self.silentKeyer()
                try keyer.send(Self.build(template), wpm: wpm)
                let sent = pipe.sent
                try keyer.setSpeed(wpm)
                try keyer.tune(true)
                try keyer.abort()
                keyer.close()
                keyer.close()
                let rest = Array(pipe.sent[sent.count...])
                rows.append(ProbeText.row("WK.bytes", [ProbeText.esc(template), String(wpm), KeyerProbe.hex(sent),
                                                         KeyerProbe.hex(rest), keyer.name()]))
            }
        }
        #expect(rows.count == 30)
        #expect(ProbeText.digest(rows) == "37acf080634f98711e33dad8209ce2440908e9531b0eb74d9bc6e58d7ca2bc8a")
        #expect(rows[24] == "WK.bytes\t]\t28\t1b534b\t021c0b010a0003\tWinkeyer")
    }

    /// `KWK.bytes`: further templates (NBSP, Czech letters dropped by assembly, prosigns, `<>`, `{F1}` without
    /// F-keys = nothing) at 3/28/120 and extreme speeds −1, 0, 5, 99, 100; `busy` after sending.
    @Test func measuredMoreBytes() throws {
        let templates = ["cq test *", "a\u{00A0}b", "\u{017E}lu\u{0165}ou\u{010D}k\u{00FD} k\u{016F}\u{0148}", "5nn/p.,?-",
                         "]+[=", "<<<>>>", "><", "<>", "<x>", "{EXCH}<{EXCH}>{EXCH}", "{F1}", "~"]
        var rows: [String] = []
        for template in templates {
            for wpm in [3, 28, 120, -1, 0, 5, 99, 100] {
                let (pipe, keyer) = Self.silentKeyer()
                try keyer.send(Self.build(template), wpm: wpm)
                let sent = pipe.sent
                try keyer.setSpeed(wpm)
                keyer.close()
                let rest = Array(pipe.sent[sent.count...])
                rows.append(ProbeText.row("KWK.bytes", [ProbeText.esc(template), String(wpm), KeyerProbe.hex(sent),
                                                          KeyerProbe.hex(rest), String(keyer.isBusy())]))
            }
        }
        #expect(rows.count == 96)
        #expect(ProbeText.digest(rows) == "0fbd0935c5f870742fb327c029a39059d85ffe66f7d2c104e822fd7c7a5a651c")
    }

    /// `KWK.parts`: directly assembled messages — `getBytes(US_ASCII)` by code points (`😀` = one `?`,
    /// `é` + U+0301 = `??`, U+0000 and U+007F pass), a prosign from only two UTF-16 units (the lower byte of each),
    /// empty text nothing and `busy` stays, `Speed(0)` = `1C wpm 1E`, `int` overflow of a speed sum.
    @Test func measuredDirectParts() throws {
        let max = Int(Int32.max)
        let cases: [[CwMessage.Part]] = [
            [.text("\u{017E}a\u{1F600}b\u{00A0}c")], [.text("\u{FFFD}x\u{FFFD}")], [.text("caf\u{00E9}\u{0301}")],
            [.prosign("SOS")], [.prosign("A")], [.prosign("")], [.prosign("\u{017D}\u{0101}")], [.prosign("\u{1F600}")],
            [.text("")], [.speed(0)], [.speed(max), .speed(1)], [.speed(-1000), .text("E")],
            [.text("\u{0000}\u{007F}\u{0080}\u{00FF}")],
        ]
        var rows: [String] = []
        for parts in cases {
            for wpm in [28, max] {
                let (pipe, keyer) = Self.silentKeyer()
                try keyer.send(CwMessage(parts: parts), wpm: wpm)
                rows.append(ProbeText.row("KWK.parts", [ProbeText.esc(KeyerProbe.parts(CwMessage(parts: parts))),
                                                          String(wpm), KeyerProbe.hex(pipe.sent),
                                                          String(keyer.isBusy())]))
                keyer.close()
            }
        }
        // A row with lone surrogate units (`\uD800x\uDC00`) cannot be carried by a Swift `String` — here
        // U+FFFD; the bytes (`3f783f`) are the same, only the escaped description of the part differs. So the
        // fingerprint without these two rows + their bytes separately is compared.
        #expect(rows[2] == "KWK.parts\t[T'\\uFFFDx\\uFFFD']\t28\t3f783f\ttrue")
        rows.removeSubrange(2...3)
        #expect(ProbeText.digest(rows) == "07f7de64bce8d4b267f566801ead724d58c60af58e265fce54e29fdf58a4f4ae")
    }

    /// `KWK.clamp`: `clampWpm` and the bytes of `setSpeed` + `tune` for extreme speeds.
    @Test func measuredClamp() throws {
        let values = [Int(Int32.min), -1, 0, 4, 5, 6, 98, 99, 100, 255, 256, Int(Int32.max)]
        var rows: [String] = []
        for w in values {
            let (pipe, keyer) = Self.silentKeyer()
            try keyer.setSpeed(w)
            try keyer.tune(w > 0)
            rows.append(ProbeText.row("KWK.clamp", [String(w), String(WinkeyerKeyer.clampWpm(w)),
                                                      KeyerProbe.hex(pipe.sent)]))
            keyer.close()
        }
        #expect(ProbeText.digest(rows) == "3d7b349ae8994463c16b9e96f7d00162c6448da3a3b8ec0dc5bdb1a206a3d2c1")
    }

    // MARK: - Measurement: read side

    /// `KWKR.read`: incoming bytes up to the end of the stream, then `hostOpen` (50 ms). The first byte is the version — both the status
    /// `C4` (`Winkeyer v196`) and `0` (`Winkeyer`, `hostOpen` returns 0); the status only from 0xC0–0xFF, the last wins.
    @Test func measuredReaderSide() async {
        let inputs: [[UInt8]] = [
            [], [31], [0], [0xC4], [0xC4, 0xC0], [31, 0xC4], [31, 0xC4, 0x54, 0x9C], [31, 0xC4, 0xC0], [31, 0xC4, 0xFB],
            [31, 0xC4, 0xBF], [31, 0x04], [31, 0xC0, 0xC7], [0xFF], [23, 0xFF, 0x80], [31, 0xC4, 0xC0, 0xCC],
        ]
        // Waiting for the reader thread and the expiry of `hostOpen` (15× 50 ms) on its own thread, not in the pool.
        let (rows, allEnded): ([String], Bool) = await onOwnThread("winkeyer-test") {
            var rows: [String] = []
            var allEnded = true
            for input in inputs {
                let pipe = PipeTransport(incoming: input, endOfStream: true)
                let keyer = WinkeyerKeyer(transport: pipe)
                allEnded = pipe.waitUntilEnded() && allEnded
                let open = KeyerProbe.safe { String(try keyer.hostOpen(timeoutMs: 50)) }
                rows.append(ProbeText.row("KWKR.read", [KeyerProbe.hex(input), ProbeText.esc(open), keyer.name(),
                                                          String(keyer.isBusy()), KeyerProbe.hex(pipe.sent)]))
                keyer.close()
            }
            return (rows, allEnded)
        }
        #expect(allEnded)
        #expect(ProbeText.digest(rows) == "16b12348143f139ee29697dc3fcb2d6457a98e44c4cd10eabcde9dbebff5bdeb")
        #expect(rows[3] == "KWKR.read\tc4\t196\tWinkeyer v196\tfalse\t0002")
    }

    /// `KWKR.busy`: `send` sets `busy` only when it sends something, `abort` clears it, `tune`/`setSpeed` do not.
    @Test func measuredBusyWithoutStatusBytes() throws {
        let pipe = PipeTransport(incoming: [31, 0xC0], endOfStream: true)
        let keyer = WinkeyerKeyer(transport: pipe)
        #expect(pipe.waitUntilEnded())
        var states = [keyer.isBusy()]
        try keyer.send(Self.build("{LOG}"), wpm: 28)
        states.append(keyer.isBusy())
        try keyer.send(Self.build("<"), wpm: 28)
        states.append(keyer.isBusy())
        try keyer.abort()
        states.append(keyer.isBusy())
        try keyer.send(Self.build("e"), wpm: 28)
        states.append(keyer.isBusy())
        try keyer.tune(true)
        try keyer.setSpeed(20)
        states.append(keyer.isBusy())
        #expect(states == [false, false, true, false, true, true])
        #expect(KeyerProbe.hex(pipe.sent) == "1c1e1e0a450b010214")
        keyer.close()
    }

    // MARK: - Measurement: errors

    final class EventLog: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []

        func add(_ item: String) {
            lock.lock()
            items.append(item)
            lock.unlock()
        }

        var joined: String {
            lock.lock()
            defer { lock.unlock() }
            return items.joined(separator: " | ")
        }
    }

    private static func ok(_ body: () throws -> Void) -> String {
        KeyerProbe.safe {
            try body()
            return "ok"
        }
    }

    /// `KWKE.fail`: a failed write → `UncheckedIOException("Zápis do Winkeyeru selhal: <message|null>")`;
    /// `busy` stays `true` (set before the write, `abort` does not clear it after an error); an empty message does not write;
    /// `close` swallows the error, closes the port, a second `close` nothing. Six write attempts.
    @Test(arguments: [("Port zavřen" as String?, "Port zavřen"), (nil, "null")])
    func measuredWriteFailures(message: String?, shown: String) throws {
        let log = EventLog()
        let pipe = PipeTransport(endOfStream: true)
        pipe.writeFailure = ByteTransportError(message)
        pipe.onClose = { log.add("port.close") }
        let keyer = WinkeyerKeyer(transport: pipe)
        log.add("send: " + Self.ok { try keyer.send(Self.build("e"), wpm: 28) })
        log.add("busy=" + String(keyer.isBusy()))
        log.add("empty: " + Self.ok { try keyer.send(Self.build("{LOG}"), wpm: 28) })
        log.add("speed: " + Self.ok { try keyer.setSpeed(20) })
        log.add("abort: " + Self.ok { try keyer.abort() })
        log.add("busy=" + String(keyer.isBusy()))
        log.add("tune: " + Self.ok { try keyer.tune(true) })
        log.add("open: " + KeyerProbe.safe { String(try keyer.hostOpen(timeoutMs: 10)) })
        log.add("close: " + Self.ok { keyer.close() })
        log.add("close2: " + Self.ok { keyer.close() })
        log.add("writes=" + String(pipe.writeAttempts))
        let error = "EXC UncheckedIOException: Zápis do Winkeyeru selhal: " + shown
        let expected = "send: \(error) | busy=true | empty: ok | speed: \(error) | abort: \(error) | busy=true"
            + " | tune: \(error) | open: \(error) | port.close | close: ok | close2: ok | writes=6"
        #expect(log.joined == expected)
    }

    /// `KWKE.closeThrows`: an error while closing the port is swallowed; a write after `close` still goes through (Java does not
    /// block it), a name without a version.
    @Test func measuredCloseFailure() throws {
        let log = EventLog()
        let pipe = PipeTransport(endOfStream: true)
        pipe.closeFailure = ByteTransportError("už zavřeno")
        pipe.onClose = { log.add("port.close") }
        let keyer = WinkeyerKeyer(transport: pipe)
        log.add("close: " + Self.ok { keyer.close() })
        log.add("send po close: " + Self.ok { try keyer.send(Self.build("e"), wpm: 28) })
        log.add("name=" + keyer.name())
        #expect(log.joined == "port.close | close: ok | send po close: ok | name=Winkeyer")
        #expect(KeyerProbe.hex(pipe.sent) == "000345")
    }

    // MARK: - Opening over a transport (new, without a Java ancestor)

    /// Java `open` without a serial port: host open, speed; with a silent key it closes the transport and passes on the error.
    @Test func openOverTransportSendsHostOpenAndSpeed() async throws {
        let pipe = PipeTransport(incoming: [31])
        let keyer = try WinkeyerKeyer.open(transport: pipe, wpm: 120, timeoutMs: 30_000)
        #expect(keyer.name() == "Winkeyer v31")
        #expect(pipe.sent == [0x00, 0x02, 0x02, 99])
        keyer.close()
        #expect(pipe.closeCount == 1)

        let silent = PipeTransport()
        // expiry of host open (50 ms) on its own thread, not in the pool
        let opened: Result<WinkeyerKeyer, any Error> = await onOwnThread("winkeyer-test") {
            Result { try WinkeyerKeyer.open(transport: silent, wpm: 28, timeoutMs: 50) }
        }
        #expect(throws: CwKeyerError(.io, "Winkeyer neodpovídá (žádná verze po host open)")) {
            _ = try opened.get()
        }
        #expect(silent.sent == [0x00, 0x02, 0x00, 0x03])
        #expect(silent.closeCount == 1)
    }
}
