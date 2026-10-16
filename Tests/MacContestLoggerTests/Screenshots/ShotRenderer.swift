import AppKit
import Foundation
@testable import MacContestLogger
@testable import MCLAppModel
import MCLCore
import SwiftUI

/// Renders one of the app's windows offscreen into a PNG: the window's SwiftUI view in an `NSHostingView` inside an
/// `NSWindow` that is never ordered onto the screen (no screen, screen saver or unlocked session is needed), light
/// appearance, the window's size from the manifest, drawn with `cacheDisplay` at 2× (the guide's images are 2×
/// screenshots). The title bar is drawn by the window's own frame view, so the image looks like the window.
@MainActor
struct ShotRenderer {

    let demo: ShotDemo
    let host: AppHost

    init(demo: ShotDemo) {
        self.demo = demo
        host = AppHost()
        host.adoptForRendering(demo.model)
    }

    /// The windows the renderer knows (`window` in `docs/screenshots.json`).
    static let windows: Set<String> = ["bandmap", "statistics", "score", "log"]

    /// Prepares the window's state and returns its view and title.
    func scene(_ window: String) async throws -> (view: AnyView, title: String) {
        let app: AppModel = demo.model
        let language: LanguageModel = app.language
        switch window {
        case "bandmap":
            app.bandmap.windowOpened()
            return (AnyView(BandmapWindowView(host: host)), language.tr("Bandmapa"))
        case "statistics":
            app.statistics.open()
            await runMainQueue()
            await app.statistics.settle()
            return (AnyView(StatisticsWindowView(host: host)), language.tr("Statistiky"))
        case "score":
            app.scoreWindow.open()
            await runMainQueue()
            await app.scoreWindow.settle()
            return (AnyView(ScoreWindowView(host: host)), app.scoreWindow.windowTitle)
        case "log":
            return (AnyView(LogWindowView(host: host)), language.tr("Přehled spojení"))
        default:
            throw ShotError.render("unknown window \(window)")
        }
    }

    /// Every subview of `view` of type `T`, depth first.
    static func subviews<T: NSView>(of view: NSView, as type: T.Type) -> [T] {
        var out: [T] = []
        for child in view.subviews {
            if let match = child as? T {
                out.append(match)
            }
            out += subviews(of: child, as: type)
        }
        return out
    }

    /// The PNG of `shot`.
    func render(_ shot: ShotManifest.Shot) async throws -> Data {
        let (view, title) = try await scene(shot.window)
        let size = CGSize(width: shot.width, height: shot.height)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.title = title
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        window.setContentSize(size)
        // Let SwiftUI run its appear actions, model updates and layout passes (only main-queue turns, no waiting
        // on time: the models are already settled).
        for _ in 0..<12 {
            hosting.layoutSubtreeIfNeeded()
            await runMainQueue()
            await Task.yield()
        }
        await demo.model.statistics.settle()
        await demo.model.scoreWindow.settle()
        for _ in 0..<6 {
            hosting.layoutSubtreeIfNeeded()
            await runMainQueue()
        }
        // Tables from their first row: a row scrolled under the floating header would show through it (the header's
        // translucent material is not drawn offscreen).
        for table in Self.subviews(of: hosting, as: NSTableView.self) where table.numberOfRows > 0 {
            table.scrollRowToVisible(0)
        }
        hosting.layoutSubtreeIfNeeded()
        // The frame view draws the title bar and the content; fall back to the content alone.
        let target: NSView = hosting.superview ?? hosting
        target.layoutSubtreeIfNeeded()
        let bounds: CGRect = target.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
                                         pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else {
            throw ShotError.render("no bitmap for \(shot.name)")
        }
        rep.size = bounds.size
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            target.cacheDisplay(in: bounds, to: rep)
        }
        window.contentView = nil
        window.close()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw ShotError.render("no PNG for \(shot.name)")
        }
        return png
    }
}
