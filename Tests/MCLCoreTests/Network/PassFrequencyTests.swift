import Testing
@testable import MCLCore

/// N1MM Alt+Z: a station's pass frequency to all stations; a PASS to it lands there.
@Suite struct PassFrequencyTests {

    static func wire(from: String, freq: Int) -> NetMessageWire {
        NetMessageWire(type: NetMessageWire.passFrequency, id: "id", fromStation: from, fromOperator: "", toStation: "",
                       text: "", call: nil, freqHz: freq, mode: nil, timestampUtc: "2026-10-04T12:34:56Z")
    }

    @Test func receivedPassFrequenciesAreKeptPerStation() {
        var messages = NetMessages()
        let effects = messages.receive(Self.wire(from: "OP2", freq: 14_123_000), catFreqHz: nil, tunedHz: 0,
                                       now: NetworkLogicTests.now)
        #expect(messages.passFrequencies == ["OP2": 14_123_000])
        #expect(NetworkLogicTests.czech(effects) == "Pass frekvence OP2: 14123.0 kHz")
        #expect(messages.lines.last?.text == "PASS FREQ 14123.0")
        #expect(messages.unread == 0)
        let cleared = messages.receive(Self.wire(from: "OP2", freq: 0), catFreqHz: nil, tunedHz: 0,
                                       now: NetworkLogicTests.now)
        #expect(messages.passFrequencies.isEmpty)
        #expect(NetworkLogicTests.czech(cleared) == "Pass frekvence OP2 zrušena")
    }

    @Test func typedPassFrequency() {
        #expect(NetMessages.passFrequencyHz("14123") == 14_123_000)
        #expect(NetMessages.passFrequencyHz("7012,5") == 7_012_500)
        #expect(NetMessages.passFrequencyHz(" ") == 0)
        #expect(NetMessages.passFrequencyHz("abc") == nil)
        #expect(NetMessages.passFrequencyHz("-5") == nil)
    }

    @Test func aPassGoesToTheAnnouncedPassFrequency() {
        let peers = NetworkSendTests.peers(op2: true, op3: true, op4: false, op5: false)
        let translator: Translator = .source
        let plain = NetMessages.passMessage(to: "OP2", call: "OK1ABC", peers: peers, myFreqHz: 0,
                                            translator: translator)
        #expect(plain?.freqHz == 14_025_000)
        let announced = NetMessages.passMessage(to: "OP2", call: "OK1ABC", peers: peers, myFreqHz: 0,
                                                translator: translator, passFrequencyHz: 14_040_000)
        #expect(announced?.freqHz == 14_040_000)
        #expect(announced?.mode == "CW")
        let cleared = NetMessages.passMessage(to: "OP2", call: "OK1ABC", peers: peers, myFreqHz: 0,
                                              translator: translator, passFrequencyHz: 0)
        #expect(cleared?.freqHz == 14_025_000)
    }
}
