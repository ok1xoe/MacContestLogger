import Foundation
import MCLCore
import Observation

/// The Digital Interface's Grab window (N1MM): the calls recognised in the received text, the highlighted one taken by
/// Alt+G, `{GRAB}`, `{LOGTHENGRAB}`, the Insert key and the Grab button. One list for the station (the macros reach
/// it from the entry window); the Digital Interface fills it while it polls fldigi.
///
/// Not offered: the call already in the call field, dupes (`digital.grabNoDupes`), calls missing from Master.scp
/// (`digital.grabOnlyScp`). Cleared on a QSY of more than 500 Hz (`grabClearOnQsy`) and when CQ is sent
/// (`grabClearOnCq`).
@Observable @MainActor
public final class GrabListModel {

    static let qsyThresholdHz: Int64 = 500

    public private(set) var list = GrabList()

    /// Dupe status of a call now (wired by the app).
    @ObservationIgnored var isDupe: @MainActor (String) -> Bool = { _ in false }
    /// Master.scp knows the call (wired by the app).
    @ObservationIgnored var inScp: @MainActor (String) -> Bool = { _ in true }
    /// The call field of the active entry window (wired by the app).
    @ObservationIgnored var typedCall: @MainActor () -> String = { "" }

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private var lastFrequencyHz: Int64 = 0

    init(config: ConfigModel) {
        self.config = config
    }

    public var order: GrabList.Order {
        GrabList.Order.from(config.config.digital.grabOrder)
    }

    /// The calls as shown, the next to grab first.
    public var shown: [String] {
        list.shown(order)
    }

    /// The highlighted call (grabbed next).
    public var highlighted: String? {
        list.highlighted(order)
    }

    /// A call recognised in the received text.
    func offer(_ call: String) {
        let digital: DigitalConfig = config.config.digital
        let normalized: String = CallStack.normalize(call)
        if normalized == CallStack.normalize(typedCall()) {
            return
        }
        if digital.grabNoDupes && isDupe(normalized) {
            return
        }
        if digital.grabOnlyScp && !inScp(normalized) {
            return
        }
        list.offer(normalized)
    }

    /// Takes the highlighted call out of the list.
    public func grab() -> String? {
        list.grab(order)
    }

    public func select(_ call: String?) {
        list.select(call)
    }

    public func remove(_ call: String) {
        list.remove(call)
    }

    public func removeTop() {
        list.removeTop(order)
    }

    public func removeSelected() {
        list.removeSelected(order)
    }

    public func clear() {
        list.clear()
    }

    /// The right-click menu's sort order (saved at once).
    public func setOrder(_ order: GrabList.Order) {
        config.config.digital.grabOrder = order.rawValue
        config.saveSilently()
    }

    /// The active entry window's frequency (every preview): a QSY clears the list with the option on.
    func noteFrequency(_ hz: Int64) {
        defer { lastFrequencyHz = hz }
        guard config.config.digital.grabClearOnQsy, lastFrequencyHz > 0, hz > 0,
              abs(hz - lastFrequencyHz) > Self.qsyThresholdHz else { return }
        list.clear()
    }

    /// CQ (F1) was sent.
    func cqSent() {
        if config.config.digital.grabClearOnCq {
            list.clear()
        }
    }
}
