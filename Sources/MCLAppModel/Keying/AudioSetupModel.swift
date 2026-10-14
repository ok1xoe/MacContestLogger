import Foundation
import MCLCore
import Observation
import os

/// N1MM Logger+ Audio Setup in Settings → Audio: the level meter of the receive input and the test tone of the voice
/// keyer's output. The tone never keys the transmitter (no PTT); the meter only reads the input while it is shown.
@Observable @MainActor
public final class AudioSetupModel {

    /// The meter is reading the input.
    public private(set) var metering: Bool = false
    /// The peak of the last block in dBFS (−90 = silence).
    public private(set) var peakDb: Double = -90
    /// The test tone is playing.
    public private(set) var testing: Bool = false
    /// The last error (input or output), `nil` = none.
    public private(set) var problem: String?

    @ObservationIgnored private let audio: AudioModel
    @ObservationIgnored private let hardware: HardwarePorts
    @ObservationIgnored private var listener: AudioCapture.ListenerID?
    @ObservationIgnored private let lane = SerialLane(name: "audio-test")
    @ObservationIgnored private let toneCancel = OSFlag()

    nonisolated static let meterUser = "settings-level-meter"

    init(audio: AudioModel, hardware: HardwarePorts) {
        self.audio = audio
        self.hardware = hardware
    }

    // MARK: - level meter

    /// Starts reading the receive input (`config.rxAudioDevice`, shared with the waterfall and the CW reader).
    public func startMeter() async {
        guard !metering else { return }
        metering = true
        problem = nil
        if let failure = await audio.acquire(Self.meterUser) {
            metering = false
            problem = failure
            return
        }
        guard metering else {
            audio.release(Self.meterUser)
            return
        }
        listener = audio.addListener { [weak self] samples in
            let peak: Double = samples.reduce(0) { max($0, abs($1)) }
            let db: Double = Self.dbfs(peak)
            MainHop.post {
                guard let self, self.metering else { return }
                self.peakDb = db
            }
        }
    }

    public func stopMeter() {
        guard metering else { return }
        metering = false
        if let listener {
            audio.removeListener(listener)
        }
        listener = nil
        peakDb = -90
        audio.release(Self.meterUser)
    }

    /// Peak (0…1) → dBFS, −90 at most.
    nonisolated static func dbfs(_ peak: Double) -> Double {
        peak <= 0.000_031_6 ? -90 : max(-90, 20 * log10(peak))
    }

    // MARK: - test tone

    /// Plays a 1 kHz tone of one second on the output (`device`, at `level` percent) — only to the sound card, the
    /// transmitter is never keyed. A second press stops it.
    public func playTestTone(device: String, level: Int) {
        if testing {
            toneCancel.set(true)
            return
        }
        testing = true
        problem = nil
        toneCancel.set(false)
        let bytes: [UInt8] = SoundCard.scaled(Self.tone(), bits: 16, gain: Double(max(0, min(100, level))) / 100)
        let format = WavFile.PcmFormat(sampleRate: Float(Self.toneRate), bits: 16, channels: 1, frameSize: 2)
        let play = hardware.playPcm
        let cancel: OSFlag = toneCancel
        let name: String? = KotlinStrings.isBlank(device) ? nil : device
        lane.submit({ () -> String? in
            do {
                try play(bytes, format, name, { cancel.value })
                return nil
            } catch {
                return KeyingErrors.javaMessage(error) ?? "null"
            }
        }, then: { [weak self] failure in
            guard let self else { return }
            self.testing = false
            self.problem = failure
        })
    }

    nonisolated static let toneRate: Int = 8_000

    /// One second of a 1 kHz sine at −6 dBFS, 16-bit mono little-endian.
    nonisolated static func tone() -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(toneRate * 2)
        let step: Double = 2 * Double.pi * 1000 / Double(toneRate)
        for n in 0..<toneRate {
            let phase: Double = step * Double(n)
            let sample: Double = sin(phase) * 16_384
            let value: Int16 = Int16(sample.rounded())
            let bits = UInt16(bitPattern: value)
            out.append(UInt8(truncatingIfNeeded: bits))
            out.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        return out
    }

    /// Waits for the tone's lane (tests).
    func settle() async {
        await lane.settle()
    }
}

/// A flag read on another thread.
final class OSFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    func set(_ value: Bool) {
        state.withLock { $0 = value }
    }

    var value: Bool {
        state.withLock { $0 }
    }
}
