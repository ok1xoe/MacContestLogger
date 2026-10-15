import Foundation

/// A keyboard attached to the Mac, as the HID layer reports it. `id` is stable while it stays plugged into the same
/// port (vendor, product and location), so two keyboards of the same model are told apart.
public struct KeyboardDevice: Equatable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// The id of a HID device.
    public static func id(vendor: Int, product: Int, location: Int) -> String {
        String(format: "%04X:%04X:%08X", vendor, product, location)
    }
}

/// A key pressed on one keyboard (HID usage page 7, the key's usage).
public struct HidKeyPress: Equatable, Sendable {
    public let deviceId: String
    public let usage: UInt32

    public init(deviceId: String, usage: UInt32) {
        self.deviceId = deviceId
        self.usage = usage
    }
}

/// N1MM Config → SO2R → „Two Keyboards": each of two keyboards drives one entry window — keyboard 1 the left
/// (radio 1 / VFO A) window, keyboard 2 the right one. The HID layer reports which keyboard a key came from; the
/// window server's key event that follows carries only the key, so the two are matched by the key: the oldest
/// press of the same key not matched yet. A held key's repeats and its release go where its press went.
///
/// The assignment is the saved one (Settings → SO2R → two keyboards); without one, as in N1MM, the first keyboard
/// typed on drives entry window 1 and the next other keyboard entry window 2 (for this run).
public struct TwoKeyboardRouter: Equatable, Sendable {

    /// The presses kept for matching (the oldest go first).
    public static let pendingLimit = 32

    /// The saved assignment: the keyboard of entry window 1 and 2 (`nil` = none saved).
    public var saved: [String?] = [nil, nil]
    /// This run's assignment of keyboards without a saved one.
    public private(set) var session: [String?] = [nil, nil]
    private var pending: [HidKeyPress] = []
    /// The window each held key (by its Mac key code) went to.
    private var held: [UInt16: Int] = [:]

    public init(keyboard1: String? = nil, keyboard2: String? = nil) {
        saved = [Self.blankToNil(keyboard1), Self.blankToNil(keyboard2)]
    }

    private static func blankToNil(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return text
    }

    /// The keyboard driving entry window `window` (saved first, then this run's).
    public func keyboard(window: Int) -> String? {
        guard saved.indices.contains(window) else { return nil }
        return saved[window] ?? session[window]
    }

    /// The window keyboard `id` drives, if any.
    public func window(of id: String) -> Int? {
        (0..<2).first { keyboard(window: $0) == id }
    }

    /// A key press reported by the HID layer (modifier keys are not recorded: they only change the next key).
    public mutating func pressed(_ press: HidKeyPress) {
        guard !Self.isModifier(press.usage) else { return }
        pending.append(press)
        if pending.count > Self.pendingLimit {
            pending.removeFirst(pending.count - Self.pendingLimit)
        }
    }

    /// The entry window (0 / 1) of the window server's key down `keyCode`, or `nil` when it cannot be told (the
    /// HID press was not seen, or its keyboard drives no window).
    public mutating func keyDown(keyCode: UInt16, isRepeat: Bool) -> Int? {
        if isRepeat {
            return held[keyCode]
        }
        let usages: [UInt32] = MacKeyUsage.usages(keyCode)
        guard let index = pending.firstIndex(where: { usages.contains($0.usage) }) else {
            held[keyCode] = nil
            return nil
        }
        let press: HidKeyPress = pending[index]
        // Presses older than the matched one belong to keys the window server dropped (or reported first).
        pending.removeFirst(index + 1)
        let window: Int? = assign(press.deviceId)
        held[keyCode] = window
        return window
    }

    /// The window of the release of `keyCode`: where its press went.
    public mutating func keyUp(keyCode: UInt16) -> Int? {
        held.removeValue(forKey: keyCode)
    }

    /// The window of keyboard `id`, assigning it for this run when a window has no keyboard yet (N1MM: the first
    /// keyboard typed on drives the left window, the next one the right window).
    private mutating func assign(_ id: String) -> Int? {
        if let window = window(of: id) {
            return window
        }
        for window in 0..<2 where keyboard(window: window) == nil {
            session[window] = id
            return window
        }
        return nil
    }

    /// Forgets this run's assignment and every pending press (the option switched, the assignment changed).
    public mutating func reset() {
        session = [nil, nil]
        pending = []
        held = [:]
    }

    /// HID usages 0xE0–0xE7: Control, Shift, Option, Command (left and right).
    static func isModifier(_ usage: UInt32) -> Bool {
        (0xE0...0xE7).contains(usage)
    }
}

/// Mac virtual key codes (`kVK_…`) → HID keyboard usages (page 7). Some keys have two usages: ISO keyboards swap
/// the key left of 1 and the one right of the left Shift, a PC keyboard's Pause, Scroll Lock, Print Screen and
/// Insert reach the Mac as F15, F14, F13 and Help.
public enum MacKeyUsage {

    public static func usages(_ keyCode: UInt16) -> [UInt32] {
        table[keyCode] ?? []
    }

    private static let table: [UInt16: [UInt32]] = [
        0x00: [0x04], 0x01: [0x16], 0x02: [0x07], 0x03: [0x09], 0x04: [0x0B], 0x05: [0x0A], 0x06: [0x1D],
        0x07: [0x1B], 0x08: [0x06], 0x09: [0x19], 0x0A: [0x64, 0x35], 0x0B: [0x05], 0x0C: [0x14], 0x0D: [0x1A],
        0x0E: [0x08], 0x0F: [0x15], 0x10: [0x1C], 0x11: [0x17], 0x12: [0x1E], 0x13: [0x1F], 0x14: [0x20],
        0x15: [0x21], 0x16: [0x23], 0x17: [0x22], 0x18: [0x2E], 0x19: [0x26], 0x1A: [0x24], 0x1B: [0x2D],
        0x1C: [0x25], 0x1D: [0x27], 0x1E: [0x30], 0x1F: [0x12], 0x20: [0x18], 0x21: [0x2F], 0x22: [0x0C],
        0x23: [0x13], 0x24: [0x28], 0x25: [0x0F], 0x26: [0x0D], 0x27: [0x34], 0x28: [0x0E], 0x29: [0x33],
        0x2A: [0x31, 0x32], 0x2B: [0x36], 0x2C: [0x38], 0x2D: [0x11], 0x2E: [0x10], 0x2F: [0x37], 0x30: [0x2B],
        0x31: [0x2C], 0x32: [0x35, 0x64], 0x33: [0x2A], 0x35: [0x29],
        0x40: [0x6C], 0x41: [0x63], 0x43: [0x55], 0x45: [0x57], 0x47: [0x53], 0x4B: [0x54], 0x4C: [0x58],
        0x4E: [0x56], 0x4F: [0x6D], 0x50: [0x6E], 0x51: [0x67], 0x52: [0x62], 0x53: [0x59], 0x54: [0x5A],
        0x55: [0x5B], 0x56: [0x5C], 0x57: [0x5D], 0x58: [0x5E], 0x59: [0x5F], 0x5A: [0x6F], 0x5B: [0x60],
        0x5C: [0x61], 0x5D: [0x89], 0x5E: [0x87], 0x5F: [0x85],
        0x60: [0x3E], 0x61: [0x3F], 0x62: [0x40], 0x63: [0x3C], 0x64: [0x41], 0x65: [0x42], 0x66: [0x91],
        0x67: [0x44], 0x68: [0x90], 0x69: [0x68, 0x46], 0x6A: [0x6B], 0x6B: [0x69, 0x47], 0x6D: [0x43],
        0x6F: [0x45], 0x71: [0x6A, 0x48], 0x72: [0x75, 0x49], 0x73: [0x4A], 0x74: [0x4B], 0x75: [0x4C],
        0x76: [0x3D], 0x77: [0x4D], 0x78: [0x3B], 0x79: [0x4E], 0x7A: [0x3A], 0x7B: [0x50], 0x7C: [0x4F],
        0x7D: [0x51], 0x7E: [0x52],
    ]
}
