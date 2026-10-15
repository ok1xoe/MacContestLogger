import Foundation
import IOKit
import IOKit.hid
import MCLAppModel
import MCLCore

/// The IOKit side of N1MM „Two Keyboards": the keyboards attached (HID generic desktop / keyboard) and their key
/// presses with the keyboard they came from. Reading key presses needs macOS Input Monitoring
/// (`IOHIDCheckAccess` / `IOHIDRequestAccess`); the HID manager runs on a thread of its own and reports presses
/// from there. Only key presses are read (usage page 7, value 1) — nothing is ever sent to a device.
final class HidKeyboardSource: KeyboardDeviceSource, @unchecked Sendable {

    private let lock = NSLock()
    private var manager: IOHIDManager?
    private var runLoop: CFRunLoop?
    private var onPress: (@Sendable (HidKeyPress) -> Void)?

    var access: KeyboardAccess {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .undetermined
        }
    }

    func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    private static var matching: CFDictionary {
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard]
            as CFDictionary
    }

    func keyboards() -> [KeyboardDevice] {
        let manager: IOHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, Self.matching)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return devices.map(Self.device).sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }

    func start(_ onPress: @escaping @Sendable (HidKeyPress) -> Void) -> Bool {
        lock.withLock { self.onPress = onPress }
        let opened = OpenResult()
        let thread = Thread { [self] in
            let manager: IOHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerSetDeviceMatching(manager, Self.matching)
            let context: UnsafeMutableRawPointer = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
                guard let context else { return }
                Unmanaged<HidKeyboardSource>.fromOpaque(context).takeUnretainedValue().received(value)
            }, context)
            let loop: CFRunLoop = CFRunLoopGetCurrent()
            IOHIDManagerScheduleWithRunLoop(manager, loop, CFRunLoopMode.defaultMode.rawValue)
            let result: IOReturn = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard result == kIOReturnSuccess else {
                IOHIDManagerUnscheduleFromRunLoop(manager, loop, CFRunLoopMode.defaultMode.rawValue)
                opened.finish(false)
                return
            }
            self.lock.withLock {
                self.manager = manager
                self.runLoop = loop
            }
            opened.finish(true)
            CFRunLoopRun()
            IOHIDManagerUnscheduleFromRunLoop(manager, loop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        thread.name = "HID keyboards"
        thread.start()
        return opened.wait()
    }

    func stop() {
        let loop: CFRunLoop? = lock.withLock {
            let loop: CFRunLoop? = runLoop
            runLoop = nil
            manager = nil
            onPress = nil
            return loop
        }
        if let loop {
            CFRunLoopStop(loop)
        }
    }

    /// A HID value on the manager's thread: a key press of usage page 7 goes out with its keyboard.
    private func received(_ value: IOHIDValue) {
        let element: IOHIDElement = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad),
              IOHIDValueGetIntegerValue(value) == 1 else { return }
        let usage: UInt32 = IOHIDElementGetUsage(element)
        guard (0x04...0xE7).contains(usage) else { return }
        let device: IOHIDDevice = IOHIDElementGetDevice(element)
        let press = HidKeyPress(deviceId: Self.device(device).id, usage: usage)
        let handler: (@Sendable (HidKeyPress) -> Void)? = lock.withLock { onPress }
        handler?(press)
    }

    private static func device(_ device: IOHIDDevice) -> KeyboardDevice {
        func int(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
        }
        let name: String = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Keyboard"
        let id: String = KeyboardDevice.id(vendor: int(kIOHIDVendorIDKey), product: int(kIOHIDProductIDKey),
                                           location: int(kIOHIDLocationIDKey))
        return KeyboardDevice(id: id, name: name)
    }

    /// The manager thread's answer whether the HID manager opened.
    private final class OpenResult: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        private var opened = false

        func finish(_ value: Bool) {
            opened = value
            semaphore.signal()
        }

        func wait() -> Bool {
            semaphore.wait()
            return opened
        }
    }
}
