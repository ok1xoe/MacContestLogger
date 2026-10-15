import Foundation
@testable import MCLCore
import Testing

/// N1MM „Two Keyboards": the HID presses (with their keyboard) matched to the window server's key events. Plain
/// values only — no input device is read.
@Suite struct TwoKeyboardRouterTests {

    private static let left = "05AC:0250:00100000"
    private static let right = "046D:C31C:00200000"
    /// `kVK_ANSI_A`, `kVK_ANSI_B` and their HID usages.
    private static let keyA: UInt16 = 0x00
    private static let keyB: UInt16 = 0x0B

    @Test func theFirstKeyboardTypedOnDrivesTheLeftWindow() {
        var router = TwoKeyboardRouter()
        router.pressed(HidKeyPress(deviceId: Self.right, usage: 0x04))
        #expect(router.keyDown(keyCode: Self.keyA, isRepeat: false) == 0)
        router.pressed(HidKeyPress(deviceId: Self.left, usage: 0x05))
        #expect(router.keyDown(keyCode: Self.keyB, isRepeat: false) == 1)
        #expect(router.window(of: Self.right) == 0)
        #expect(router.window(of: Self.left) == 1)
        // A third keyboard drives nothing.
        router.pressed(HidKeyPress(deviceId: "third", usage: 0x04))
        #expect(router.keyDown(keyCode: Self.keyA, isRepeat: false) == nil)
        // The run's assignment is forgotten on reset.
        router.reset()
        #expect(router.window(of: Self.right) == nil)
    }

    @Test func theSavedAssignmentWins() {
        var router = TwoKeyboardRouter(keyboard1: Self.left, keyboard2: Self.right)
        router.pressed(HidKeyPress(deviceId: Self.right, usage: 0x04))
        router.pressed(HidKeyPress(deviceId: Self.left, usage: 0x05))
        #expect(router.keyDown(keyCode: Self.keyA, isRepeat: false) == 1)
        #expect(router.keyDown(keyCode: Self.keyB, isRepeat: false) == 0)
        // Only one saved: the other window takes the next keyboard.
        var one = TwoKeyboardRouter(keyboard1: nil, keyboard2: Self.left)
        one.pressed(HidKeyPress(deviceId: Self.right, usage: 0x04))
        #expect(one.keyDown(keyCode: Self.keyA, isRepeat: false) == 0)
        #expect(TwoKeyboardRouter(keyboard1: " ", keyboard2: "").keyboard(window: 0) == nil)
    }

    @Test func interleavedKeysAreMatchedByKey() {
        var router = TwoKeyboardRouter(keyboard1: Self.left, keyboard2: Self.right)
        // Both presses arrive before either key event (2BSIQ: one hand on each keyboard).
        router.pressed(HidKeyPress(deviceId: Self.left, usage: 0x04))
        router.pressed(HidKeyPress(deviceId: Self.right, usage: 0x05))
        #expect(router.keyDown(keyCode: Self.keyB, isRepeat: false) == 1)
        // The A press is older than the matched B press: it was dropped with it, so A is not known any more.
        #expect(router.keyDown(keyCode: Self.keyA, isRepeat: false) == nil)
        router.pressed(HidKeyPress(deviceId: Self.left, usage: 0x04))
        router.pressed(HidKeyPress(deviceId: Self.right, usage: 0x04))
        #expect(router.keyDown(keyCode: Self.keyA, isRepeat: false) == 0)
        #expect(router.keyDown(keyCode: Self.keyA, isRepeat: false) == 1)
        // A key event without its press (the HID report came late) is not routed.
        #expect(router.keyDown(keyCode: Self.keyB, isRepeat: false) == nil)
    }

    @Test func repeatsAndReleasesFollowThePress() {
        var router = TwoKeyboardRouter(keyboard1: Self.left, keyboard2: Self.right)
        router.pressed(HidKeyPress(deviceId: Self.right, usage: 0x04))
        #expect(router.keyDown(keyCode: Self.keyA, isRepeat: false) == 1)
        #expect(router.keyDown(keyCode: Self.keyA, isRepeat: true) == 1)
        #expect(router.keyUp(keyCode: Self.keyA) == 1)
        #expect(router.keyUp(keyCode: Self.keyA) == nil)
        // Modifier keys are not recorded (they only change the next key).
        router.pressed(HidKeyPress(deviceId: Self.left, usage: 0xE0))
        router.pressed(HidKeyPress(deviceId: Self.left, usage: 0x3A))
        #expect(router.keyDown(keyCode: 0x7A, isRepeat: false) == 0)
    }

    @Test func keyTableCoversTheEntryKeys() {
        #expect(MacKeyUsage.usages(0x24) == [0x28])
        #expect(MacKeyUsage.usages(0x35) == [0x29])
        #expect(MacKeyUsage.usages(0x7A) == [0x3A])
        #expect(MacKeyUsage.usages(0x6F) == [0x45])
        // A PC keyboard's Pause reaches the Mac as F15; ISO keyboards swap the § and ` keys.
        #expect(MacKeyUsage.usages(0x71).contains(0x48))
        #expect(MacKeyUsage.usages(0x0A).contains(0x35) && MacKeyUsage.usages(0x32).contains(0x64))
        #expect(MacKeyUsage.usages(0xFF).isEmpty)
        #expect(KeyboardDevice.id(vendor: 0x05AC, product: 0x0250, location: 0x0010_0000) == Self.left)
    }
}
