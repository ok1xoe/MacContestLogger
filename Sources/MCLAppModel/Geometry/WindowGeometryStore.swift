import CoreGraphics
import Foundation
import MCLCore

/// Window geometry in `config.windowGeometry[id]`, compatible with v1.1.1 (Kotlin `rememberPersistentWindowState`):
/// the saved position (and optionally size) is read when a window opens, clamped onto the connected
/// displays, and written back 500 ms after the window stops moving.
///
/// The config keeps AWT coordinates; the conversion to AppKit goes through `AwtCoordinates`. The clock is injected
/// (`RescoreClock` is the core's main-actor timer protocol; tests advance a fake one).
@MainActor
public final class WindowGeometryStore {

    /// Kotlin `debounce(500)`.
    public static let debounceMilliseconds = 500

    private let config: ConfigModel
    private let clock: any RescoreClock
    private var pending: [String: (timer: any RescoreTimer, geometry: WindowGeometry)] = [:]

    public init(config: ConfigModel, clock: any RescoreClock) {
        self.config = config
        self.clock = clock
    }

    /// The size a window opens with: the saved one when sizes persist and one is saved, otherwise `defaultSize`.
    public func initialSize(id: String, defaultSize: CGSize, persistSize: Bool) -> CGSize {
        if persistSize, let saved = config.config.windowGeometry[id], saved.hasSize() {
            return CGSize(width: saved.width, height: saved.height)
        }
        return defaultSize
    }

    /// The AppKit frame a window opens with, or `nil` = let the system place it (nothing saved, or the saved
    /// position lies on no connected display — Kotlin `WindowPosition.PlatformDefault`).
    ///
    /// - Parameters:
    ///   - screens: AppKit frames of the displays (`NSScreen.screens.map(\.frame)`).
    ///   - mainScreenHeight: height of the main display (`NSScreen.screens[0].frame.maxY`).
    public func initialFrame(id: String, defaultSize: CGSize, persistSize: Bool, screens: [CGRect],
                             mainScreenHeight: CGFloat) -> CGRect? {
        guard let saved = config.config.windowGeometry[id] else { return nil }
        let size: CGSize = initialSize(id: id, defaultSize: defaultSize, persistSize: persistSize)
        let width = Int(size.width)
        let height = Int(size.height)
        let awtScreens: [CGRect] = screens.map { AwtCoordinates.fromAppKit($0, mainScreenHeight: mainScreenHeight) }
        guard let clamped = WindowPlacement.clampToScreens(x: saved.x, y: saved.y, width: width, height: height,
                                                           screens: awtScreens) else {
            return nil
        }
        let awt = CGRect(x: clamped.x, y: clamped.y, width: width, height: height)
        return AwtCoordinates.toAppKit(awt, mainScreenHeight: mainScreenHeight)
    }

    /// The window moved or resized (`windowDidMove`/`windowDidResize`): after 500 ms without another change the
    /// geometry is saved (`persistSize == false` stores the size as 0, Kotlin's „position only").
    public func windowChanged(id: String, frame: CGRect, persistSize: Bool, mainScreenHeight: CGFloat) {
        let awt: CGRect = AwtCoordinates.fromAppKit(frame, mainScreenHeight: mainScreenHeight)
        let geometry = WindowGeometry(x: Self.truncate(awt.minX), y: Self.truncate(awt.minY),
                                      width: persistSize ? Self.truncate(awt.width) : 0,
                                      height: persistSize ? Self.truncate(awt.height) : 0)
        pending[id]?.timer.cancel()
        let timer = clock.schedule(afterMilliseconds: Self.debounceMilliseconds) { [weak self] in
            self?.commit(id)
        }
        pending[id] = (timer, geometry)
    }

    /// Saves every pending change at once (quit).
    public func flush() {
        for id in pending.keys.sorted() {
            pending[id]?.timer.cancel()
            commit(id)
        }
    }

    private func commit(_ id: String) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        config.config.windowGeometry[id] = entry.geometry
        config.save(failureKey: "Uložení geometrie okna selhalo (%s)")
    }

    /// Kotlin `Dp.value.toInt()`: toward zero.
    private static func truncate(_ value: CGFloat) -> Int {
        Int(value.rounded(.towardZero))
    }
}
