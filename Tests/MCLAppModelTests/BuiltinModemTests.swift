import Foundation
@testable import MCLAppModel
@testable import MCLCore
import RTTYSignalKit
import Testing

/// The built-in RTTY modem behind the Digital Interface (N1MM's embedded MMTTY): receive from the shared receiver
/// audio, transmit through the fake sound output with the TX watch, Esc, and the two receivers (independent or linked
/// tuning). Synthetic audio into a deviceless capture; the transmit audio is pulled by the test; nothing real opens.
@MainActor @Suite struct BuiltinModemTests {

    static func rtty(_ text: String, markHz: Double = 2125) -> [Double] {
        RTTYSignalGenerator(sampleRate: BuiltinRttyChannel.sampleRate, markHz: markHz, amplitude: 0.3)
            .generate(text: text).map { Double($0) }
    }

    private static func make(configure: @escaping (inout AppConfig) -> Void = { _ in }) async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            config.digital.engine = .builtin
            config.station.call = "OK1XOE"
            configure(&config)
        })
        app.entry.setMode(.rtty)
        app.entry.setFrequency("14080")
        return app
    }

    private static func poll(_ app: KeyingApp) async {
        app.radioClock.advance(by: 300)
        await app.settle()
    }

    /// Pulls the transmit audio until the transmission has ended (the output stopped).
    private static func drain(_ app: KeyingApp, _ stream: FakeModemStream) -> [Float] {
        var audio: [Float] = []
        for _ in 0..<200 where !stream.isStopped {
            audio += stream.pull(6_000)
            app.model.keyer.lane.builtin.settle()
        }
        return audio
    }

    @Test func decodesTheReceiverAudioIntoTheDigitalInterface() async throws {
        let app = try await Self.make()
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.model.builtinModem.attach(0)
        await app.settle()
        #expect(app.model.audio.userNames == ["rtty"])
        try RadioSignals.feed(app, Self.rtty("CQ TEST DL1ABC DL1ABC K\r\n"))
        await Self.poll(app)
        #expect(digital.text.contains("CQ TEST DL1ABC DL1ABC K"), "\(digital.text)")
        #expect(digital.status.contains("RTTY"))
        #expect(digital.recentCalls == ["DL1ABC"])
        #expect(digital.frequencyCaption.contains("2210 Hz"), "fldigi's carrier is the centre: \(digital.frequencyCaption)")
        digital.close()
        #expect(app.model.audio.userNames.isEmpty)
        await app.settle()
        #expect(!app.model.audio.capture.isRunning)
    }

    /// One stereo input, two stations: receiver 1 decodes the left channel, receiver 2 the right one, each in its
    /// own Digital Interface (and a click goes to that radio's entry window).
    @Test func stereoInputLeftToReceiver1RightToReceiver2() async throws {
        let app = try await Self.make()
        let di1: DigitalInterfaceModel = app.model.makeDigitalInterface()
        let di2: DigitalInterfaceModel = app.model.makeDigitalInterface(index: 1)
        di1.open()
        di2.open()
        await app.model.builtinModem.attach(0)
        await app.model.builtinModem.attach(1)
        await app.settle()
        #expect(app.model.audio.userNames == ["rtty", "rtty2"])
        let left: [Double] = Self.rtty("CQ TEST DL1ABC DL1ABC K\r\n")
        let right: [Double] = Self.rtty("CQ TEST W1AW W1AW K\r\n")
        var pcm: [UInt8] = []
        for (l, r) in zip(RadioSignals.pcm(left).chunked(2), RadioSignals.pcm(right).chunked(2)) {
            pcm += l + r
        }
        let generation: UInt64 = try #require(app.keying.lastAudioGeneration)
        app.model.audio.capture.acceptStereo(pcm, generation: generation)
        await Self.poll(app)
        #expect(di1.text.contains("DL1ABC") && !di1.text.contains("W1AW"), "\(di1.text)")
        #expect(di2.text.contains("W1AW") && !di2.text.contains("DL1ABC"), "\(di2.text)")
        di1.close()
        di2.close()
        #expect(app.model.audio.userNames.isEmpty)
    }

    @Test func transmitsThroughTheSoundOutputAndReturnsToReceive() async throws {
        let app = try await Self.make()
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        app.keyer.digital.send("CQ TEST OK1XOE", key: 0)
        await app.settle()
        #expect(app.keyer.digitalSending)
        let stream: FakeModemStream = try #require(app.keying.modemOutputs.first)
        #expect(app.keying.events.contains("modem output - 12000"))
        #expect(app.model.builtinModem.channel(0).trxState == "TX")
        // The window polls while the modem transmits: the echo of the own text is marked as transmitted.
        var audio: [Float] = stream.pull(24_000)
        await Self.poll(app)
        #expect(!digital.transmittedRanges.isEmpty, "\(digital.text)")
        audio += Self.drain(app, stream)
        #expect(stream.isStopped)
        #expect(app.model.builtinModem.channel(0).trxState == "RX")
        let decoder = BuiltinRttyChannel()
        decoder.receive((audio + [Float](repeating: 0, count: 6_000)).map { Double($0) })
        #expect(decoder.rxText(start: 0, length: decoder.rxLength).contains("CQ TEST OK1XOE"))
        for _ in 0..<3 {
            app.clock.advance(by: 500)
            await app.settle()
        }
        #expect(!app.keyer.digitalSending, "the TX watch saw the modem back on receive")
        // The own text came back as the echo, dimmed and never grabbed.
        await Self.poll(app)
        #expect(digital.text.contains("CQ TEST OK1XOE"), "\(digital.text)")
        digital.close()
    }

    /// F1 in RTTY goes out through the built-in modem with its macros; Op Mode switches the speed; a PSK modem name
    /// is refused (the built-in modem has only RTTY).
    @Test func functionKeysAndOpMode() async throws {
        let app = try await Self.make { config in
            config.digital.runMessages[0] = FunctionKeyMessage(label: "CQ", text: "CQ TEST * TEST")
            config.digital.spMessages[0] = FunctionKeyMessage(label: "CQ", text: "CQ TEST * TEST")
        }
        let digital: DigitalInterfaceModel = app.model.makeDigitalInterface()
        digital.open()
        await app.settle()
        #expect(digital.opModes.common == ["RTTY"], "\(digital.opModes)")
        digital.selectModem("RTTY-75")
        await app.settle()
        #expect(app.status == "Vestavěný modem: mód RTTY-75")
        #expect(app.model.builtinModem.channel(0).tuning.baud == 75)
        digital.selectModem("BPSK31")
        await app.settle()
        #expect(app.status.contains("only RTTY"), "\(app.status)")
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        let stream: FakeModemStream = try #require(app.keying.modemOutputs.first)
        let audio: [Float] = Self.drain(app, stream)
        let decoder = BuiltinRttyChannel()
        try decoder.setMode("RTTY-75")
        decoder.receive((audio + [Float](repeating: 0, count: 6_000)).map { Double($0) })
        #expect(decoder.rxText(start: 0, length: decoder.rxLength).contains("CQ TEST OK1XOE TEST"))
        digital.close()
    }

    /// `{PROFILEn}` switches the transmitting receiver's profile before the text goes out; `{ESC}` stops the
    /// transmission in progress first.
    @Test func profileAndEscMacros() async throws {
        let app = try await Self.make { config in
            config.digital.runMessages[0] = FunctionKeyMessage(label: "CQ", text: "{ESC}{PROFILE2}CQ TEST")
            config.digital.spMessages[0] = FunctionKeyMessage(label: "CQ", text: "{ESC}{PROFILE2}CQ TEST")
        }
        let modem: BuiltinModemModel = app.model.builtinModem
        modem.tune(0) { $0.baud = 50 }
        #expect(modem.saveProfile(1, name: "50 Bd", side: 0) == nil)
        modem.tune(0) { $0.baud = 45.45 }
        app.keyer.digital.send("RYRYRYRYRYRYRYRYRYRYRYRYRYRYRY", key: 1)
        await app.settle()
        let first: FakeModemStream = try #require(app.keying.modemOutputs.first)
        first.pull(2_000)
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        #expect(first.isStopped, "{ESC} stopped the transmission in progress")
        #expect(modem.channel(0).tuning.baud == 50, "{PROFILE2} applied")
        let second: FakeModemStream = try #require(app.keying.modemOutputs.last)
        #expect(second !== first)
        let audio: [Float] = Self.drain(app, second)
        let decoder = BuiltinRttyChannel()
        decoder.update { $0.baud = 50 }
        decoder.receive((audio + [Float](repeating: 0, count: 6_000)).map { Double($0) })
        #expect(decoder.rxText(start: 0, length: decoder.rxLength).contains("CQ TEST"))
        // An empty slot: a status line, nothing changes.
        app.keyer.digital.applyProfile(9)
        #expect(app.status == "Profil modemu 10 je prázdný")
    }

    /// Built-in FSK (opt-in): the port's key line keyed with the text, PTT on the port's PTT line, no sound output,
    /// the port closed at the end; Esc stops it. A clock that does not wait; fake key lines.
    @Test func fskOverASerialPortLine() async throws {
        let app = try await Self.make { config in
            var setup = config.builtinModem
            setup.set(.fskPort, "/dev/fake.fsk")
            setup.set(.fskPttLine, "RTS")
            config.builtinModem = setup
        }
        let hub: BuiltinModemHub = app.model.keyer.lane.builtin
        hub.fskClock = InstantFskClock()
        app.keyer.digital.send("CQ TEST", key: 0)
        await app.settle()
        for _ in 0..<2_000 where hub.channels[0].isTransmitting {
            try await Task.sleep(for: .milliseconds(5))
            hub.settle()
        }
        #expect(!hub.channels[0].isTransmitting, "the transmission ended")
        #expect(app.keying.modemOutputs.isEmpty, "no sound output with FSK")
        let events: [String] = app.keying.events.filter { $0.hasPrefix("key") || $0.hasPrefix("ptt") }
        #expect(events.first == "key lines open /dev/fake.fsk DTR RTS")
        #expect(events.dropFirst().first == "ptt on")
        #expect(events.filter { $0 == "key down" }.count >= 9, "a start bit per character")
        #expect(events.suffix(2) == ["ptt off", "key lines close"], "\(events.suffix(4))")
        let echo: String = hub.channels[0].rxText(start: 0, length: hub.channels[0].rxLength)
        #expect(echo.contains("CQ TEST"), "the echo of the FSK text: \(echo)")
        // Esc during a long FSK transmission.
        app.keyer.digital.send(String(repeating: "RY", count: 400), key: 0)
        await app.settle()
        #expect(app.keyer.digital.abort())
        await app.settle()
        hub.settle()
        #expect(!hub.channels[0].isTransmitting)
        #expect(app.keying.events.last == "key lines close")
    }

    @Test func escStopsTheTransmissionAtOnce() async throws {
        let app = try await Self.make()
        app.keyer.digital.send("RYRYRYRYRYRYRYRYRYRYRYRYRYRYRYRYRYRYRYRYRYRYRY", key: 0)
        await app.settle()
        let stream: FakeModemStream = try #require(app.keying.modemOutputs.first)
        stream.pull(3_000)
        #expect(app.keyer.digital.abort())
        await app.settle()
        #expect(stream.isStopped)
        #expect(app.model.builtinModem.channel(0).trxState == "RX")
        #expect(stream.pull(1_000).isEmpty)
    }

    @Test func aFailedOutputEndsTheTransmission() async throws {
        let app = try await Self.make()
        app.keying.failModemOutput = "no device"
        app.keyer.digital.send("CQ TEST", key: 0)
        await app.settle()
        #expect(!app.keyer.digitalSending)
        #expect(app.status.contains("RTTY: no device"), "\(app.status)")
        #expect(app.model.builtinModem.channel(0).trxState == "RX")
    }

    @Test func twoReceiversTunedIndependentlyOrLinked() async throws {
        let app = try await Self.make()
        let modem: BuiltinModemModel = app.model.builtinModem
        let di2: DigitalInterfaceModel = app.model.makeDigitalInterface(index: 1)
        di2.open()
        await app.settle()
        modem.tune(0) { $0.markHz = 1000 }
        #expect(modem.channel(0).tuning.markHz == 1000)
        #expect(modem.channel(1).tuning.markHz == 2125, "independent by default")
        di2.toggle(.afc)
        await app.settle()
        #expect(!modem.channel(1).tuning.afc)
        #expect(modem.channel(0).tuning.afc)
        // Linked: one tuning for both receivers.
        var setup: BuiltinModemSetup = app.model.config.config.builtinModem
        setup.set(.linkedTuning, flag: true)
        app.model.config.config.builtinModem = setup
        app.keyer.digital.syncBuiltin()
        modem.tune(1) { $0.shiftHz = 425 }
        #expect(modem.channel(0).tuning.shiftHz == 425)
        #expect(modem.channel(0).tuning.markHz == modem.channel(1).tuning.markHz)
        // DI2 decodes its own receiver: a signal on its mark only.
        await modem.attach(1)
        modem.tune(1) { $0.markHz = 1500; $0.shiftHz = 170; $0.afc = false }
        try RadioSignals.feed(app, Self.rtty("DE OK2ZZ OK2ZZ\r\n", markHz: 1500))
        await Self.poll(app)
        #expect(di2.text.contains("OK2ZZ"), "\(di2.text)")
        di2.close()
    }
}

private extension Array {
    /// Consecutive slices of `size` elements.
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// The FSK keyer's clock without waiting.
final class InstantFskClock: FskClock, @unchecked Sendable {
    private let lock = NSLock()
    private var time: UInt64 = 0

    func now() -> UInt64 {
        lock.withLock { time }
    }

    func sleep(untilNanos deadline: UInt64) {
        lock.withLock { time = max(time, deadline) }
    }
}
