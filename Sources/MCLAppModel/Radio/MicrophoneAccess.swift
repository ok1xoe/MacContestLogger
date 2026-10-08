import AVFoundation
import Foundation

/// The system's microphone permission (TCC).
enum MicrophoneAccess {

    /// `true` when recording is allowed; the first call shows the system prompt. A build without the usage string in
    /// its `Info.plist` (a bare `swift run`) cannot ask: the recording itself then reports what the system says.
    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
                return true
            }
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
}
