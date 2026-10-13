import Foundation
import MCLCore
import Observation

/// The one call stack of the station (N1MM single-operator and partner call stacking): Ctrl+Alt+G and
/// `{STACKANOTHER}` push the call field, `{SOCALLSTACK}` exchanges it, Alt+click in the Digital Interface pushes a
/// heard call, a partner's STACK message arrives here; Alt+G (Ctrl+Alt+K) and `{LOGTHENPOP}` take the next call,
/// Alt+D with an empty call field deletes it, `{CLRSTACK}` clears the stack.
///
/// Dupes are never stacked or popped and the order follows `esm.callStackOrder`; both need the contest's view of a
/// call at the active entry window's frequency and mode (`evaluate`, wired by the app). A band change drops the calls
/// of the old band when `esm.callStackClearOnBandChange` is on.
@Observable @MainActor
public final class CallStackModel {

    public private(set) var stack = CallStack()

    /// Dupe and new multipliers of a call now (wired by the app to the spot analysis); neutral without a contest.
    @ObservationIgnored var evaluate: @MainActor (String) -> CallStack.Evaluation = { _ in .neutral }
    /// The band (ADIF) of the active entry window, `""` when unknown.
    @ObservationIgnored var currentBand: @MainActor () -> String = { "" }

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private var lastBand: String = ""

    init(config: ConfigModel, status: StatusModel) {
        self.config = config
        self.status = status
    }

    private var order: CallStack.Order {
        CallStack.Order.from(config.config.esm.callStackOrder)
    }

    /// The calls in the order they come off the stack (the „ZÁSOBNÍK" line).
    public var calls: [String] {
        let evaluate = self.evaluate
        return stack.ordered(order) { evaluate($0) }.map(\.call)
    }

    /// The call that comes off next, `nil` for an empty stack.
    public var next: String? {
        let evaluate = self.evaluate
        return stack.peek(order) { evaluate($0) }
    }

    /// Pushes a call; the status line says what happened. `true` = it is on the stack now.
    @discardableResult
    public func push(_ call: String, source: CallStack.Source = .own, quiet: Bool = false) -> Bool {
        pruneForBand()
        let normalized: String = CallStack.normalize(call)
        let result: CallStack.PushResult = stack.push(normalized, source: source, band: currentBand(),
                                                      evaluation: evaluate(normalized))
        switch result {
        case .added:
            if !quiet {
                status.show(CallStackTexts.pushedKey, .string(normalized))
            }
            return true
        case .alreadyStacked:
            if !quiet {
                status.show(CallStackTexts.alreadyKey, .string(normalized))
            }
            return true
        case .dupe:
            status.show(CallStackTexts.dupeKey, .string(normalized))
            return false
        case .blank:
            status.show(CallStackTexts.nothingKey)
            return false
        }
    }

    /// Takes the next call off the stack; an empty stack shows „Zásobník volaček je prázdný".
    public func pop(showEmpty: Bool = true) -> String? {
        pruneForBand()
        let evaluate = self.evaluate
        guard let call = stack.pop(order, evaluate: { evaluate($0) }) else {
            if showEmpty {
                status.show(CallStackTexts.emptyKey)
            }
            return nil
        }
        return call
    }

    /// Alt+D with an empty call field: the next call is deleted without working it. `false` = the stack is empty.
    @discardableResult
    public func removeTop() -> Bool {
        pruneForBand()
        let evaluate = self.evaluate
        guard let call = stack.removeTop(order, evaluate: { evaluate($0) }) else { return false }
        status.show(CallStackTexts.removedKey, .string(call))
        return true
    }

    /// A logged call leaves the stack.
    public func remove(_ call: String) {
        stack.remove(call)
    }

    /// `{CLRSTACK}`.
    public func clear() {
        stack.clear()
        status.show(CallStackTexts.clearedKey)
    }

    /// The active entry window's band changed (the preview follows every frequency change): with the option on,
    /// the calls of the old band are dropped.
    func noteBand(_ band: String) {
        guard !band.isEmpty, band != lastBand else { return }
        lastBand = band
        pruneForBand()
    }

    private func pruneForBand() {
        guard config.config.esm.callStackClearOnBandChange else { return }
        let band: String = currentBand()
        if stack.prune(band: band) {
            status.show(CallStackTexts.bandClearedKey)
        }
    }
}

/// The texts of the call stack (Czech keys of `lang_*.json`).
public enum CallStackTexts {
    static let pushedKey = "Do zásobníku: %s"
    static let alreadyKey = "%s už je v zásobníku"
    static let dupeKey = "%s je dupe — do zásobníku nejde"
    static let nothingKey = "Do zásobníku není co dát (pole volačky je prázdné)"
    static let removedKey = "Ze zásobníku smazána %s"
    static let clearedKey = "Zásobník volaček vymazán"
    static let bandClearedKey = "Jiné pásmo — zásobník volaček vymazán"
    static let emptyKey = "Zásobník volaček je prázdný"
    static let runOnlyKey = "%s: zásobník volaček jen v Run"
}
