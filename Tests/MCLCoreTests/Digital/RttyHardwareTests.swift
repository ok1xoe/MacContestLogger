import Foundation
@testable import MCLCore
import Testing

/// The RTTY hardware protocols, from their documentation (untested on real devices): TNC command macros, K0SM's
/// TinyFSK framing, K1EL's WinKeyer 3.1 FSK mode command (WKUSB API extension 0x13) and the Baudot text.
@Suite struct RttyHardwareTests {

    @Test func tncMacros() {
        #expect(TncCommands.bytes("X{ENTER}") == [0x58, 0x0D])
        #expect(TncCommands.bytes("{CTRL-C}R RTTY {ENTER}") == [0x03, 0x52, 0x20, 0x52, 0x54, 0x54, 0x59, 0x20, 0x0D])
        #expect(TncCommands.bytes("{ctrl-d}{ESC}{ENTERLF}") == [0x04, 0x1B, 0x0D, 0x0A])
        #expect(TncCommands.bytes("{UNKNOWN}") == Array("{UNKNOWN}".utf8))
        #expect(TncType.pk232.defaultCommands.tx == "X{ENTER}")
        #expect(TncType.kam.defaultCommands.rx == "{CTRL-C}E")
        var digital = DigitalConfig()
        digital.tncType = TncType.kam.rawValue
        digital.tncEsc = "{CTRL-C}Q"
        #expect(digital.tncCommands.tx == "{CTRL-C}T")
        #expect(digital.tncCommands.esc == "{CTRL-C}Q")
    }

    @Test func tinyFskFrames() {
        #expect(TinyFsk.frame("cq test [k0sm]") == Array("[CQ TEST K0SM]".utf8))
        #expect(TinyFsk.frame("599", returnToRx: false) == Array("[599".utf8))
        #expect(TinyFsk.abort == 0x5C)
    }

    @Test func winkeyerRttyMode() {
        #expect(WinkeyerRtty.mode(nil) == [0x00, 0x13, 0x00, 0x00])
        #expect(WinkeyerRtty.mode(WinkeyerRtty.Settings()) == [0x00, 0x13, 0x80, 0x00])
        let all = WinkeyerRtty.Settings(baud: 75, reverse: true, fskOnKey: true, diddle: true, usos: true)
        let expected: [UInt8] = [0x00, 0x13, 0xE6, 0x01]
        #expect(WinkeyerRtty.mode(all) == expected)
        #expect(WinkeyerRtty.mode(WinkeyerRtty.Settings(baud: 100))[2] == 0x83)
        #expect(WinkeyerRtty.frame("tu\nqrz") == Array("[TU}QRZ]".utf8))
    }

    @Test func baudotTextAndDuration() {
        #expect(BaudotText.filter("Hi [OK1XOE] ~5nn~ \\") == "HI OK1XOE 5NN ")
        #expect(BaudotText.durationMs("CQ") == Int((4 * 7.5 * 1000 / 45.45).rounded()) + 300)
    }

    @Test func winkeyerSendsRttyAndLeavesItForCw() throws {
        let pipe = PipeTransport(endOfStream: true)
        let keyer = WinkeyerKeyer(transport: pipe)
        try keyer.sendRtty("cq test", settings: WinkeyerRtty.Settings())
        #expect(pipe.sent == [0x00, 0x13, 0x80, 0x00] + Array("[CQ TEST]".utf8))
        pipe.resetSent()
        try keyer.abortRtty()
        #expect(pipe.sent == [0x5C])
        pipe.resetSent()
        try keyer.send(CwMessage(parts: [.text("TU")]), wpm: 28)
        #expect(Array(pipe.sent.prefix(4)) == [0x00, 0x13, 0x00, 0x00], "RTTY off before CW")
        keyer.close()
    }
}
