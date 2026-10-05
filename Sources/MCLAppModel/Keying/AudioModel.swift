import Foundation
import MCLCore
import Observation

/// The receiver audio shared by the waterfall, the CW reader and the contest recorder (`AppState.audio`,
/// `acquireAudio`, `releaseAudio`, `AS:152-167`): the first user opens the input
/// (`config.rxAudioDevice`), a running input is not reselected, the last user closes it; a failed start does not
/// leave its user registered (Kotlin did — the input then never closed). Start and close run on the audio lane.
@Observable @MainActor
public final class AudioModel {

    /// The capture the listeners attach to (its blocks arrive on the `audio-capture` queue).
    @ObservationIgnored public let capture = AudioCapture()
    @ObservationIgnored private var users = AudioUsers()
    @ObservationIgnored private let lane = SerialLane(name: "audio")
    @ObservationIgnored private let hardware: HardwarePorts
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private var closed = false

    init(hardware: HardwarePorts, config: ConfigModel) {
        self.hardware = hardware
        self.config = config
    }

    /// The users holding the input.
    public var userNames: Set<String> {
        users.users
    }

    /// The input as the main actor sees it. Starts and closes run later on the lane, so `capture.isRunning` alone
    /// cannot tell a start in flight (a second user would start the input twice) nor a close in flight (a new user
    /// would take a running input that is about to close).
    private enum Device {
        case stopped
        /// A start is queued; the users that arrive meanwhile wait for its outcome.
        case starting
        case running
    }

    @ObservationIgnored private var device: Device = .stopped
    /// Raised by every close: a start whose users all left before it finished does not mark the input running.
    @ObservationIgnored private var epoch: Int = 0
    @ObservationIgnored private var startWaiters: [CheckedContinuation<Void, Never>] = []

    /// Kotlin `acquireAudio(user)`: `nil` = the input runs, otherwise the error's message (the user is not
    /// registered then). A user arriving while another user's start is in flight waits for that start and
    /// shares its input; when that start failed, it tries again itself (Kotlin acquires synchronously, one after
    /// the other).
    public func acquire(_ user: String) async -> String? {
        while device == .starting && !closed {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                startWaiters.append(continuation)
            }
        }
        guard !closed else { return InertHardwareError.message }
        let running: Bool = device == .running && capture.isRunning
        switch users.acquire(user, running: running) {
        case .alreadyRunning:
            return nil
        case .start:
            break
        }
        device = .starting
        let startEpoch: Int = epoch
        let deviceName: String = config.config.rxAudioDevice
        let capture: AudioCapture = self.capture
        let start: @Sendable (AudioCapture, String?) throws(AudioIOError) -> Void = hardware.startAudio
        let failure: String? = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            lane.submit {
                do {
                    try start(capture, deviceName)
                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(returning: KeyingErrors.javaMessage(error) ?? "null")
                }
            }
        }
        // A close queued meanwhile (every user left) runs after this start: the input is then stopped.
        device = epoch == startEpoch && failure == nil ? .running : .stopped
        let waiters: [CheckedContinuation<Void, Never>] = startWaiters
        startWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
        if let failure {
            users.startFailed(user)
            return failure
        }
        return nil
    }

    /// Kotlin `releaseAudio(user)`: the last user closes the input (on the lane, after any start queued before).
    public func release(_ user: String) {
        guard users.release(user) else { return }
        epoch += 1
        if device == .running {
            device = .stopped
        }
        let capture: AudioCapture = self.capture
        lane.submit {
            capture.close()
        }
    }

    public func addListener(_ listener: @escaping @Sendable ([Double]) -> Void) -> AudioCapture.ListenerID {
        capture.addListener(listener)
    }

    public func removeListener(_ id: AudioCapture.ListenerID) {
        capture.removeListener(id)
    }

    public func addRawListener(_ listener: @escaping @Sendable ([UInt8]) -> Void) -> AudioCapture.ListenerID {
        capture.addRawListener(listener)
    }

    public func removeRawListener(_ id: AudioCapture.ListenerID) {
        capture.removeRawListener(id)
    }

    /// The quit (last): the input closes whoever still holds it.
    func shutdown() async {
        closed = true
        epoch += 1
        device = .stopped
        let waiters: [CheckedContinuation<Void, Never>] = startWaiters
        startWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
        let capture: AudioCapture = self.capture
        lane.submit {
            capture.close()
        }
        await lane.settle()
    }

    /// Waits for the starts and closes queued before (tests).
    func settle() async {
        await lane.settle()
    }
}
