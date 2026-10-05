import Foundation

/// Automatic switching between Run / S&P by CQ frequency (N1MM Alt+F11 and Config →
/// "Do not automatically switch to Run on CQ-frequency").
public struct RunModeConfig: Codable, Equatable, Sendable {
    /// A QSY away from the CQ frequency switches to S&P (and back, see `runOnCqFrequency`).
    public var autoSwitch: Bool = true
    /// Returning to the CQ frequency switches to Run; handy to turn off in sprints.
    public var runOnCqFrequency: Bool = true
    /// Pause between the end of a CQ and the next CQ when repeating (N1MM Ctrl+R, seconds).
    public var repeatSeconds: Double = 2.0 {
        didSet {
            let normalized = RunModeConfig.normalizedRepeatSeconds(repeatSeconds)
            if normalized != repeatSeconds { repeatSeconds = normalized }
        }
    }

    enum CodingKeys: String, CodingKey { case autoSwitch, runOnCqFrequency, repeatSeconds }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RunModeConfig()
        autoSwitch = c.value(.autoSwitch, default: d.autoSwitch)
        runOnCqFrequency = c.value(.runOnCqFrequency, default: d.runOnCqFrequency)
        repeatSeconds = RunModeConfig.normalizedRepeatSeconds(c.value(.repeatSeconds, default: d.repeatSeconds))
    }

    private static func normalizedRepeatSeconds(_ value: Double) -> Double {
        max(0.2, min(value, 120.0))
    }
}
