import Foundation
import MCLCore

/// The N1MM+ Telnet window's Spot Comment and Special Calls tabs and „Spot all S&P QSOs": applied and saved at once.
/// Spotting to the public cluster stays opt-in: „Spot all S&P QSOs" is off by default.
extension DxClusterModel {

    // MARK: - spot comment

    /// N1MM „Comment For All Spots" (with `SpotComment` macros).
    public var spotComment: String {
        config.config.dxCluster.spotComment
    }

    public func setSpotComment(_ text: String) {
        // One line: a line end would make the cluster command several commands (and is never sent).
        let line: String = text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        save(\.spotComment, line)
    }

    /// N1MM Config → „Spot all S&P QSOs".
    public var spotAllSpQsos: Bool {
        config.config.dxCluster.spotAllSpQsos
    }

    public func setSpotAllSpQsos(_ on: Bool) {
        save(\.spotAllSpQsos, on)
    }

    // MARK: - special calls

    public var specialCalls: [String] {
        config.config.dxCluster.specialCalls
    }

    /// The list as edited (one call per line, or separated by commas or spaces).
    public func setSpecialCalls(text: String) {
        save(\.specialCalls, SpecialCalls.parse(text))
    }

    public var specialCallsIncludeBonus: Bool {
        config.config.dxCluster.specialCallsIncludeBonus
    }

    public func setSpecialCallsIncludeBonus(_ on: Bool) {
        save(\.specialCallsIncludeBonus, on)
    }

    /// Import: the calls of an N1MM file (or a plain list) are added to the list; returns how many were new.
    @discardableResult
    public func importSpecialCalls(_ text: String) -> Int {
        let current: [String] = specialCalls
        let known: Set<String> = Set(current)
        let added: [String] = SpecialCalls.parse(text).filter { !known.contains($0) }
        save(\.specialCalls, current + added)
        status.show("Zvláštní volačky: přidáno %s", .int(added.count))
        return added.count
    }

    /// Export: N1MM's file of the list.
    public var specialCallsFileText: String {
        SpecialCalls.export(specialCalls)
    }

    public func clearSpecialCalls() {
        save(\.specialCalls, [])
    }

    private func save<Value: Equatable>(_ field: WritableKeyPath<DxClusterConfig, Value>, _ value: Value) {
        guard config.config.dxCluster[keyPath: field] != value else { return }
        config.config.dxCluster[keyPath: field] = value
        config.save(failureKey: ClusterTexts.macroSaveFailedKey)
    }
}
