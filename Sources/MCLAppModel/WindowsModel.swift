import Foundation
import MCLCore
import Observation

/// Which tool windows are open (Kotlin `showXxx` flags of `AppState`), persisted in `config.openWindows` with the
/// v1.1.1 ids so the windows reopen after a restart (`KApp:153-193`).
///
/// The app opens the ids of `implemented`; every other id in the config is kept as it is, so a later feature
/// (or the JVM version sharing the file) still finds its windows.
@Observable @MainActor
public final class WindowsModel {

    /// Kotlin's order of the saved ids (`App.kt` `buildList`); `mult:<kind>` windows follow, then ids Kotlin does
    /// not know (kept, appended).
    public static let kotlinOrder: [String] = [
        "log", "catLog", "availMult", "dxCluster", "bandmap", "blacklist", "hamqthLog", "rate", "skeds", "score",
        "movemults", "dupesheet", "rotator", "statistics", "propagation", "bandnotes", "cwkeyboard", "cwreader",
        "digitalinterface", "wsjtxdecodes", "netstatus", "chat", "partner", "waterfall", "defeditor", "qtc",
        "worldmap", "worldmap-dxcc",
    ]

    /// Window ids the app can open (`log`, `defeditor` and `profiles`, the radio tool windows, the
    /// spot windows, the network and integration windows).
    public static let implemented: Set<String> = Set([
        "log", "defeditor", "profiles", "catLog", "rotator", "cwkeyboard", "cwreader", "digitalinterface", "waterfall",
        "dxCluster", "bandmap", "availMult", "blacklist", "netstatus", "chat", "partner", "wsjtxdecodes", "hamqthLog",
    ]).union(infoToolWindows)

    /// The info and tool windows: the Info window (`rate`), the goal editor and the goals from an
    /// earlier log, the statistics, score, dupesheet, skeds, QTC, the simulator, the band notes, the move
    /// multipliers, the propagation forecast, the world map (`worldmap`, `worldmap-dxcc` = the same window opened in
    /// DXCC mode) and one window per multiplier kind (`mult:<kind>`).
    public static let infoToolWindows: Set<String> = Set([
        "rate", "goals", "goals-from-log", "statistics", "score", "dupesheet", "skeds", "qtc", "simulator",
        "bandnotes", "movemults", "propagation", "worldmap", "worldmap-dxcc",
    ]).union(multWindowIds)

    /// `mult:<kind>` for every kind of the multiplier grids (Kotlin `openMultWindows`).
    public static let multWindowIds: Set<String> = Set(MultGridLayout.kinds.map { "mult:" + $0 })

    /// The id of the scene that shows a window id: the world map has one window for its two saved ids.
    public static func sceneId(for id: String) -> String {
        id == "worldmap-dxcc" ? "worldmap" : id
    }

    /// The windows of the spots and the cluster: the app layer closes them when the model drops their id (the
    /// DX Cluster shortcut toggles its window).
    public static let spotWindows: [String] = ["dxCluster", "bandmap", "availMult", "blacklist"]

    /// The menu items that open a tool window (Kotlin `showXxx = true`, `App.kt:645-662`) and the window ids they
    /// open; the ids differ from the menu ids where Kotlin's `config.openWindows` ids are camel-cased.
    public static let menuWindows: [String: String] = [
        "window.catlog": "catLog", "window.rotator": "rotator", "window.cwkeyboard": "cwkeyboard",
        "window.cwreader": "cwreader", "window.digitalinterface": "digitalinterface", "window.waterfall": "waterfall",
        "window.dxcluster": "dxCluster", "window.bandmap": "bandmap", "window.availmult": "availMult",
        "window.blacklist": "blacklist", "window.netstatus": "netstatus", "window.chat": "chat",
        "window.partner": "partner", "window.wsjtxdecodes": "wsjtxdecodes", "window.hamqthlog": "hamqthLog",
        "window.rate": "rate", "window.skeds": "skeds", "window.score": "score", "window.movemults": "movemults",
        "window.dupesheet": "dupesheet", "window.statistics": "statistics", "window.qtc": "qtc",
        "window.propagation": "propagation", "window.bandnotes": "bandnotes", "window.simulator": "simulator",
        "mult.dxcc": "mult:dxcc", "mult.grid": "mult:grid", "mult.itu": "mult:itu", "mult.cq": "mult:cq",
        "mult.districts": "mult:districts", "mult.other": "mult:other", "mult.sections": "mult:sections",
    ]

    /// Windows Kotlin never saves in `config.openWindows` (their `showXxx` flag starts `false`): `profiles`
    /// (`showProfiles`, `AS:2491`), the simulator and the two goal windows. They are open in `openIds` for this run
    /// only.
    public static let notPersisted: Set<String> = ["profiles", "simulator", "goals", "goals-from-log"]

    /// Open window ids (Kotlin `config.openWindows`).
    public private(set) var openIds: [String]

    /// Called after a window id was closed (the user's close of its window): a model that must stop with its window
    /// (the simulator) hooks in here, so the stop does not depend on the view's lifecycle.
    @ObservationIgnored var onClosed: (String) -> Void = { _ in }

    @ObservationIgnored private let config: ConfigModel

    init(config: ConfigModel) {
        self.config = config
        self.openIds = config.config.openWindows
    }

    /// Kotlin `logSearchRequest`: a search the log window takes over (and clears) when it shows; `""` = clear the
    /// search.
    public var logSearchRequest: String?

    /// Kotlin `findInLog(call)` (Ctrl+F, `AS:932-936`): opens the log window searching `call:<CALL>` (Kotlin
    /// `trim().uppercase()`), a blank call clears the search.
    public func findInLog(_ call: String) {
        setOpen("log", true)
        logSearchRequest = KotlinStrings.isBlank(call) ? "" : "call:" + KotlinStrings.uppercase(KotlinStrings.trim(call))
    }

    /// A window the app layer opens or brings to the front (`openWindow(id:)`), with a serial so the same window
    /// asked for twice is still a change. Used by windows that are not in `openIds` (the Settings window,
    /// No persisted state, no reopening after a restart).
    public struct WindowRequest: Equatable, Sendable {
        public let id: String
        public let serial: Int
    }

    /// The last window request (`requestWindow`).
    public private(set) var windowRequest: WindowRequest?

    /// Asks the app layer to open `id` or bring it to the front.
    public func requestWindow(_ id: String) {
        windowRequest = WindowRequest(id: id, serial: (windowRequest?.serial ?? 0) + 1)
    }

    public func isOpen(_ id: String) -> Bool {
        openIds.contains(id)
    }

    /// The world map opened or closed (Kotlin `showWorldMap` with `worldMapStartDxcc`): the saved id is `worldmap-dxcc`
    /// for the DXCC mode, `worldmap` otherwise; the other one never stays beside it. One save.
    public func setWorldMapOpen(_ open: Bool, dxcc: Bool = false) {
        var ids: [String] = openIds.filter { $0 != "worldmap" && $0 != "worldmap-dxcc" }
        if open {
            ids.append(dxcc ? "worldmap-dxcc" : "worldmap")
        }
        replaceIds(ids)
    }

    /// Whether the world map is open in either of its two ids.
    public var isWorldMapOpen: Bool {
        isOpen("worldmap") || isOpen("worldmap-dxcc")
    }

    /// Opens or closes a window; a changed set is saved (failure: „Uložení stavu oken selhalo (%s)"). A window of
    /// `notPersisted` changes only `openIds`.
    public func setOpen(_ id: String, _ open: Bool) {
        let wasOpen: Bool = openIds.contains(id)
        defer {
            if wasOpen && !open {
                onClosed(id)
            }
        }
        var ids: [String] = openIds.filter { $0 != id }
        if open {
            ids.append(id)
        }
        replaceIds(ids)
    }

    private func replaceIds(_ ids: [String]) {
        let ordered: [String] = Self.ordered(ids)
        openIds = ordered
        let saved: [String] = ordered.filter { !Self.notPersisted.contains($0) }
        guard saved != config.config.openWindows else { return }
        config.config.openWindows = saved
        config.save(failureKey: "Uložení stavu oken selhalo (%s)")
    }

    /// Kotlin order: known ids, then `mult:` windows, then unknown ids — each once, in their previous order.
    static func ordered(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        let unique: [String] = ids.filter { seen.insert($0).inserted }
        let known: [String] = kotlinOrder.filter { unique.contains($0) }
        let mult: [String] = unique.filter { $0.hasPrefix("mult:") }
        let others: [String] = unique.filter { !kotlinOrder.contains($0) && !$0.hasPrefix("mult:") }
        return known + mult + others
    }
}
