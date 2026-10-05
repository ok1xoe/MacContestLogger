import AudioToolbox
import CoreAudio
import Foundation

/// CoreAudio sound devices by name (a replacement for Java `javax.sound` mixers).
/// Read-only property access (`kAudioHardwarePropertyDevices`, `kAudioDevicePropertyStreams`,
/// `kAudioObjectPropertyName`) — nothing is opened. A CoreAudio error (e.g. a machine without audio) = empty list.
enum CoreAudioDevices {

    /// Java pseudo-mixer of the default device; this name may be in `config.json`
    /// (`voiceKeyer.outputDevice`, `rxAudioDevice`) and means the system default device.
    static let defaultDeviceName = "Default Audio Device"

    /// Names of devices with input (`input`) or output streams in CoreAudio order.
    static func names(input: Bool) -> [String] {
        devices(input: input).map(\.name)
    }

    /// Device for a name from the configuration: `nil` = system default (`nil`, empty/blank name,
    /// `Default Audio Device`, a name not found — like Java `mixer(name) == null`).
    static func deviceID(named name: String?, input: Bool) -> AudioDeviceID? {
        guard let name, !JavaText.isBlank(name), name != defaultDeviceName else {
            return nil
        }
        return devices(input: input).first { $0.name == name }?.id
    }

    private static func devices(input: Bool) -> [(id: AudioDeviceID, name: String)] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        var out: [(id: AudioDeviceID, name: String)] = []
        for id in ids where hasStreams(id, input: input) {
            if let name = name(of: id) {
                out.append((id, name))
            }
        }
        return out
    }

    private static func hasStreams(_ id: AudioDeviceID, input: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status: OSStatus = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value = name?.takeRetainedValue() else {
            return nil
        }
        return value as String
    }

    /// Sets the device of the audio unit of the `AVAudioEngine` input/output node (before the engine starts).
    static func select(_ id: AudioDeviceID, on unit: AudioUnit) -> OSStatus {
        var device = id
        return AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                    &device, UInt32(MemoryLayout<AudioDeviceID>.size))
    }
}
