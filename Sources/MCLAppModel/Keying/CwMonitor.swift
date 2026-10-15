import Foundation
import MCLCore
import os

/// The sound-card CW monitor: the sent message as a shaped tone (`CwToneRenderer`) from the same element sequence
/// the DTR/RTS keyer uses, played on its own lane through the monitor port. Off unless the user enables it; a new
/// message (not a stacked one) and Esc cut the one playing.
final class CwMonitor: Sendable {

    private let lane = SerialLane(name: "cw-monitor")
    private let token = OSAllocatedUnfairLock<Int64>(initialState: 0)
    private let output: @Sendable ([UInt8], WavFile.PcmFormat, String?, () -> Bool) throws(AudioIOError) -> Void

    init(hardware: HardwarePorts) {
        output = hardware.playMonitor
    }

    /// Plays `message` when the monitor is on; `interrupt` = cut what plays now (a stacked message waits instead).
    func play(_ message: CwMessage, wpm: Int, options: CwKeyingOptions, interrupt: Bool) {
        let o: CwKeyingOptions = options.normalized()
        guard o.monitorEnabled else { return }
        let mine: Int64 = token.withLock { value in
            if interrupt {
                value &+= 1
            }
            return value
        }
        let token = self.token
        let output = self.output
        lane.submit {
            let cancelled: () -> Bool = { token.withLock { $0 } != mine }
            if cancelled() {
                return
            }
            let elements: [CwElement] = CwElements.sequence(message, wpm: wpm, weight: o.weight,
                                                            contestSpacing: o.contestSpacing)
            if elements.isEmpty {
                return
            }
            let lead: Double = o.serialKeying && o.serialHasPtt ? Double(o.serialPttDelayMs) : 0
            let pcm: [UInt8] = CwToneRenderer.render(elements, pitchHz: o.monitorPitchHz,
                                                     volume: Double(o.monitorVolume) / 100, leadingSilenceMs: lead)
            let device: String? = KotlinStrings.isBlank(o.monitorDevice) ? nil : o.monitorDevice
            // A missing device only silences the monitor; keying is not affected.
            try? output(pcm, CwToneRenderer.format, device, cancelled)
        }
    }

    /// Esc, the reset and the quit: the playing tone stops.
    func stop() {
        token.withLock { $0 &+= 1 }
    }

    func settle() async {
        await lane.settle()
    }
}
