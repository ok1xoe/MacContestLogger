@testable import MCLCore
import Testing

/// N1MM Align, Shift Frequency Compensation and the tuning macros.
@Suite struct FldigiTuningTests {

    @Test func alignMovesTheDialByTheAudioDifference() {
        #expect(DigitalFrequency.alignedDialHz(dialHz: 14_080_000, rawMode: "PKTUSB", carrierHz: 1_700,
                                               targetHz: 2_210) == 14_079_490)
        #expect(DigitalFrequency.alignedDialHz(dialHz: 7_040_000, rawMode: "LSB", carrierHz: 1_700,
                                               targetHz: 2_210) == 7_040_510)
        #expect(DigitalFrequency.alignedDialHz(dialHz: 14_080_000, rawMode: "RTTY", carrierHz: 2_300,
                                               targetHz: 2_210) == 14_079_910)
        #expect(DigitalFrequency.alignedDialHz(dialHz: 14_080_000, rawMode: "RTTYR", carrierHz: 2_300,
                                               targetHz: 2_210) == 14_080_090)
        #expect(DigitalFrequency.alignedDialHz(dialHz: 14_080_000, rawMode: "CW", carrierHz: 1_700,
                                               targetHz: 2_210) == nil)
        #expect(DigitalFrequency.alignedDialHz(dialHz: 14_080_000, rawMode: "USB", carrierHz: 2_210,
                                               targetHz: 2_210) == nil)
    }

    @Test func shiftCompensationOnlyInFsk() {
        #expect(DigitalFrequency.shiftCompensation(rawMode: "RTTY", enabled: true, offsetHz: 170) == 170)
        #expect(DigitalFrequency.shiftCompensation(rawMode: "rttyr", enabled: true, offsetHz: -170) == -170)
        #expect(DigitalFrequency.shiftCompensation(rawMode: "USB", enabled: true, offsetHz: 170) == 0)
        #expect(DigitalFrequency.shiftCompensation(rawMode: "RTTY", enabled: false, offsetHz: 170) == 0)
    }

    @Test func alignTargets() {
        var digital = DigitalConfig()
        #expect(digital.alignHz(modem: "RTTY") == 2_210)
        #expect(digital.alignHz(modem: "BPSK31") == 1_500)
        digital.alignOtherHz = DigitalConfig.audioHz(99_999, fallback: 1_500)
        #expect(digital.alignOtherHz == 1_500)
    }

    @Test func tuningMacros() {
        let ctx = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "", lastLogged: "", serial: 1, rst: "599",
                                           exchange: "", cutNumbers: false, leadingZeros: false, now: nil)
        let message = CwMessageBuilder.build("{ALIGN}{ENABLEAFC}{DISABLEAFC}{ENABLENET}{DISABLENET}", ctx)
        #expect(message.actions == [.align, .afcOn, .afcOff, .netOn, .netOff])
        #expect(message.unknownMacros.isEmpty)
    }
}
