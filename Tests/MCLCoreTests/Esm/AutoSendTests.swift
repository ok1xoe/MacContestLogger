import Testing
@testable import MCLCore

/// N1MM „CW/PH AutoSend Threshold": the call starts going out after N characters typed after its last digit.
@Suite struct AutoSendTests {

    @Test func charactersAfterTheLastDigit() {
        #expect(AutoSend.charactersAfterLastDigit("DL") == nil)
        #expect(AutoSend.charactersAfterLastDigit("DL1") == 0)
        #expect(AutoSend.charactersAfterLastDigit("DL1AB") == 2)
        #expect(AutoSend.charactersAfterLastDigit("3D2AB") == 2)
        #expect(AutoSend.charactersAfterLastDigit("OK1XYZ/P") == 5)
    }

    @Test func startsAtTheThresholdThenFollowsTheTyping() {
        #expect(AutoSend.next(call: "DL1A", sent: nil, threshold: 2) == nil)
        #expect(AutoSend.next(call: "DL1AB", sent: nil, threshold: 2) == "DL1AB")
        #expect(AutoSend.next(call: "DL1ABC", sent: "DL1AB", threshold: 2) == "C")
        #expect(AutoSend.next(call: "DL1AB", sent: "DL1AB", threshold: 2) == nil)
        // An edit other than typing on sends nothing (ESM resends the corrected call).
        #expect(AutoSend.next(call: "DL1AC", sent: "DL1AB", threshold: 2) == nil)
        #expect(AutoSend.next(call: "DL1A", sent: "DL1AB", threshold: 2) == nil)
    }

    @Test func zeroIsOff() {
        #expect(AutoSend.next(call: "DL1ABC", sent: nil, threshold: 0) == nil)
        #expect(AutoSend.next(call: "", sent: nil, threshold: 1) == nil)
    }
}
