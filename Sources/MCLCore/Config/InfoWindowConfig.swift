import Foundation

/// Info window options that in N1MM sit in the right-click context menu:
/// length of the rate-graph interval, display of timers and the off-time timer mode.
///
/// Values outside the menu (a hand-edited `config.json`) silently revert to the
/// default — otherwise the window would work with something that cannot be chosen in the UI.
public struct InfoWindowConfig: Codable, Equatable, Sendable {

    /// Lengths of moving averages that N1MM offers.
    public static let trendMinuteOptions: [Int] = [20, 30, 60]

    /// Off-time timer modes (without the SO2V/SO2R variants — one TCVR).
    public static let offTimeModeOptions: [String] = [
        "sinceLastQso", "offTime", "countUp", "countDown", "cumulativeOff",
    ]

    private static let defaultTrendMinutes = 20
    private static let defaultOffTimeMode = "sinceLastQso"

    public var trendMinutes: Int = InfoWindowConfig.defaultTrendMinutes {
        didSet {
            let normalized = InfoWindowConfig.normalizedTrendMinutes(trendMinutes)
            if normalized != trendMinutes { trendMinutes = normalized }
        }
    }
    public var showTimers: Bool = true
    public var offTimeMode: String = InfoWindowConfig.defaultOffTimeMode {
        didSet {
            let normalized = InfoWindowConfig.normalizedOffTimeMode(offTimeMode)
            if normalized != offTimeMode { offTimeMode = normalized }
        }
    }
    public var showCallframeSpot: Bool = true
    public var showCountryInfo: Bool = true
    public var showSunTimes: Bool = true
    public var showWwv: Bool = true
    public var showGoals: Bool = true
    public var showMessages: Bool = true

    enum CodingKeys: String, CodingKey {
        case trendMinutes, showTimers, offTimeMode, showCallframeSpot, showCountryInfo
        case showSunTimes, showWwv, showGoals, showMessages
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = InfoWindowConfig()
        trendMinutes = InfoWindowConfig.normalizedTrendMinutes(c.value(.trendMinutes, default: d.trendMinutes))
        showTimers = c.value(.showTimers, default: d.showTimers)
        offTimeMode = InfoWindowConfig.normalizedOffTimeMode(c.value(.offTimeMode, default: d.offTimeMode))
        showCallframeSpot = c.value(.showCallframeSpot, default: d.showCallframeSpot)
        showCountryInfo = c.value(.showCountryInfo, default: d.showCountryInfo)
        showSunTimes = c.value(.showSunTimes, default: d.showSunTimes)
        showWwv = c.value(.showWwv, default: d.showWwv)
        showGoals = c.value(.showGoals, default: d.showGoals)
        showMessages = c.value(.showMessages, default: d.showMessages)
    }

    private static func normalizedTrendMinutes(_ value: Int) -> Int {
        trendMinuteOptions.contains(value) ? value : defaultTrendMinutes
    }

    private static func normalizedOffTimeMode(_ value: String) -> String {
        offTimeModeOptions.contains(value) ? value : defaultOffTimeMode
    }
}
