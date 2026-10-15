import Foundation
import MCLCore
import Observation

/// The RTTY engine pane of one receiver (N1MM's MMTTY engine window under the receiver's text): the spectrum and
/// the waterfall with the mark and space markers, MMTTY's XY scope, the level against the squelch, and the tuning —
/// a click on the spectrum or the waterfall puts the mark there, shift and speed choices, AFC / NET / Rev. Refreshed
/// every 100 ms while the pane is shown.
@Observable @MainActor
public final class BuiltinEngineModel {

    /// The refresh period.
    static let refreshMs = 100
    /// The waterfall's size in pixels (the view scales it).
    static let waterfallSize = (width: 512, height: 120)

    /// The receiver (0 = radio 1, 1 = radio 2).
    public let side: Int
    /// The shown audio range (Hz).
    public private(set) var fromHz: Double = 300
    public private(set) var toHz: Double = 3_000
    public private(set) var tuning = BuiltinRttyChannel.Tuning()
    public private(set) var level: Double = 0
    public private(set) var squelchOpen = false
    public private(set) var transmitting = false
    public private(set) var waterfall = BuiltinWaterfall(width: BuiltinEngineModel.waterfallSize.width,
                                                         height: BuiltinEngineModel.waterfallSize.height)
    /// Raised by every new waterfall row (the view redraws its image).
    public private(set) var frame: Int = 0
    /// The XY scope's last batch (mark, space).
    public private(set) var xyPoints: [(x: Float, y: Float)] = []
    public private(set) var xyEnabled = false
    /// The squelch threshold (MMTTY 0…32768) and whether the squelch is on.
    public private(set) var squelchLevel: Double = 600
    public private(set) var squelchOn = false

    @ObservationIgnored private let modem: BuiltinModemModel
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private var timer: (any RescoreTimer)?
    @ObservationIgnored private var open = false

    init(side: Int, modem: BuiltinModemModel, clock: any RescoreClock) {
        self.side = min(max(side, 0), 1)
        self.modem = modem
        self.clock = clock
    }

    private var channel: BuiltinRttyChannel {
        modem.channel(side)
    }

    /// The receiver's audio error (`nil` = it listens).
    public var audioError: String? {
        modem.audioErrors[side]
    }

    public func start() {
        guard !open else { return }
        open = true
        refresh()
    }

    public func stop() {
        open = false
        timer?.cancel()
        timer = nil
        if xyEnabled {
            channel.setXYScope(false)
        }
    }

    /// One refresh: the tuning, the level and a new waterfall row; the next one is scheduled.
    func refresh() {
        guard open else { return }
        let snapshot: BuiltinRttyChannel.Snapshot = channel.snapshot
        tuning = snapshot.tuning
        level = snapshot.level
        squelchOpen = snapshot.squelchOpen
        transmitting = snapshot.transmitting
        squelchLevel = channel.number("squelchLevel") ?? squelchLevel
        squelchOn = channel.flag("squelch") ?? squelchOn
        if let spectrum = snapshot.spectrum, !snapshot.transmitting {
            waterfall.push(spectrum, fromHz: fromHz, toHz: toHz)
            frame &+= 1
        }
        if xyEnabled, let points = channel.xyPoints() {
            xyPoints = points
        }
        timer = clock.schedule(afterMilliseconds: Self.refreshMs) { [weak self] in
            self?.refresh()
        }
    }

    /// The audio frequency at a fraction (0…1) of the display's width.
    public func hz(atFraction fraction: Double) -> Double {
        fromHz + min(max(fraction, 0), 1) * (toHz - fromHz)
    }

    /// The fraction of the display's width of an audio frequency.
    public func fraction(ofHz hz: Double) -> Double {
        (hz - fromHz) / (toHz - fromHz)
    }

    /// A click on the spectrum or the waterfall: the mark goes there (MMTTY), the shift stays.
    public func click(atFraction fraction: Double) {
        let hz: Double = hz(atFraction: fraction)
        modem.tune(side) { $0.markHz = hz }
        tuning = channel.tuning
    }

    /// The right button: MMTTY's notch at that frequency.
    public func notch(atFraction fraction: Double) {
        channel.notch(hz(atFraction: fraction))
    }

    public func setShift(_ hz: Double) {
        modem.tune(side) { $0.shiftHz = hz }
        tuning = channel.tuning
    }

    public func setBaud(_ baud: Double) {
        modem.tune(side) { $0.baud = baud }
        tuning = channel.tuning
    }

    public func setAfc(_ on: Bool) {
        modem.tune(side) { $0.afc = on }
        tuning = channel.tuning
    }

    public func setNet(_ on: Bool) {
        modem.tune(side) { $0.net = on }
        tuning = channel.tuning
    }

    public func setReverse(_ on: Bool) {
        modem.tune(side) { $0.reverse = on }
        tuning = channel.tuning
    }

    /// The mouse wheel over the display: the squelch threshold up or down (MMTTY), in steps of 1/32 of the range.
    public func adjustSquelch(steps: Int) {
        let value: Double = min(max(squelchLevel + Double(steps) * 1_024, 0), 32_768)
        channel.set("squelchLevel", number: value)
        squelchLevel = value
    }

    public func setSquelch(_ on: Bool) {
        channel.set("squelch", flag: on)
        squelchOn = on
    }

    public func setXY(_ on: Bool) {
        xyEnabled = on
        channel.setXYScope(on)
        if !on {
            xyPoints = []
        }
    }

    /// The display range (e.g. 300…3000 Hz, or 1500…2700 Hz around the usual RTTY tones).
    public func setRange(from: Double, to: Double) {
        guard to - from >= 200 else { return }
        fromHz = max(0, from)
        toHz = min(to, BuiltinRttyChannel.sampleRate / 2)
        waterfall = BuiltinWaterfall(width: Self.waterfallSize.width, height: Self.waterfallSize.height)
    }

    /// The display ranges offered.
    public static let ranges: [(from: Double, to: Double)] = [(300, 3_000), (1_000, 2_500), (1_700, 2_700), (0, 6_000)]
}
